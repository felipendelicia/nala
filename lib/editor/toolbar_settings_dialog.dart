import 'package:flutter/material.dart';
import 'toolbar_preferences.dart';

Future<ToolbarLayout?> showToolbarSettings(
  BuildContext context,
  ToolbarLayout layout,
) => showDialog<ToolbarLayout>(
  context: context,
  builder: (_) => _ToolbarSettings(layout: layout),
);

class _ToolbarSettings extends StatefulWidget {
  const _ToolbarSettings({required this.layout});
  final ToolbarLayout layout;
  @override
  State<_ToolbarSettings> createState() => _ToolbarSettingsState();
}

class _ToolbarSettingsState extends State<_ToolbarSettings> {
  late var order = [...widget.layout.order];
  late var visible = {...widget.layout.visible};
  late var dock = widget.layout.dock;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Personalizar barra'),
    content: SizedBox(
      width: 440,
      height: MediaQuery.sizeOf(context).height * .58,
      child: Column(
        children: [
          DropdownButtonFormField<ToolbarDock>(
            initialValue: dock,
            decoration: const InputDecoration(labelText: 'Ubicación'),
            items: const [
              DropdownMenuItem(value: ToolbarDock.top, child: Text('Arriba')),
              DropdownMenuItem(
                value: ToolbarDock.left,
                child: Text('Izquierda'),
              ),
              DropdownMenuItem(
                value: ToolbarDock.right,
                child: Text('Derecha'),
              ),
            ],
            onChanged: (value) => setState(() => dock = value!),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Elegí los accesos y arrastralos para ordenar. Más herramientas siempre queda disponible.',
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              itemCount: order.length,
              buildDefaultDragHandles: false,
              onReorderItem: (old, next) => setState(() {
                order.insert(next, order.removeAt(old));
              }),
              itemBuilder: (context, i) => CheckboxListTile(
                key: ValueKey(order[i]),
                value: visible.contains(order[i]),
                title: Text(toolbarLabels[order[i]]!),
                secondary: ReorderableDragStartListener(
                  index: i,
                  child: const SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(Icons.drag_handle),
                  ),
                ),
                onChanged: (enabled) => setState(() {
                  if (enabled!) {
                    visible.add(order[i]);
                  } else {
                    visible.remove(order[i]);
                  }
                }),
              ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => setState(() {
          final defaults = ToolbarLayout.defaults();
          order = [...defaults.order];
          visible = {...defaults.visible};
          dock = defaults.dock;
        }),
        child: const Text('Restablecer'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          ToolbarLayout(order: order, visible: visible, dock: dock),
        ),
        child: const Text('Guardar'),
      ),
    ],
  );
}
