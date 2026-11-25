import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../document/deferred_notebook_page.dart';
import '../document/notebook.dart';
import '../document/notebook_repository.dart';
import '../document/revision.dart';
import '../document/folders.dart';

class LibraryController extends ChangeNotifier {
  LibraryController({
    required this.repository,
    required this.deviceId,
    FolderRepository? folders,
  }) : folderRepository =
           folders ??
           (repository is FolderRepository
               ? repository as FolderRepository
               : null);
  final FolderRepository? folderRepository;
  List<NoteFolder> folders = [];
  String? currentFolderId;
  List<NoteFolder> get childFolders =>
      folders.where((f) => f.parentId == currentFolderId).toList();
  List<NoteFolder> get breadcrumbs => pathFor(currentFolderId);
  List<NoteFolder> pathFor(String? id) {
    final result = <NoteFolder>[];
    final seen = <String>{};
    while (id != null && seen.add(id)) {
      final matches = folders.where((f) => f.id == id);
      if (matches.isEmpty) break;
      final folder = matches.first;
      result.insert(0, folder);
      id = folder.parentId;
    }
    return result;
  }

  void openFolder(String? id) {
    if (id != null && !folders.any((f) => f.id == id)) {
      throw StateError('La carpeta no existe');
    }
    currentFolderId = id;
    notifyListeners();
  }

  Future<NoteFolder> createFolder(
    String name, {
    Object? parentId = _currentFolder,
  }) async {
    final folder = NoteFolder(
      id: const Uuid().v4(),
      name: name.trim(),
      parentId: identical(parentId, _currentFolder)
          ? currentFolderId
          : parentId as String?,
    );
    await folderRepository!.saveFolder(folder);
    await refresh();
    return folders.firstWhere((f) => f.id == folder.id);
  }

  Future<void> renameFolder(NoteFolder folder, String name) async {
    final latest = folders.firstWhere((f) => f.id == folder.id);
    await folderRepository!.saveFolder(
      latest.copyWith(name: name.trim(), updatedAt: DateTime.now().toUtc()),
    );
    await refresh();
  }

  Future<void> moveFolder(NoteFolder folder, String? parentId) async {
    final latest = folders.firstWhere((f) => f.id == folder.id);
    await folderRepository!.saveFolder(
      latest.copyWith(parentId: parentId, updatedAt: DateTime.now().toUtc()),
    );
    await refresh();
  }

  Future<void> moveNotebook(CatalogEntry entry, String? folderId) async {
    if (folderId != null && !folders.any((f) => f.id == folderId)) {
      throw StateError('La carpeta de destino no existe');
    }
    final document = await _loadEditableEntry(entry);
    await updateNotebook(
      document,
      document.notebook.copyWith(folderId: folderId),
    );
  }

  Future<void> renameNotebook(CatalogEntry entry, String title) async {
    final document = await _loadEditableEntry(entry);
    await updateNotebook(document, document.notebook.copyWith(title: title));
  }

  Future<DocumentEntry> _loadEditableEntry(CatalogEntry entry) async {
    final document = await loadEntry(entry);
    if (document == null) throw StateError('El apunte ya no está disponible.');
    return document;
  }

  Future<void> updateNotebook(DocumentEntry entry, Notebook book) async {
    await repository.commit(
      Revision(
        id: const Uuid().v4(),
        deviceId: deviceId,
        parentId: entry.headId,
        createdAt: DateTime.now().toUtc(),
        notebook: book.copyWith(updatedAt: DateTime.now().toUtc()),
      ),
    );
    await refresh();
  }

  Future<void> deleteNotebook(CatalogEntry entry) async {
    final now = DateTime.now().toUtc();
    await repository.commit(
      Revision(
        id: Revision.deletionId(const Uuid().v4()),
        deviceId: deviceId,
        parentId: entry.headId,
        createdAt: now,
        // The sync protocol requires a notebook with a page. The retained
        // parent holds the content, so the deletion depends on no assets.
        notebook: Notebook.blank(
          id: entry.documentId,
          pageId: entry.firstPageId,
          title: entry.title,
          pattern: PaperPattern.blank,
          now: now,
        ),
      ),
    );
    await refresh();
  }

  final NotebookRepository repository;
  final String deviceId;
  List<CatalogEntry> entries = [];
  final _visiblePreviews = <(String, String), WeakReference<NotebookPage>>{};
  final _pendingPreviews = <(String, String), Future<NotebookPage?>>{};
  bool _disposed = false;

  NotebookPage? _loadedPreview(CatalogEntry entry) =>
      _visiblePreviews[(entry.documentId, entry.headId)]?.target;

  NotebookPage? visiblePreview(CatalogEntry entry) {
    final page = _loadedPreview(entry);
    if (page == null ||
        page.background.pattern == null ||
        page.objects.any((object) => object.assetId != null)) {
      return null;
    }
    return page;
  }

  Future<DocumentEntry?> loadEntry(CatalogEntry entry) async {
    final notebook = await repository.load(
      entry.documentId,
      headId: entry.headId,
    );
    return notebook == null ? null : entry.withNotebook(notebook);
  }

  Future<DocumentEntry?> loadForEditing(
    CatalogEntry entry, {
    required int initialPageIndex,
  }) async {
    if (_disposed) return null;
    if (repository case final EditableNotebookRepository editable) {
      NotebookPage? preview;
      if (initialPageIndex == 0) {
        preview = _loadedPreview(entry);
        final pending = _pendingPreviews[(entry.documentId, entry.headId)];
        if (preview == null && pending != null) {
          try {
            preview = await pending;
          } catch (_) {
            // A failed thumbnail should not prevent the authoritative read.
          }
          if (_disposed) return null;
        }
      }
      final decodedPreview = preview is DeferredNotebookPage && preview.isReady
          ? preview
          : null;
      final notebook = await editable.loadForEditing(
        entry.documentId,
        headId: entry.headId,
        initialPageIndex: initialPageIndex,
        preparedPagePayload: decodedPreview?.encoded,
      );
      if (notebook == null) return null;
      final active =
          notebook.pages[initialPageIndex.clamp(0, notebook.pages.length - 1)];
      if (active is DeferredNotebookPage && !active.isReady) {
        if (decodedPreview == null ||
            !active.reuseDecodedPage(decodedPreview)) {
          await active.prepare();
        }
      }
      return entry.withNotebook(notebook);
    }
    return loadEntry(entry);
  }

  Future<NotebookPage?> loadPreview(CatalogEntry entry) {
    if (_disposed) return Future.value();
    final key = (entry.documentId, entry.headId);
    return _pendingPreviews.putIfAbsent(
      key,
      () => _loadPreview(entry).whenComplete(() {
        _pendingPreviews.remove(key);
      }),
    );
  }

  Future<NotebookPage?> _loadPreview(CatalogEntry entry) async {
    final NotebookPage? page;
    if (repository case final NotebookCatalogRepository catalog) {
      page = await catalog.loadPreview(entry.documentId, headId: entry.headId);
    } else {
      page = (await loadEntry(entry))?.notebook.pages.first;
    }
    if (page != null && !_disposed) {
      // The visible tile holds the page. Leave it collectible with the tile.
      final key = (entry.documentId, entry.headId);
      _visiblePreviews.remove(key);
      _visiblePreviews[key] = WeakReference(page);
      if (_visiblePreviews.length > 12) {
        _visiblePreviews.remove(_visiblePreviews.keys.first);
      }
    }
    return page;
  }

  @override
  void dispose() {
    _disposed = true;
    _pendingPreviews.clear();
    _visiblePreviews.clear();
    super.dispose();
  }

  Future<void> refresh() async {
    if (repository case final NotebookCatalogRepository catalog) {
      entries = await catalog.listCatalog();
    } else {
      entries = [
        for (final document in await repository.list())
          CatalogEntry.fromDocument(document),
      ];
    }
    folders = await folderRepository?.listFolders() ?? [];
    if (currentFolderId != null &&
        !folders.any((f) => f.id == currentFolderId)) {
      currentFolderId = null;
    }
    notifyListeners();
  }

  Future<DocumentEntry> createNotebook({
    required String title,
    required String subject,
    required PaperPattern pattern,
  }) async {
    final book = Notebook.blank(
      id: const Uuid().v4(),
      pageId: const Uuid().v4(),
      title: title.trim().isEmpty ? 'Cuaderno sin título' : title.trim(),
      subject: subject.trim(),
      pattern: pattern,
      now: DateTime.now().toUtc(),
      folderId: currentFolderId,
    );
    return add(book);
  }

  Future<DocumentEntry> add(Notebook book) async {
    final revision = Revision(
      id: const Uuid().v4(),
      deviceId: deviceId,
      parentId: null,
      createdAt: DateTime.now().toUtc(),
      notebook: book,
    );
    await repository.commit(revision);
    await refresh();
    return entries
        .firstWhere((e) => e.headId == revision.id)
        .withNotebook(book);
  }

  List<CatalogEntry> filtered({String query = '', String subject = ''}) {
    final normalized = _normalize(query);
    final folderIds = currentFolderId == null
        ? {for (final folder in folders) folder.id}
        : const <String>{};
    return entries.where((entry) {
      final folderId = entry.folderId;
      return (folderId == currentFolderId ||
              (currentFolderId == null && !folderIds.contains(folderId))) &&
          (subject.isEmpty || entry.subject == subject) &&
          (normalized.isEmpty || _normalize(entry.title).contains(normalized));
    }).toList();
  }

  static String _normalize(String text) {
    const accents = 'áéíóúüñ';
    const plain = 'aeiouun';
    var normalized = text.toLowerCase();
    for (var i = 0; i < accents.length; i++) {
      normalized = normalized.replaceAll(accents[i], plain[i]);
    }
    return normalized;
  }
}

const _currentFolder = Object();
