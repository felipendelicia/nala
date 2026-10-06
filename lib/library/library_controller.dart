import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
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

  Future<void> moveNotebook(DocumentEntry entry, String? folderId) async {
    if (folderId != null && !folders.any((f) => f.id == folderId)) {
      throw StateError('La carpeta de destino no existe');
    }
    await updateNotebook(entry, entry.notebook.copyWith(folderId: folderId));
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

  final NotebookRepository repository;
  final String deviceId;
  List<DocumentEntry> entries = [];
  Future<void> refresh() async {
    entries = await repository.list();
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
    return entries.firstWhere((e) => e.headId == revision.id);
  }

  List<DocumentEntry> filtered({String query = '', String subject = ''}) =>
      entries
          .where(
            (e) =>
                (e.notebook.folderId == currentFolderId ||
                    (currentFolderId == null &&
                        !folders.any((f) => f.id == e.notebook.folderId))) &&
                (subject.isEmpty || e.notebook.subject == subject) &&
                _normalize(e.notebook.title).contains(_normalize(query)),
          )
          .toList();
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
