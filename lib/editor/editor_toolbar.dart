import 'package:flutter/material.dart';
import '../document/notebook.dart';
import '../ui/app_theme.dart';
import 'toolbar_preferences.dart';

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
    this.layout,
    this.onShortcut = const {},
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
  final ToolbarLayout? layout;
  final Map<ToolbarAction, VoidCallback?> onShortcut;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final config = layout ?? ToolbarLayout.defaults();
    final vertical = config.dock != ToolbarDock.top;
    final wide = !vertical && MediaQuery.sizeOf(context).width >= 1100;
    const colors = [
      0xff202020,
      0xff24584b,
      0xff284cad,
      0xffc14747,
      0xffe9ba3b,
      0xff8553aa,
    ];
    const names = ['Grafito', 'Verde', 'Azul', 'Rojo', 'Amarillo', 'Violeta'];
    Widget button(
      ToolbarAction action,
      IconData icon,
      VoidCallback? callback, {
      bool selected = false,
    }) => IconButton(
      tooltip: toolbarLabels[action],
      onPressed: callback,
      isSelected: selected,
      icon: Icon(icon, size: 21),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    );
    final controls = <ToolbarAction, Widget>{};
    for (final tool in EditorTool.values) {
      final action = ToolbarAction.values[tool.index];
      const icons = [
        Icons.edit_outlined,
        Icons.border_color_outlined,
        Icons.auto_fix_normal_outlined,
        Icons.gesture,
      ];
      controls[action] = Tooltip(
        message: toolbarLabels[action]!,
        child: TextButton(
          onPressed: () => onTool(tool),
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            foregroundColor: tool == this.tool
                ? scheme.onPrimary
                : scheme.onSurfaceVariant,
            backgroundColor: tool == this.tool
                ? scheme.primary
                : Colors.transparent,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icons[tool.index], size: 21),
              if (wide) ...[
                const SizedBox(width: 8),
                Text(toolbarLabels[action]!),
              ],
            ],
          ),
        ),
      );
    }
    controls[ToolbarAction.color] = PopupMenuButton<int>(
      tooltip: 'Color de tinta',
      onOpened: onOpenMenu,
      onCanceled: onOpenMenu,
      initialValue: argb,
      onSelected: onColor,
      icon: Icon(Icons.circle, color: Color(argb)),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
    );
    controls[ToolbarAction.width] = PopupMenuButton<double>(
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
          PopupMenuItem(value: w, child: Text('$w pt')),
      ],
      child: SizedBox(
        height: 48,
        width: vertical ? 48 : 76,
        child: Center(
          child: vertical
              ? const Icon(Icons.line_weight)
              : Text(width.toStringAsFixed(1)),
        ),
      ),
    );
    controls[ToolbarAction.penSettings] = button(
      ToolbarAction.penSettings,
      Icons.tune,
      onPenSettings,
    );
    controls[ToolbarAction.undo] = button(
      ToolbarAction.undo,
      Icons.undo,
      canUndo ? onUndo : null,
    );
    controls[ToolbarAction.redo] = button(
      ToolbarAction.redo,
      Icons.redo,
      canRedo ? onRedo : null,
    );
    if (onDeleteSelection != null) {
      controls[ToolbarAction.deleteSelection] = button(
        ToolbarAction.deleteSelection,
        Icons.delete_outline,
        onDeleteSelection,
      );
    }
    if (pattern != null) {
      controls[ToolbarAction.paper] = PopupMenuButton<PaperPattern>(
        tooltip: 'Tipo de hoja',
        onOpened: onOpenMenu,
        onCanceled: onOpenMenu,
        initialValue: pattern,
        onSelected: onPattern,
        itemBuilder: (_) => [
          for (final p in PaperPattern.values)
            PopupMenuItem(value: p, child: Text(paperLabel(p.index))),
        ],
        child: SizedBox(
          height: 48,
          width: vertical ? 48 : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.description_outlined, size: 21),
                if (!vertical) ...[
                  const SizedBox(width: 8),
                  Text(paperLabel(pattern!.index)),
                ],
              ],
            ),
          ),
        ),
      );
      if (onApplyPattern != null) {
        controls[ToolbarAction.applyPaper] = button(
          ToolbarAction.applyPaper,
          Icons.layers_outlined,
          onApplyPattern,
        );
      }
    }
    const icons = <ToolbarAction, IconData>{
      ToolbarAction.text: Icons.text_fields,
      ToolbarAction.image: Icons.image_outlined,
      ToolbarAction.latex: Icons.functions,
      ToolbarAction.link: Icons.link,
      ToolbarAction.elements: Icons.collections_bookmark_outlined,
      ToolbarAction.templates: Icons.dashboard_customize_outlined,
      ToolbarAction.search: Icons.search,
      ToolbarAction.study: Icons.school_outlined,
      ToolbarAction.audio: Icons.mic_none,
    };
    for (final entry in icons.entries) {
      controls[entry.key] = button(
        entry.key,
        entry.value,
        onShortcut[entry.key],
      );
    }
    final children = [
      for (final action in config.order)
        if (config.visible.contains(action) && controls.containsKey(action))
          controls[action]!,
    ];
    final more = onMoreTools == null
        ? null
        : IconButton(
            tooltip: 'Más herramientas',
            onPressed: onMoreTools,
            isSelected: moreToolsActive,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: Badge(
              isLabelVisible: moreToolsActive,
              backgroundColor: scheme.primary,
              child: const Icon(Icons.apps_outlined),
            ),
          );
    return Material(
      color: scheme.surface,
      child: Container(
        height: vertical ? null : 56,
        width: vertical ? 56 : null,
        padding: vertical
            ? const EdgeInsets.symmetric(vertical: 4)
            : const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: .4),
            ),
          ),
        ),
        child: Flex(
          direction: vertical ? Axis.vertical : Axis.horizontal,
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: vertical ? Axis.vertical : Axis.horizontal,
                child: Flex(
                  direction: vertical ? Axis.vertical : Axis.horizontal,
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            ),
            ?more,
          ],
        ),
      ),
    );
  }
}
