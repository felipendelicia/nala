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
    this.onOpenMenu,
    this.onMoreTools,
    this.moreToolsActive = false,
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
  final VoidCallback? onOpenMenu, onMoreTools;
  final bool moreToolsActive;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    const colors = [
      0xff202020,
      0xff24584b,
      0xff284cad,
      0xffc14747,
      0xffe9ba3b,
      0xff8553aa,
    ];
    const names = ['Grafito', 'Verde', 'Azul', 'Rojo', 'Amarillo', 'Violeta'];
    const labels = ['Lápiz', 'Resaltador', 'Borrador', 'Selección'];
    const icons = [
      Icons.edit_outlined,
      Icons.border_color_outlined,
      Icons.auto_fix_normal_outlined,
      Icons.gesture,
    ];
    Widget divider() => Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: scheme.outlineVariant.withValues(alpha: .5),
    );
    Widget swatch(int color, String name) => Tooltip(
      message: name,
      child: InkResponse(
        onTap: () => onColor(color),
        radius: 22,
        child: SizedBox(
          width: 40,
          height: 48,
          child: Center(
            child: Container(
              width: color == argb ? 29 : 21,
              height: color == argb ? 29 : 21,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: color == argb ? scheme.primary : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(color),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Material(
      color: scheme.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: .4),
            ),
          ),
        ),
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          for (final current in EditorTool.values)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: Tooltip(
                                message: labels[current.index],
                                child: TextButton(
                                  onPressed: () => onTool(current),
                                  style: TextButton.styleFrom(
                                    foregroundColor: current == tool
                                        ? scheme.onPrimary
                                        : scheme.onSurfaceVariant,
                                    backgroundColor: current == tool
                                        ? scheme.primary
                                        : Colors.transparent,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: wide ? 14 : 12,
                                    ),
                                    minimumSize: const Size(44, 44),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(icons[current.index], size: 21),
                                      if (wide) ...[
                                        const SizedBox(width: 8),
                                        Text(labels[current.index]),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    divider(),
                    if (wide) ...[
                      for (var i = 0; i < colors.length; i++)
                        swatch(colors[i], names[i]),
                    ] else
                      PopupMenuButton<int>(
                        tooltip: 'Color de tinta',
                        onOpened: onOpenMenu,
                        onCanceled: onOpenMenu,
                        initialValue: argb,
                        onSelected: onColor,
                        icon: Icon(Icons.circle, color: Color(argb)),
                        itemBuilder: (_) => [
                          for (var i = 0; i < colors.length; i++)
                            PopupMenuItem(
                              value: colors[i],
                              child: Row(
                                children: [
                                  Icon(Icons.circle, color: Color(colors[i])),
                                  const SizedBox(width: 12),
                                  Text(names[i]),
                                ],
                              ),
                            ),
                        ],
                      ),
                    PopupMenuButton<double>(
                      tooltip: 'Grosor de tinta',
                      onOpened: onOpenMenu,
                      onCanceled: onOpenMenu,
                      initialValue: width,
                      onSelected: onWidth,
                      itemBuilder: (_) => [
                        for (final w
                            in tool == EditorTool.highlighter
                                ? [4.0, 8.0, 14.0, 20.0, 28.0]
                                : [1.5, 2.5, 4.0, 6.0, 8.0])
                          PopupMenuItem(
                            value: w,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 56,
                                  child: Center(
                                    child: Container(
                                      height: w.clamp(1.5, 14.0),
                                      width: 40,
                                      decoration: BoxDecoration(
                                        color: scheme.onSurface,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text('$w pt'),
                              ],
                            ),
                          ),
                      ],
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 24,
                                child: Container(
                                  height: width.clamp(2.0, 12.0),
                                  decoration: BoxDecoration(
                                    color: scheme.onSurface,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(width.toStringAsFixed(1)),
                              const Icon(Icons.expand_more, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Ajustes del lápiz',
                      onPressed: onPenSettings,
                      icon: const Icon(Icons.tune, size: 21),
                    ),
                    divider(),
                    IconButton(
                      tooltip: 'Deshacer',
                      onPressed: canUndo ? onUndo : null,
                      icon: const Icon(Icons.undo, size: 21),
                    ),
                    IconButton(
                      tooltip: 'Rehacer',
                      onPressed: canRedo ? onRedo : null,
                      icon: const Icon(Icons.redo, size: 21),
                    ),
                    if (onDeleteSelection != null)
                      IconButton(
                        tooltip: 'Eliminar selección',
                        onPressed: onDeleteSelection,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    if (pattern != null) ...[
                      divider(),
                      PopupMenuButton<PaperPattern>(
                        tooltip: 'Tipo de hoja',
                        onOpened: onOpenMenu,
                        onCanceled: onOpenMenu,
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
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.description_outlined,
                                  size: 19,
                                ),
                                const SizedBox(width: 8),
                                Text(paperLabel(pattern!.index)),
                                const Icon(Icons.expand_more, size: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (onApplyPattern != null)
                        IconButton(
                          tooltip: 'Aplicar hoja a todo el cuaderno',
                          onPressed: onApplyPattern,
                          icon: const Icon(Icons.layers_outlined, size: 21),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            if (onMoreTools != null) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Más herramientas',
                onPressed: onMoreTools,
                isSelected: moreToolsActive,
                icon: Badge(
                  isLabelVisible: moreToolsActive,
                  backgroundColor: scheme.primary,
                  child: const Icon(Icons.apps_outlined),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
