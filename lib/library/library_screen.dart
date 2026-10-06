import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../bootstrap.dart';
import '../document/notebook.dart';
import '../document/revision.dart';
import '../editor/editor_controller.dart';
import '../editor/editor_screen.dart';
import '../editor/paper_canvas.dart';
import '../ui/app_theme.dart';
import 'notebook_dialog.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.services});
  final AppServices services;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String query = '', subject = '';
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
      MaterialPageRoute<void>(builder: (_) => EditorScreen(controller: editor)),
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
          actions: const [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text('Guardado en este dispositivo'),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              if (constraints.maxWidth >= 1000)
                SizedBox(
                  width: 220,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        const Text('Materias', style: TextStyle(fontSize: 20)),
                        const SizedBox(height: 16),
                        ListTile(
                          title: const Text('Todos mis apuntes'),
                          selected: subject.isEmpty,
                          onTap: () => setState(() => subject = ''),
                        ),
                        for (final course in subjects)
                          ListTile(
                            title: Text(course),
                            selected: subject == course,
                            onTap: () => setState(() => subject = course),
                          ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(
                    constraints.maxWidth >= 600 ? 32 : 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Mis apuntes',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w500,
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
                            onPressed: null,
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text('Abrir PDF'),
                          ),
                          SizedBox(
                            width: constraints.maxWidth < 500
                                ? constraints.maxWidth - 32
                                : 280,
                            child: TextField(
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.search),
                                hintText: 'Buscar apuntes',
                              ),
                              onChanged: (text) => setState(() => query = text),
                            ),
                          ),
                          if (constraints.maxWidth < 1000 &&
                              subjects.isNotEmpty)
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
                      const SizedBox(height: 28),
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
                                      library.entries.isEmpty
                                          ? 'Tu próximo apunte empieza acá'
                                          : 'No hay apuntes con esa búsqueda',
                                      style: const TextStyle(fontSize: 22),
                                    ),
                                    const SizedBox(height: 12),
                                    if (library.entries.isEmpty)
                                      const Text(
                                        'Creá un cuaderno y elegí tu tipo de hoja.',
                                      ),
                                  ],
                                ),
                              )
                            : GridView.builder(
                                gridDelegate:
                                    SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 400,
                                      mainAxisExtent: 270,
                                      crossAxisSpacing: 20,
                                      mainAxisSpacing: 20,
                                    ),
                                itemCount: entries.length,
                                itemBuilder: (context, index) => _NotebookTile(
                                  entry: entries[index],
                                  onTap: () => _open(entries[index]),
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
  const _NotebookTile({required this.entry, required this.onTap});
  final DocumentEntry entry;
  final VoidCallback onTap;
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
