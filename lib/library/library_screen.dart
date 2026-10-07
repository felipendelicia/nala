import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' show PdfPasswordException;
import '../bootstrap.dart';
import '../document/notebook.dart';
import '../document/revision.dart';
import '../document/folders.dart';
import 'folder_dialog.dart';
import '../editor/editor_controller.dart';
import '../editor/editor_screen.dart';
import '../editor/paper_canvas.dart';
import '../ui/app_theme.dart';
import '../ui/appearance.dart';
import 'notebook_dialog.dart';
import '../pdf/password_dialog.dart';
import '../pdf/pdf_page_background.dart';
import '../pdf/pdf_service.dart';
import '../account/cloud_controller.dart';
import '../account/cloud_panel.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.services, this.cloud});
  final AppServices services;
  final CloudController? cloud;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String query = '', subject = '';
  bool importing = false;
  Future<void> _open(DocumentEntry entry) async {
    final editor = EditorController(
      notebook: entry.notebook,
      headId: entry.headId,
      repository: widget.services.repository,
      deviceId: widget.services.deviceId,
      newId: const Uuid().v4,
      now: DateTime.now,
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditorScreen(
          controller: editor,
          penPreferences: widget.services.penPreferences,
          pdf: widget.services.pdf,
          files: widget.services.files,
          share: widget.services.share,
          assets: widget.services.assets,
          audio: widget.services.audio,
          audioDirectory: '${widget.services.root}/audio-temp',
          cloud: widget.cloud,
        ),
      ),
    );
    editor.dispose();
    if (mounted) await widget.services.library.refresh();
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

  Future<void> _noteAction(DocumentEntry entry, String action) async {
    final library = widget.services.library;
    try {
      if (action == 'move') {
        final target = await showDialog<FolderDestination>(
          context: context,
          builder: (_) => FolderPickerDialog(library: library),
        );
        if (target != null) await library.moveNotebook(entry, target.id);
      } else {
        final name = await showDialog<String>(
          context: context,
          builder: (_) => NameDialog(
            title: 'Renombrar apunte',
            label: 'Nombre del apunte',
            value: entry.notebook.title,
          ),
        );
        if (name != null) {
          await library.updateNotebook(
            entry,
            entry.notebook.copyWith(title: name),
          );
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

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.services.library,
    builder: (context, _) {
      final library = widget.services.library;
      final entries = library.filtered(query: query, subject: subject);
      final subjects =
          library.entries
              .map((e) => e.notebook.subject)
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
                                      maxCrossAxisExtent: 360,
                                      mainAxisExtent:
                                          constraints.maxHeight < 800
                                          ? 280
                                          : 320,
                                      crossAxisSpacing: 20,
                                      mainAxisSpacing: 20,
                                    ),
                                itemCount: entries.length,
                                itemBuilder: (_, index) => _NotebookTile(
                                  entry: entries[index],
                                  pdf: widget.services.pdf,
                                  onTap: () => _open(entries[index]),
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
    required this.entry,
    required this.onTap,
    required this.pdf,
    required this.onAction,
  });
  final DocumentEntry entry;
  final VoidCallback onTap;
  final PdfService pdf;
  final ValueChanged<String> onAction;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final page = entry.notebook.pages.first;
    final isPdf = page.background.assetId != null;
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
                        padding: const EdgeInsets.fromLTRB(40, 18, 40, 0),
                        child: FittedBox(
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
                            child: IgnorePointer(
                              child: PaperCanvas(
                                page: page,
                                tool: EditorTool.pen,
                                onStroke: (_) {},
                                background: isPdf
                                    ? PdfPageBackground(
                                        pdf: pdf,
                                        page: page,
                                        scale: .25,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
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
                          isPdf ? 'PDF' : 'Cuaderno',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: PopupMenuButton<String>(
                        tooltip: 'Opciones de apunte',
                        onSelected: onAction,
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'move', child: Text('Mover a…')),
                          PopupMenuItem(
                            value: 'rename',
                            child: Text('Renombrar'),
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
                    entry.notebook.title,
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
                              : entry.notebook.subject.isEmpty
                              ? 'Sin materia'
                              : entry.notebook.subject,
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
                        '${entry.notebook.pages.length}',
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
