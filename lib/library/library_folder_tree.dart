import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../document/folders.dart';
import '../ui/app_theme.dart';

class LibraryFolderTree extends StatefulWidget {
  const LibraryFolderTree({
    super.key,
    required this.folders,
    required this.selectedPath,
    required this.onNavigate,
  });

  final List<NoteFolder> folders;
  final List<NoteFolder> selectedPath;
  final ValueChanged<String?> onNavigate;

  @override
  State<LibraryFolderTree> createState() => _LibraryFolderTreeState();
}

typedef _FolderRow = ({NoteFolder folder, int depth});

class _LibraryFolderTreeState extends State<LibraryFolderTree> {
  static const _topPadding = 24.0;

  final _scroll = ScrollController();
  final _expanded = <String>{};
  late Map<String?, List<NoteFolder>> _children;
  List<String> _selectedPathIds = [];
  bool _revealPending = false;

  @override
  void initState() {
    super.initState();
    _indexFolders();
    _updateSelection();
  }

  @override
  void didUpdateWidget(LibraryFolderTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.folders, oldWidget.folders)) _indexFolders();
    _updateSelection();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _indexFolders() {
    final ids = {for (final folder in widget.folders) folder.id};
    _expanded.retainAll(ids);
    _children = {};
    for (final folder in widget.folders) {
      final parentId = ids.contains(folder.parentId) ? folder.parentId : null;
      (_children[parentId] ??= []).add(folder);
    }
  }

  void _updateSelection() {
    final pathIds = [for (final folder in widget.selectedPath) folder.id];
    // Preserve an explicit collapse when the same selection survives a refresh.
    if (listEquals(_selectedPathIds, pathIds)) return;
    _selectedPathIds = pathIds;
    for (var i = 0; i < pathIds.length - 1; i++) {
      _expanded.add(pathIds[i]);
    }
    _revealPending = true;
  }

  List<_FolderRow> _visibleFolders() {
    final pending = <_FolderRow>[
      for (final folder in (_children[null] ?? const <NoteFolder>[]).reversed)
        (folder: folder, depth: 0),
    ];
    final visible = <_FolderRow>[];
    while (pending.isNotEmpty) {
      final row = pending.removeLast();
      visible.add(row);
      final children = _children[row.folder.id];
      if (children != null && _expanded.contains(row.folder.id)) {
        for (final folder in children.reversed) {
          pending.add((folder: folder, depth: row.depth + 1));
        }
      }
    }
    return visible;
  }

  void _revealRow(int index, double rowHeight) {
    _revealPending = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      final start = _topPadding + index * rowHeight;
      final end = start + rowHeight;
      final visibleEnd = position.pixels + position.viewportDimension;
      if (start < position.pixels) {
        _scroll.jumpTo(start.clamp(0.0, position.maxScrollExtent));
      } else if (end > visibleEnd) {
        _scroll.jumpTo(
          (end - position.viewportDimension).clamp(
            0.0,
            position.maxScrollExtent,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleFolders();
    final selectedId = _selectedPathIds.lastOrNull;
    final rowHeight = math.max(
      44.0,
      MediaQuery.textScalerOf(context).scale(22) + 8,
    );
    if (_revealPending) {
      final selectedIndex = visible.indexWhere(
        (row) => row.folder.id == selectedId,
      );
      _revealRow(selectedIndex + 2, rowHeight);
    }

    return Material(
      color: nalaSidebar,
      child: ListView.builder(
        controller: _scroll,
        primary: false,
        padding: const EdgeInsets.fromLTRB(12, _topPadding, 12, 16),
        itemExtent: rowHeight,
        itemCount: visible.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 8, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'Tu biblioteca',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }
          if (index == 1) {
            return _TreeRow(
              label: 'Mis apuntes',
              icon: Icons.home_outlined,
              selected: selectedId == null,
              onSelect: () => widget.onNavigate(null),
            );
          }
          final (:folder, :depth) = visible[index - 2];
          final canExpand = _children.containsKey(folder.id);
          final expanded = _expanded.contains(folder.id);
          return Padding(
            key: ValueKey(folder.id),
            // Keep space for the label even in very deep branches.
            padding: EdgeInsetsDirectional.only(
              start: math.min(depth, 5) * 12.0,
            ),
            child: _TreeRow(
              label: folder.name,
              icon: canExpand && expanded
                  ? Icons.folder_open_outlined
                  : Icons.folder_outlined,
              selected: selectedId == folder.id,
              onSelect: () => widget.onNavigate(folder.id),
              expanded: expanded,
              onToggle: canExpand
                  ? () => setState(() {
                      if (!_expanded.add(folder.id)) {
                        _expanded.remove(folder.id);
                      }
                    })
                  : null,
            ),
          );
        },
      ),
    );
  }
}

class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelect,
    this.expanded = false,
    this.onToggle,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onSelect;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : const Color(0xffdddddd);
    final borderRadius = BorderRadius.circular(10);
    return Material(
      color: selected ? Colors.white12 : Colors.transparent,
      borderRadius: borderRadius,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onToggle != null)
            SizedBox(
              width: 32,
              child: IconButton(
                tooltip: expanded ? 'Contraer $label' : 'Expandir $label',
                onPressed: onToggle,
                icon: Semantics(
                  expanded: expanded,
                  child: Icon(
                    expanded ? Icons.expand_more : Icons.chevron_right,
                  ),
                ),
                style: IconButton.styleFrom(
                  foregroundColor: color,
                  minimumSize: Size.zero,
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          Expanded(
            child: Tooltip(
              message: label,
              excludeFromSemantics: true,
              waitDuration: const Duration(milliseconds: 500),
              child: TextButton(
                onPressed: onSelect,
                style: TextButton.styleFrom(
                  foregroundColor: color,
                  padding: EdgeInsetsDirectional.only(
                    start: onToggle == null ? 36 : 4,
                    end: 8,
                  ),
                  minimumSize: Size.zero,
                  alignment: AlignmentDirectional.centerStart,
                  shape: RoundedRectangleBorder(borderRadius: borderRadius),
                  textStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                child: Semantics(
                  selected: selected,
                  child: Row(
                    children: [
                      Icon(icon, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
