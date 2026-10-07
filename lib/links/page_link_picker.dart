import 'package:flutter/material.dart';
import '../document/notebook.dart';
import '../document/notebook_repository.dart';
import '../document/page_link.dart';

class PageLinkChoice {
  const PageLinkChoice({required this.link, required this.label});
  final PageLink link;
  final String label;
}

Future<PageLinkChoice?> showPageLinkPicker(
  BuildContext context, {
  required NotebookRepository repository,
}) => showDialog<PageLinkChoice>(
  context: context,
  builder: (_) => _PageLinkPicker(repository: repository),
);

class _PageChoice {
  const _PageChoice(this.notebook, this.page, this.index);
  final Notebook notebook;
  final NotebookPage page;
  final int index;
  String get pageLabel => 'Página ${index + 1}';
  String get label => '${notebook.title} · $pageLabel';
  String get preview =>
      [page.recognizedText, ...page.objects.map((object) => object.text)]
          .where((text) => text.trim().isNotEmpty)
          .join(' · ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
  bool matches(String query) =>
      '${notebook.title} ${notebook.subject} $pageLabel $preview'
          .toLowerCase()
          .contains(query);
}

class _PageLinkPicker extends StatefulWidget {
  const _PageLinkPicker({required this.repository});
  final NotebookRepository repository;
  @override
  State<_PageLinkPicker> createState() => _PageLinkPickerState();
}

class _PageLinkPickerState extends State<_PageLinkPicker> {
  final search = TextEditingController();
  List<_PageChoice>? pages;
  String? error;
  bool selecting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _load({String? notice}) async {
    try {
      final entries = await widget.repository.list();
      final seen = <String>{};
      final loaded = <_PageChoice>[];
      // A link has no revision ID. Match repository.load's first current head
      // rather than offering a conflict-only page that cannot be opened later.
      for (final entry in entries) {
        final notebook = entry.notebook;
        if (!seen.add(notebook.id)) continue;
        for (var index = 0; index < notebook.pages.length; index++) {
          loaded.add(_PageChoice(notebook, notebook.pages[index], index));
        }
      }
      if (mounted) {
        setState(() {
          pages = loaded;
          error = notice;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'No se pudo leer la biblioteca de cuadernos.');
      }
    }
  }

  Future<void> _choose(_PageChoice choice) async {
    setState(() {
      selecting = true;
      error = null;
    });
    try {
      final current = await widget.repository.load(choice.notebook.id);
      final index =
          current?.pages.indexWhere((page) => page.id == choice.page.id) ?? -1;
      if (current == null || index < 0) {
        await _load(notice: 'Esa página ya no está disponible. Elegí otra.');
        return;
      }
      if (mounted) {
        Navigator.pop(
          context,
          PageLinkChoice(
            link: PageLink(notebookId: current.id, pageId: choice.page.id),
            label: '${current.title} · Página ${index + 1}',
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'No se pudo abrir esa página. Intentá de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => selecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    final visible = pages?.where((page) => page.matches(query)).toList();
    return AlertDialog(
      title: const Text('Enlazar a una página'),
      content: SizedBox(
        width: 560,
        height: MediaQuery.sizeOf(context).height * .55,
        child: Column(
          children: [
            TextField(
              controller: search,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Buscar cuaderno o página',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (selecting) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: pages == null
                  ? Center(
                      child: error == null
                          ? const CircularProgressIndicator()
                          : TextButton(
                              onPressed: _load,
                              child: const Text('Reintentar'),
                            ),
                    )
                  : visible!.isEmpty
                  ? Center(
                      child: Text(
                        pages!.isEmpty
                            ? 'Todavía no hay páginas para enlazar.'
                            : 'No se encontraron páginas.',
                      ),
                    )
                  : ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final choice = visible[index];
                        final preview = choice.preview;
                        return ListTile(
                          leading: const Icon(Icons.description_outlined),
                          title: Text(choice.pageLabel),
                          subtitle: Text(
                            '${choice.notebook.title}${preview.isEmpty ? '' : '\n$preview'}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: selecting ? null : () => _choose(choice),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
