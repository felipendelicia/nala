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
  late var quickColors = [...widget.layout.quickColors];

  Future<void> _editQuickColors() async {
    final selected = [...quickColors];
    final colors = await showDialog<List<int>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setSelection) => AlertDialog(
          scrollable: true,
          title: const Text('Colores rápidos'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Elegí hasta tres colores para mostrar en la barra.'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final color in toolbarInkPalette.entries)
                    FilterChip(
                      label: Text(color.value),
                      avatar: Icon(
                        Icons.circle,
                        size: 16,
                        color: Color(color.key),
                      ),
                      selected: selected.contains(color.key),
                      onSelected:
                          selected.contains(color.key) ||
                              selected.length < toolbarQuickColorLimit
                          ? (enabled) => setSelection(() {
                              if (enabled &&
                                  selected.length < toolbarQuickColorLimit) {
                                selected.add(color.key);
                              } else if (!enabled) {
                                selected.remove(color.key);
                              }
                            })
                          : null,
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: const Text('Listo'),
            ),
          ],
        ),
      ),
    );
    if (mounted && colors != null) {
      setState(() {
        quickColors = colors;
        if (colors.isNotEmpty) visible.add(ToolbarAction.color);
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Personalizar barra'),
    content: SizedBox(
      width: 440,
      height: MediaQuery.sizeOf(context).height * .58,
      child: ReorderableListView.builder(
        header: Column(
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
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Colores rápidos'),
              trailing: Text('${quickColors.length}/$toolbarQuickColorLimit'),
              onTap: _editQuickColors,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Elegí los accesos y arrastralos para ordenar. Más herramientas siempre queda disponible.',
              ),
            ),
          ],
        ),
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
    actions: [
      TextButton(
        onPressed: () => setState(() {
          final defaults = ToolbarLayout.defaults();
          order = [...defaults.order];
          visible = {...defaults.visible};
          dock = defaults.dock;
          quickColors = [...defaults.quickColors];
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
          ToolbarLayout(
            order: order,
            visible: visible,
            dock: dock,
            quickColors: quickColors,
          ),
        ),
        child: const Text('Guardar'),
      ),
    ],
  );
}
