import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' show PdfPasswordException;
import '../bootstrap.dart';
import '../backup/backup_dialog.dart';
import '../backup/backup_files.dart';
import '../backup/backup_service.dart';
import '../document/notebook.dart';
import '../document/revision.dart';
import '../document/folders.dart';
import 'folder_dialog.dart';
import '../document/asset_store.dart';
import '../workspace/document_workspace.dart';
import '../workspace/workspace_opening_screen.dart';
import '../search/notebook_search_dialog.dart';
import '../search/search_service.dart';
import '../editor/paper_canvas.dart';
import '../ui/app_theme.dart';
import '../ui/appearance.dart';
import 'library_controller.dart';
import 'notebook_dialog.dart';
import '../pdf/password_dialog.dart';
import '../pdf/pdf_page_background.dart';
import '../pdf/pdf_service.dart';
import '../account/cloud_controller.dart';
import '../account/cloud_panel.dart';

const _notebookTileMaxWidth = 360.0;
const _notebookPreviewSidePadding = 40.0;
const _workspaceTransitionDuration = Duration(milliseconds: 120);

AnimationStyle? _libraryMenuAnimation(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.android
    ? AnimationStyle.noAnimation
    : null;

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.services,
    this.cloud,
    this.backupFiles,
  });
  final AppServices services;
  final CloudController? cloud;
  final BackupFiles? backupFiles;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String query = '', subject = '';
  bool importing = false;
  bool _openingNotebook = false;

  Future<void> _openCatalogEntry(
    CatalogEntry entry, {
    int initialPageIndex = 0,
  }) async {
    if (_openingNotebook) return;
    _openingNotebook = true;
    final services = widget.services;
    try {
      if (Theme.of(context).platform == TargetPlatform.android) {
        final cloud = widget.cloud;
        await _pushWorkspace(
          (_) => WorkspaceOpeningScreen(
            services: services,
            cloud: cloud,
            title: entry.title,
            initialPageIndex: initialPageIndex,
            preview: initialPageIndex == 0
                ? services.library.visiblePreview(entry)
                : null,
            loadEntry: () async {
              final document = await services.library.loadForEditing(
                entry,
                initialPageIndex: initialPageIndex,
              );
              return mounted && identical(services, widget.services)
                  ? document
                  : null;
            },
          ),
        );
        return;
      }
      final document = await services.library.loadEntry(entry);
      if (!mounted || !identical(services, widget.services)) return;
      if (document == null) {
        _error(StateError('El apunte ya no está disponible.'));
        return;
      }
      await _open(document, initialPageIndex: initialPageIndex);
    } catch (error) {
      if (mounted && identical(services, widget.services)) _error(error);
    } finally {
      _openingNotebook = false;
    }
  }

  Future<void> _open(DocumentEntry entry, {int initialPageIndex = 0}) {
    final services = widget.services;
    final cloud = widget.cloud;
    return _pushWorkspace(
      (_) => WorkspaceScreen(
        services: services,
        initialEntry: entry,
        initialPageIndex: initialPageIndex,
        cloud: cloud,
      ),
    );
  }

  Future<void> _pushWorkspace(WidgetBuilder workspace) async {
    final services = widget.services;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : _workspaceTransitionDuration;
    CurvedAnimation? workspaceMotion;
    final route = Theme.of(context).platform == TargetPlatform.android
        ? PageRouteBuilder<void>(
            pageBuilder: (context, _, _) => workspace(context),
            transitionDuration: duration,
            reverseTransitionDuration: duration,
            transitionsBuilder: (_, animation, _, child) {
              if (reduceMotion) return child;
              final motion = workspaceMotion ??= CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeOutCubic.flipped,
              );
              return FadeTransition(opacity: motion, child: child);
            },
          )
        : MaterialPageRoute<void>(builder: workspace);
    await Navigator.of(context).push(route);
    // The popped result arrives while the reverse animation is still running.
    await route.completed;
    workspaceMotion?.dispose();
    if (mounted && identical(services, widget.services)) {
      await services.library.refresh();
    }
  }

  Future<bool> _saveRecognized(
    String notebookId,
    String pageId,
    String fingerprint,
    String text,
  ) async {
    final services = widget.services;
    final heads = (await services.repository.list())
        .where((e) => e.notebook.id == notebookId)
        .toList();
    if (heads.length != 1) return false;
    final entry = heads.single;
    final page = entry.notebook.pages.where((p) => p.id == pageId).firstOrNull;
    if (page == null || await pageRecognitionFingerprint(page) != fingerprint) {
      return false;
    }
    // Hashing is asynchronous. Recheck the revision before committing the cache.
    final latest = (await services.repository.list())
        .where((e) => e.notebook.id == notebookId)
        .toList();
    if (!mounted ||
        !identical(services, widget.services) ||
        latest.length != 1 ||
        latest.single.headId != entry.headId) {
      return false;
    }
    await services.library.updateNotebook(
      entry,
      entry.notebook.copyWith(
        pages: [
          for (final p in entry.notebook.pages)
            p.id != pageId
                ? p
                : p.copyWith(
                    recognizedText: text,
                    recognitionFingerprint: fingerprint,
                  ),
        ],
      ),
    );
    return true;
  }

  Future<void> _search() async {
    final services = widget.services;
    final searched = {
      for (final entry in await services.repository.list())
        entry.notebook.id: entry,
    };
    if (!mounted || !identical(services, widget.services)) return;
    final hit = await showDialog<SearchHit>(
      context: context,
      builder: (_) => NotebookSearchDialog(
        notebooks: [for (final entry in searched.values) entry.notebook],
        pdf: services.pdf,
        assets: services.assets,
        onRecognized: _saveRecognized,
      ),
    );
    if (hit == null || !mounted || !identical(services, widget.services)) {
      return;
    }
    await services.library.refresh();
    if (!mounted || !identical(services, widget.services)) return;
    final heads = services.library.entries
        .where((entry) => entry.documentId == hit.notebookId)
        .toList();
    final searchedHead = searched[hit.notebookId]?.headId;
    final entry =
        heads.where((head) => head.headId == searchedHead).firstOrNull ??
        heads.singleOrNull;
    if (entry != null) {
      await _openCatalogEntry(entry, initialPageIndex: hit.pageIndex);
    }
  }

  Future<void> _backup() async {
    final services = widget.services;
    final result = await showBackupDialog(
      context,
      service: BackupService(
        root: services.root,
        repository: services.repository,
        assets: services.assets,
        deviceId: services.deviceId,
        appearanceFile: AppearanceScope.of(context)?.file,
      ),
      files: widget.backupFiles ?? NativeBackupFiles(),
      onRestored: (result) async {
        await services.library.refresh();
        if (result.preferencesRestored) {
          await services.toolbarPreferences?.reload();
          await services.penPreferences?.reload();
        }
      },
    );
    if (result != null && mounted) _navigate(result.recoveryFolderId);
  }

  Future<void> _create() async {
    final result = await showDialog<NotebookDraft>(
      context: context,
      builder: (_) => const NotebookDialog(),
    );
    if (result == null || !mounted) return;
    try {
      final entry = await widget.services.library.createNotebook(
        title: result.title,
        subject: result.subject,
        pattern: result.pattern,
      );
      if (mounted) await _open(entry);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo crear el cuaderno. Revisá el espacio del dispositivo.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _import() async {
    setState(() => importing = true);
    try {
      final file = await widget.services.files.openPdf();
      if (file == null || !mounted) return;
      String? password;
      while (mounted) {
        try {
          final note = await widget.services.pdf.importDocument(
            bytes: file.bytes,
            title: file.name.replaceFirst(
              RegExp(r'\.pdf$', caseSensitive: false),
              '',
            ),
            documentId: const Uuid().v4(),
            newId: const Uuid().v4,
            now: DateTime.now(),
            password: password,
          );
          final entry = await widget.services.library.add(
            note.copyWith(folderId: widget.services.library.currentFolderId),
          );
          if (mounted) setState(() => importing = false);
          if (mounted) await _open(entry);
          break;
        } on PdfPasswordException {
          if (!mounted) return;
          password = await askPdfPassword(context, incorrect: password != null);
          if (password == null) return;
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo abrir ese PDF. Comprobá el archivo y el espacio del dispositivo.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> _folderAction(NoteFolder? folder, String action) async {
    final library = widget.services.library;
    try {
      if (action == 'create' || action == 'rename') {
        final name = await showDialog<String>(
          context: context,
          builder: (_) => NameDialog(
            title: folder == null ? 'Nueva carpeta' : 'Renombrar carpeta',
            label: 'Nombre de la carpeta',
            value: folder?.name ?? '',
          ),
        );
        if (name == null) return;
        if (folder == null) {
          await library.createFolder(name);
        } else {
          await library.renameFolder(folder, name);
        }
      } else if (action == 'move') {
        final target = await showDialog<FolderDestination>(
          context: context,
          builder: (_) =>
              FolderPickerDialog(library: library, movingFolderId: folder!.id),
        );
        if (target != null) await library.moveFolder(folder!, target.id);
      } else if (action == 'delete') {
        await library.folderRepository!.deleteFolder(folder!.id);
        await library.refresh();
      }
    } catch (error) {
      _error(error);
    }
  }

  void _error(Object error) {
    if (!mounted) return;
    final message = error is StateError
        ? error.message.toString().replaceFirst(RegExp(r'^Bad state:\s*'), '')
        : 'No se pudo guardar el cambio. Revisá el espacio del dispositivo.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _noteAction(CatalogEntry entry, String action) async {
    final library = widget.services.library;
    bool sameLibrary() =>
        mounted && identical(library, widget.services.library);
    try {
      if (action == 'move') {
        final target = await showDialog<FolderDestination>(
          context: context,
          builder: (_) => FolderPickerDialog(library: library),
        );
        if (target != null && sameLibrary()) {
          await library.moveNotebook(entry, target.id);
        }
      } else if (action == 'delete') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('¿Eliminar apunte?'),
            content: Text(
              '«${entry.title}» se quitará de tu biblioteca y de los '
              'dispositivos sincronizados.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        );
        if (confirmed == true && sameLibrary()) {
          await library.deleteNotebook(entry);
        }
      } else if (action == 'rename') {
        final name = await showDialog<String>(
          context: context,
          builder: (_) => NameDialog(
            title: 'Renombrar apunte',
            label: 'Nombre del apunte',
            value: entry.title,
          ),
        );
        if (name != null && sameLibrary()) {
          await library.renameNotebook(entry, name);
        }
      }
    } catch (error) {
      _error(error);
    }
  }

  void _navigate(String? folder) {
    setState(() {
      query = '';
      subject = '';
    });
    widget.services.library.openFolder(folder);
  }

  ValueKey<(String, String?)> _tileKey(CatalogEntry entry) =>
      ValueKey((entry.documentId, entry.isConflict ? entry.headId : null));

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.services.library,
    builder: (context, _) {
      final library = widget.services.library;
      final entries = library.filtered(query: query, subject: subject);
      final tileIndices = {
        for (var index = 0; index < entries.length; index++)
          _tileKey(entries[index]): index,
      };
      final subjects =
          library.entries
              .map((e) => e.subject)
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      return Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/nala-icon.png',
                  width: 36,
                  height: 36,
                ),
              ),
              const SizedBox(width: 12),
              const Text('Nala', style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Buscar en todos los apuntes',
              onPressed: _search,
              icon: const Icon(Icons.manage_search_outlined),
            ),
            PopupMenuButton<String>(
              tooltip: 'Más opciones de la biblioteca',
              popUpAnimationStyle: _libraryMenuAnimation(context),
              onSelected: (action) {
                if (action == 'backup') _backup();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'backup',
                  child: Row(
                    children: [
                      Icon(Icons.backup_outlined, size: 20),
                      SizedBox(width: 12),
                      Flexible(child: Text('Backup de la biblioteca')),
                    ],
                  ),
                ),
              ],
            ),
            const AppearanceButton(),
            if (widget.cloud != null)
              CloudControls(cloud: widget.cloud!)
            else if (MediaQuery.sizeOf(context).width >= 850)
              const SizedBox(
                width: 270,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Guardado en este dispositivo',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
            else
              const Tooltip(
                message: 'Guardado en este dispositivo',
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Icon(Icons.offline_pin_outlined),
                ),
              ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              if (constraints.maxWidth >= 1100)
                SizedBox(
                  width: 224,
                  child: Material(
                    color: nalaSidebar,
                    child: ListTileTheme(
                      textColor: const Color(0xffdddddd),
                      iconColor: const Color(0xffcccccc),
                      selectedColor: Colors.white,
                      selectedTileColor: Colors.white12,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 24, 12, 20),
                            child: Text(
                              'Tu biblioteca',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          ListTile(
                            leading: const Icon(Icons.home_outlined),
                            title: const Text('Mis apuntes'),
                            selected: library.currentFolderId == null,
                            onTap: () => _navigate(null),
                          ),
                          for (final folder in library.folders)
                            Padding(
                              padding: EdgeInsets.only(
                                left:
                                    (library.pathFor(folder.id).length - 1) *
                                    12.0,
                              ),
                              child: ListTile(
                                leading: const Icon(
                                  Icons.folder_outlined,
                                  size: 20,
                                ),
                                title: Text(
                                  folder.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                selected: library.currentFolderId == folder.id,
                                onTap: () => _navigate(folder.id),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(
                    constraints.maxWidth >= 600 ? 28 : 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: () => _navigate(null),
                            icon: const Icon(Icons.home_outlined),
                            label: const Text('Mis apuntes'),
                          ),
                          for (final f in library.breadcrumbs)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.chevron_right, size: 18),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: math.min(
                                      320,
                                      constraints.maxWidth - 64,
                                    ),
                                  ),
                                  child: Tooltip(
                                    message: f.name,
                                    child: TextButton(
                                      onPressed: () => _navigate(f.id),
                                      child: Text(
                                        f.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        library.breadcrumbs.isEmpty
                            ? 'Tus apuntes'
                            : library.breadcrumbs.last.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${entries.length} ${entries.length == 1 ? 'apunte' : 'apuntes'} en esta carpeta',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: _create,
                            icon: const Icon(Icons.add),
                            label: const Text('Crear cuaderno'),
                          ),
                          OutlinedButton.icon(
                            onPressed: importing ? null : _import,
                            icon: importing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.picture_as_pdf_outlined),
                            label: Text(
                              importing ? 'Abriendo PDF…' : 'Abrir PDF',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: library.folderRepository == null
                                ? null
                                : () => _folderAction(null, 'create'),
                            icon: const Icon(Icons.create_new_folder_outlined),
                            label: const Text('Nueva carpeta'),
                          ),
                          SizedBox(
                            width: constraints.maxWidth < 500
                                ? constraints.maxWidth - 32
                                : 260,
                            child: TextField(
                              key: ValueKey(library.currentFolderId),
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.search),
                                hintText: 'Buscar en esta carpeta',
                              ),
                              onChanged: (s) => setState(() => query = s),
                            ),
                          ),
                          if (subjects.isNotEmpty)
                            SizedBox(
                              width: math.min(180, constraints.maxWidth - 32),
                              child: DropdownButton<String>(
                                isExpanded: true,
                                value: subject,
                                items: [
                                  const DropdownMenuItem(
                                    value: '',
                                    child: Tooltip(
                                      message: 'Todas las materias',
                                      child: Text(
                                        'Todas las materias',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  ...subjects.map(
                                    (s) => DropdownMenuItem(
                                      value: s,
                                      child: Tooltip(
                                        message: s,
                                        child: Text(
                                          s,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (s) =>
                                    setState(() => subject = s ?? ''),
                              ),
                            ),
                        ],
                      ),
                      if (library.childFolders.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: SizedBox(
                            height: 64,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                for (final folder in library.childFolders)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        OutlinedButton.icon(
                                          onPressed: () => _navigate(folder.id),
                                          icon: const Icon(
                                            Icons.folder_outlined,
                                          ),
                                          label: Text(folder.name),
                                        ),
                                        PopupMenuButton<String>(
                                          tooltip: 'Opciones de carpeta',
                                          popUpAnimationStyle:
                                              _libraryMenuAnimation(context),
                                          onSelected: (a) =>
                                              _folderAction(folder, a),
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(
                                              value: 'rename',
                                              child: Text('Renombrar'),
                                            ),
                                            PopupMenuItem(
                                              value: 'move',
                                              child: Text('Mover a…'),
                                            ),
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Text(
                                                'Eliminar carpeta vacía',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: entries.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.menu_book_outlined,
                                      size: 52,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      query.isEmpty
                                          ? 'Un nuevo apunte empieza acá'
                                          : 'No hay apuntes con esa búsqueda',
                                      style: const TextStyle(fontSize: 22),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Creá un cuaderno, una carpeta o abrí un PDF.',
                                    ),
                                  ],
                                ),
                              )
                            : GridView.builder(
                                gridDelegate:
                                    SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: _notebookTileMaxWidth,
                                      mainAxisExtent:
                                          constraints.maxHeight < 800
                                          ? 280
                                          : 320,
                                      crossAxisSpacing: 20,
                                      mainAxisSpacing: 20,
                                    ),
                                itemCount: entries.length,
                                findChildIndexCallback: (key) =>
                                    tileIndices[key],
                                itemBuilder: (_, index) => _NotebookTile(
                                  key: _tileKey(entries[index]),
                                  entry: entries[index],
                                  library: library,
                                  pdf: widget.services.pdf,
                                  assets: widget.services.assets,
                                  onTap: () =>
                                      _openCatalogEntry(entries[index]),
                                  onAction: (a) =>
                                      _noteAction(entries[index], a),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _NotebookTile extends StatelessWidget {
  const _NotebookTile({
    super.key,
    required this.entry,
    required this.library,
    required this.onTap,
    required this.pdf,
    required this.assets,
    required this.onAction,
  });
  final CatalogEntry entry;
  final LibraryController library;
  final VoidCallback onTap;
  final PdfService pdf;
  final AssetStore assets;
  final ValueChanged<String> onAction;

  Widget _thumbnail(BuildContext context, BoxConstraints constraints) {
    final pageSize = Size(entry.firstPageWidth, entry.firstPageHeight);
    final fitted = applyBoxFit(
      BoxFit.contain,
      pageSize,
      constraints.biggest,
    ).destination;
    if (fitted.isEmpty) return const SizedBox.shrink();
    final physicalSize = fitted * MediaQuery.devicePixelRatioOf(context);
    final cover = entry.coverAssetId;
    return FittedBox(
      fit: BoxFit.contain,
      alignment: Alignment.topCenter,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 18,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: SizedBox.fromSize(
          size: pageSize,
          child: IgnorePointer(
            child: cover != null
                ? _NotebookCover(
                    assets: assets,
                    assetId: cover,
                    physicalSize: physicalSize,
                  )
                : _NotebookPreview(
                    key: ValueKey((library, entry.headId)),
                    library: library,
                    entry: entry,
                    pdf: pdf,
                    assets: assets,
                    rasterScale: physicalSize.width / pageSize.width,
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  border: Border(
                    bottom: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: .45),
                    ),
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          _notebookPreviewSidePadding,
                          18,
                          _notebookPreviewSidePadding,
                          0,
                        ),
                        child: LayoutBuilder(builder: _thumbnail),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      left: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          entry.isPdf ? 'PDF' : 'Cuaderno',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: PopupMenuButton<String>(
                        tooltip: 'Opciones de apunte',
                        popUpAnimationStyle: _libraryMenuAnimation(context),
                        onSelected: onAction,
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'move', child: Text('Mover a…')),
                          PopupMenuItem(
                            value: 'rename',
                            child: Text('Renombrar'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Eliminar apunte'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.isConflict
                              ? 'Versiones distintas'
                              : entry.subject.isEmpty
                              ? 'Sin materia'
                              : entry.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.description_outlined,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${entry.pageCount}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotebookPreview extends StatefulWidget {
  const _NotebookPreview({
    super.key,
    required this.library,
    required this.entry,
    required this.pdf,
    required this.assets,
    required this.rasterScale,
  });

  final LibraryController library;
  final CatalogEntry entry;
  final PdfService pdf;
  final AssetStore assets;
  final double rasterScale;

  @override
  State<_NotebookPreview> createState() => _NotebookPreviewState();
}

class _NotebookPreviewState extends State<_NotebookPreview> {
  late final _page = widget.library.loadPreview(widget.entry);

  @override
  Widget build(BuildContext context) => FutureBuilder<NotebookPage?>(
    future: _page,
    builder: (context, snapshot) {
      final page = snapshot.data;
      if (page == null) return const SizedBox.shrink();
      return PaperCanvas(
        assets: widget.assets,
        page: page,
        tool: EditorTool.pen,
        onStroke: (_) {},
        externalInput: true,
        previewRasterScale: widget.rasterScale,
        background: page.background.isPdf
            ? PdfPageBackground(pdf: widget.pdf, page: page, scale: .25)
            : null,
      );
    },
  );
}

class _NotebookCover extends StatefulWidget {
  const _NotebookCover({
    required this.assets,
    required this.assetId,
    required this.physicalSize,
  });

  final AssetStore assets;
  final String assetId;
  final Size physicalSize;

  @override
  State<_NotebookCover> createState() => _NotebookCoverState();
}

class _NotebookCoverState extends State<_NotebookCover> {
  late Future<Uint8List> _image = widget.assets.read(widget.assetId);

  @override
  void didUpdateWidget(_NotebookCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assets != widget.assets ||
        oldWidget.assetId != widget.assetId) {
      _image = widget.assets.read(widget.assetId);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    key: ValueKey(widget.assetId),
    future: _image,
    builder: (context, snapshot) {
      const placeholder = ColoredBox(
        color: Colors.white,
        child: Center(child: Icon(Icons.image_outlined)),
      );
      final bytes = snapshot.data;
      if (bytes == null) return placeholder;
      return Image(
        image: _CoverThumbnailImage(
          MemoryImage(bytes),
          math.max(1, widget.physicalSize.width.ceil()),
          math.max(1, widget.physicalSize.height.ceil()),
        ),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => placeholder,
      );
    },
  );
}

class _CoverThumbnailImage extends ImageProvider<_CoverThumbnailImage> {
  const _CoverThumbnailImage(this.source, this.width, this.height);

  final MemoryImage source;
  final int width, height;

  @override
  Future<_CoverThumbnailImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _CoverThumbnailImage key,
    ImageDecoderCallback decode,
  ) => key.source.loadImage(key.source, (buffer, {getTargetSize}) {
    assert(getTargetSize == null);
    return decode(buffer, getTargetSize: key._targetSize);
  });

  ui.TargetImageSize _targetSize(int intrinsicWidth, int intrinsicHeight) {
    final widthScale = width / intrinsicWidth;
    final heightScale = height / intrinsicHeight;
    if (widthScale >= 1 || heightScale >= 1) return const ui.TargetImageSize();
    // The other dimension follows the source aspect ratio. The image still
    // crops with BoxFit.cover and retains enough pixels on its fitted axis.
    return widthScale >= heightScale
        ? ui.TargetImageSize(width: width)
        : ui.TargetImageSize(height: height);
  }

  @override
  bool operator ==(Object other) =>
      other is _CoverThumbnailImage &&
      other.source == source &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(source, width, height);
}
