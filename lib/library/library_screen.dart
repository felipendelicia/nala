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
          pdf: widget.services.pdf,
          files: widget.services.files,
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
            if (widget.cloud != null)
              CloudControls(cloud: widget.cloud!)
            else
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Guardado en este dispositivo'),
              ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              if (constraints.maxWidth >= 1100)
                SizedBox(
                  width: 220,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
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
                                (library.pathFor(folder.id).length - 1) * 12.0,
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
                                TextButton(
                                  onPressed: () => _navigate(f.id),
                                  child: Text(f.name),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
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
                            DropdownButton<String>(
                              value: subject,
                              items: [
                                const DropdownMenuItem(
                                  value: '',
                                  child: Text('Todas las materias'),
                                ),
                                ...subjects.map(
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s),
                                  ),
                                ),
                              ],
                              onChanged: (s) =>
                                  setState(() => subject = s ?? ''),
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
                                    const Icon(
                                      Icons.menu_book_outlined,
                                      size: 52,
                                      color: nalaGreen,
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
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 400,
                                      mainAxisExtent: 270,
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
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: nalaGreen, width: 5)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 130,
                  child: FittedBox(
                    alignment: Alignment.centerLeft,
                    child: IgnorePointer(
                      child: PaperCanvas(
                        page: entry.notebook.pages.first,
                        tool: EditorTool.pen,
                        onStroke: (_) {},
                        background:
                            entry.notebook.pages.first.background.assetId ==
                                null
                            ? null
                            : PdfPageBackground(
                                pdf: pdf,
                                page: entry.notebook.pages.first,
                                scale: .25,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              entry.notebook.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              entry.isConflict
                  ? 'Versiones distintas · ${entry.deviceId}'
                  : '${entry.notebook.subject.isEmpty ? 'Sin materia' : entry.notebook.subject} · ${entry.notebook.pages.length} ${entry.notebook.pages.length == 1 ? 'hoja' : 'hojas'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ),
  );
}
