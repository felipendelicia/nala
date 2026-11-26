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
    this.chatAction,
    this.dragHandle,
    this.floating = false,
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
  final Widget? chatAction;
  final Widget? dragHandle;
  final bool floating;
  final bool moreToolsActive;
  final ToolbarLayout? layout;
  final Map<ToolbarAction, VoidCallback?> onShortcut;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _buildToolbar(context, availableWidth: constraints.maxWidth),
  );

  Widget _buildToolbar(BuildContext context, {required double availableWidth}) {
    final scheme = Theme.of(context).colorScheme;
    final config = layout ?? ToolbarLayout.defaults();
    final vertical = !floating && config.dock != ToolbarDock.top;
    final axis = vertical ? Axis.vertical : Axis.horizontal;
    final quickColorWidth = config.visible.contains(ToolbarAction.color)
        ? config.quickColors.length * 48.0
        : 0.0;
    final toolWidth =
        availableWidth - quickColorWidth - (dragHandle == null ? 0 : 44);
    final wide = !floating && !vertical && toolWidth >= 1100;
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
    controls[ToolbarAction.color] = Flex(
      mainAxisSize: MainAxisSize.min,
      direction: axis,
      children: [
        for (final color in config.quickColors)
          IconButton(
            tooltip: 'Color rápido: ${toolbarInkPalette[color]}',
            isSelected: color == argb,
            onPressed: () => onColor(color),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: Container(
              width: 28,
              height: 28,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: color == argb
                    ? Border.all(color: scheme.primary, width: 2)
                    : null,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(color),
                  border: Border.all(
                    color: scheme.onSurface.withValues(alpha: .45),
                  ),
                ),
              ),
            ),
          ),
        PopupMenuButton<int>(
          tooltip: 'Color de tinta',
          onOpened: onOpenMenu,
          onCanceled: onOpenMenu,
          initialValue: argb,
          onSelected: onColor,
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.palette_outlined, size: 21),
              if (!config.quickColors.contains(argb))
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(argb),
                      border: Border.all(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
            ],
          ),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          itemBuilder: (_) => [
            for (final color in toolbarInkPalette.entries)
              PopupMenuItem(
                value: color.key,
                child: Row(
                  children: [
                    Icon(Icons.circle, color: Color(color.key)),
                    const SizedBox(width: 12),
                    Text(color.value),
                  ],
                ),
              ),
          ],
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
      elevation: floating ? 6 : 0,
      shape: floating
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: scheme.outlineVariant),
            )
          : null,
      clipBehavior: floating ? Clip.antiAlias : Clip.none,
      child: Container(
        height: vertical ? null : 56,
        width: vertical ? 56 : null,
        padding: vertical
            ? const EdgeInsets.symmetric(vertical: 4)
            : const EdgeInsets.symmetric(horizontal: 4),
        decoration: floating
            ? null
            : BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: .4),
                  ),
                ),
              ),
        child: Flex(
          direction: axis,
          children: [
            ?dragHandle,
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: axis,
                child: Flex(
                  direction: axis,
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            ),
            ?chatAction,
            ?more,
          ],
        ),
      ),
    );
  }
}
