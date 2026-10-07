import 'package:flutter/material.dart';
import '../document/notebook.dart';
import '../document/page_object.dart';
import 'element_store.dart';

Future<LibraryElement?> showElementPicker(
  BuildContext context, {
  required ElementStore store,
}) => showDialog<LibraryElement>(
  context: context,
  builder: (_) => _ElementPicker(store: store),
);

Future<LibraryElement?> saveSelectionAsElement(
  BuildContext context, {
  required ElementStore store,
  required NotebookPage page,
  required Set<String> ids,
}) async {
  final hasContent =
      page.strokes.any((stroke) => ids.contains(stroke.id)) ||
      page.objects.any((object) => ids.contains(object.id));
  if (!hasContent) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Seleccioná trazos u objetos para guardarlos.'),
      ),
    );
    return null;
  }
  final name = await _showNameDialog(
    context,
    title: 'Guardar como elemento',
    action: 'Guardar elemento',
  );
  if (name == null || !context.mounted) return null;
  try {
    return await store.saveSelection(name: name, page: page, ids: ids);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar el elemento. Intentá de nuevo.'),
        ),
      );
    }
    return null;
  }
}

Future<String?> _showNameDialog(
  BuildContext context, {
  required String title,
  required String action,
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder: (_) =>
      _ElementNameDialog(title: title, action: action, initial: initial),
);

class _ElementNameDialog extends StatefulWidget {
  const _ElementNameDialog({
    required this.title,
    required this.action,
    required this.initial,
  });
  final String title, action, initial;
  @override
  State<_ElementNameDialog> createState() => _ElementNameDialogState();
}

class _ElementNameDialogState extends State<_ElementNameDialog> {
  late final name = TextEditingController(text: widget.initial);
  bool get valid =>
      name.text.trim().isNotEmpty && name.text.trim().length <= 120;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void _save() {
    if (valid) Navigator.pop(context, name.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 420,
      child: TextField(
        controller: name,
        autofocus: true,
        maxLength: 120,
        decoration: const InputDecoration(labelText: 'Nombre del elemento'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _save(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: valid ? _save : null, child: Text(widget.action)),
    ],
  );
}

class _ElementPicker extends StatefulWidget {
  const _ElementPicker({required this.store});
  final ElementStore store;
  @override
  State<_ElementPicker> createState() => _ElementPickerState();
}

class _ElementPickerState extends State<_ElementPicker> {
  final search = TextEditingController();
  List<LibraryElement>? elements;
  String? error;
  bool changing = false;
  int loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.store.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.store.changes.removeListener(_load);
    search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++loadGeneration;
    try {
      final loaded = await widget.store.load();
      if (mounted && generation == loadGeneration) {
        setState(() {
          elements = loaded;
          error = null;
        });
      }
    } catch (_) {
      if (mounted && generation == loadGeneration) {
        setState(() => error = 'No se pudo leer la biblioteca de elementos.');
      }
    }
  }

  Future<void> _rename(LibraryElement element) async {
    final name = await _showNameDialog(
      context,
      title: 'Renombrar elemento',
      action: 'Guardar nombre',
      initial: element.name,
    );
    if (name == null || !mounted) return;
    await _change(
      () => widget.store.rename(element.id, name),
      'No se pudo renombrar ese elemento.',
    );
  }

  Future<void> _remove(LibraryElement element) => _change(
    () => widget.store.remove(element.id),
    'No se pudo eliminar ese elemento.',
  );
  Future<void> _change(
    Future<void> Function() operation,
    String message,
  ) async {
    setState(() {
      changing = true;
      error = null;
    });
    try {
      await operation();
      await _load();
    } catch (_) {
      if (mounted) setState(() => error = message);
    } finally {
      if (mounted) setState(() => changing = false);
    }
  }

  String _description(LibraryElement element) {
    final parts = <String>[];
    final strokes = element.strokes.length;
    if (strokes > 0) parts.add('$strokes ${strokes == 1 ? 'trazo' : 'trazos'}');
    for (final kind in PageObjectKind.values) {
      final count = element.objects
          .where((object) => object.kind == kind)
          .length;
      if (count == 0) continue;
      final label = switch (kind) {
        PageObjectKind.text => count == 1 ? 'texto' : 'textos',
        PageObjectKind.image => count == 1 ? 'imagen' : 'imágenes',
        PageObjectKind.latex => count == 1 ? 'fórmula' : 'fórmulas',
      };
      parts.add('$count $label');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    final visible = elements
        ?.where((element) => element.name.toLowerCase().contains(query))
        .toList();
    return AlertDialog(
      title: const Text('Biblioteca de elementos'),
      content: SizedBox(
        width: 560,
        height: MediaQuery.sizeOf(context).height * .55,
        child: Column(
          children: [
            TextField(
              controller: search,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Buscar elemento',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (changing) const LinearProgressIndicator(),
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
              child: elements == null
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
                        elements!.isEmpty
                            ? 'Todavía no guardaste elementos.'
                            : 'No se encontraron elementos.',
                      ),
                    )
                  : ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final element = visible[index];
                        return ListTile(
                          leading: const Icon(Icons.widgets_outlined),
                          title: Text(
                            element.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(_description(element)),
                          onTap: changing
                              ? null
                              : () => Navigator.pop(context, element),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Renombrar elemento',
                                onPressed: changing
                                    ? null
                                    : () => _rename(element),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Eliminar elemento',
                                onPressed: changing
                                    ? null
                                    : () => _remove(element),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
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
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
