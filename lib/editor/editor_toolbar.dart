import 'package:flutter/material.dart';
import '../document/notebook.dart';
import '../ui/app_theme.dart';

class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.tool,
    required this.onTool,
    required this.argb,
    required this.onColor,
    required this.width,
    required this.onWidth,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    required this.onDeleteSelection,
    required this.pattern,
    required this.onPattern,
    required this.onApplyPattern,
    this.onPenSettings,
  });
  final EditorTool tool;
  final ValueChanged<EditorTool> onTool;
  final int argb;
  final ValueChanged<int> onColor;
  final double width;
  final ValueChanged<double> onWidth;
  final bool canUndo, canRedo;
  final VoidCallback onUndo, onRedo;
  final VoidCallback? onDeleteSelection;
  final PaperPattern? pattern;
  final ValueChanged<PaperPattern> onPattern;
  final VoidCallback? onApplyPattern;
  final VoidCallback? onPenSettings;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final current in EditorTool.values)
            IconButton.filledTonal(
              tooltip: [
                'Lápiz',
                'Resaltador',
                'Borrador',
                'Selección',
              ][current.index],
              isSelected: current == tool,
              onPressed: () => onTool(current),
              icon: Icon(
                [
                  Icons.edit_outlined,
                  Icons.brush_outlined,
                  Icons.auto_fix_normal_outlined,
                  Icons.select_all,
                ][current.index],
              ),
            ),
          const SizedBox(width: 8),
          PopupMenuButton<int>(
            tooltip: 'Color de tinta',
            initialValue: argb,
            onSelected: onColor,
            icon: Icon(Icons.circle, color: Color(argb)),
            itemBuilder: (_) =>
                [
                      0xff202020,
                      0xff24584b,
                      0xff284cad,
                      0xffc14747,
                      0xffe1a51e,
                      0xff8553aa,
                    ]
                    .map(
                      (color) => PopupMenuItem(
                        value: color,
                        child: Row(
                          children: [
                            Icon(Icons.circle, color: Color(color)),
                            const SizedBox(width: 12),
                            Text(
                              [
                                'Grafito',
                                'Verde',
                                'Azul',
                                'Rojo',
                                'Amarillo',
                                'Violeta',
                              ][[
                                0xff202020,
                                0xff24584b,
                                0xff284cad,
                                0xffc14747,
                                0xffe1a51e,
                                0xff8553aa,
                              ].indexOf(color)],
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
          ),
          PopupMenuButton<double>(
            tooltip: 'Grosor de tinta',
            initialValue: width,
            onSelected: onWidth,
            icon: const Icon(Icons.line_weight),
            itemBuilder: (_) => [1.5, 2.5, 4.0, 8.0, 14.0]
                .map((w) => PopupMenuItem(value: w, child: Text('$w pt')))
                .toList(),
          ),
          IconButton(
            tooltip: 'Ajustes del lápiz',
            onPressed: onPenSettings,
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: 'Deshacer',
            onPressed: canUndo ? onUndo : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Rehacer',
            onPressed: canRedo ? onRedo : null,
            icon: const Icon(Icons.redo),
          ),
          IconButton(
            tooltip: 'Eliminar selección',
            onPressed: onDeleteSelection,
            icon: const Icon(Icons.delete_outline),
          ),
          if (pattern != null)
            PopupMenuButton<PaperPattern>(
              tooltip: 'Tipo de hoja',
              initialValue: pattern,
              onSelected: onPattern,
              itemBuilder: (_) => PaperPattern.values
                  .map(
                    (p) => PopupMenuItem(
                      value: p,
                      child: Text(paperLabel(p.index)),
                    ),
                  )
                  .toList(),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(paperLabel(pattern!.index)),
                    const Icon(Icons.expand_more, size: 18),
                  ],
                ),
              ),
            ),
          if (onApplyPattern != null)
            IconButton(
              tooltip: 'Aplicar hoja a todo el cuaderno',
              onPressed: onApplyPattern,
              icon: const Icon(Icons.layers_outlined),
            ),
        ],
      ),
    ),
  );
}
