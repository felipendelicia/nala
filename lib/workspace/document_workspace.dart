import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../account/cloud_controller.dart';
import '../bootstrap.dart';
import '../document/notebook_repository.dart';
import '../document/revision.dart';
import '../editor/editor_controller.dart';
import '../editor/editor_screen.dart';

class WorkspaceTab {
  WorkspaceTab({required this.controller, this.initialPageIndex = 0});
  final EditorController controller;
  final int initialPageIndex;
  String get id => controller.notebook.id;
  Future<void> Function()? prepareClose;
}

/// Owns document controllers for the lifetime of the workspace, independent of
/// which document is visible. A document can occupy only one pane at a time.
class DocumentWorkspace extends ChangeNotifier {
  DocumentWorkspace({
    required this.repository,
    required this.deviceId,
    required this.newId,
    required this.now,
  });
  final NotebookRepository repository;
  final String deviceId;
  final String Function() newId;
  final DateTime Function() now;
  final List<WorkspaceTab> _tabs = [];
  List<WorkspaceTab> get tabs => List.unmodifiable(_tabs);
  String? _left, _right, _active;
  String? get activeId => _active;
  bool get split => _right != null;
  List<String> get visibleIds => [_left, _right].whereType<String>().toList();
  bool isActive(String id) => id == _active;
  WorkspaceTab open(DocumentEntry entry, {int initialPageIndex = 0}) {
    final existing = _tabs.where((t) => t.id == entry.notebook.id).firstOrNull;
    if (existing != null) {
      select(existing.id);
      return existing;
    }
    final tab = WorkspaceTab(
      initialPageIndex: initialPageIndex,
      controller: EditorController(
        notebook: entry.notebook,
        headId: entry.headId,
        repository: repository,
        deviceId: deviceId,
        newId: newId,
        now: now,
      ),
    );
    _tabs.add(tab);
    select(tab.id);
    return tab;
  }

  void select(String id) {
    if (!_tabs.any((t) => t.id == id)) return;
    if (_left == null) {
      _left = id;
    } else if (id != _left && id != _right) {
      if (_active == _right && split) {
        _right = id;
      } else {
        _left = id;
      }
    }
    _active = id;
    notifyListeners();
  }

  void focus(String id) {
    if (visibleIds.contains(id) && _active != id) {
      _active = id;
      notifyListeners();
    }
  }

  void splitWith(String id) {
    if (!_tabs.any((t) => t.id == id) || id == _left) return;
    _right = id;
    _active = id;
    notifyListeners();
  }

  void unsplit() {
    if (_active == _right) _left = _right;
    _right = null;
    _active = _left;
    notifyListeners();
  }

  Future<void> close(String id) async {
    final tab = _tabs.where((t) => t.id == id).firstOrNull;
    if (tab == null) return;
    await tab.prepareClose?.call();
    await tab.controller.flush();
    _tabs.remove(tab);
    if (_left == id) {
      _left = _right;
      _right = null;
    } else if (_right == id) {
      _right = null;
    }
    _left ??= _tabs.firstOrNull?.id;
    if (_active == id || !visibleIds.contains(_active)) _active = _left;
    tab.controller.dispose();
    notifyListeners();
  }

  Future<void> flush() async {
    for (final tab in _tabs) {
      try {
        await tab.prepareClose?.call();
        await tab.controller.flush();
      } catch (_) {
        select(tab.id);
        rethrow;
      }
    }
  }

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.controller.dispose();
    }
    _tabs.clear();
    super.dispose();
  }
}

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    super.key,
    required this.services,
    required this.initialEntry,
    this.cloud,
    this.initialPageIndex = 0,
  });
  final AppServices services;
  final DocumentEntry initialEntry;
  final CloudController? cloud;
  final int initialPageIndex;
  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  late final workspace = DocumentWorkspace(
    repository: widget.services.repository,
    deviceId: widget.services.deviceId,
    newId: const Uuid().v4,
    now: DateTime.now,
  )..open(widget.initialEntry, initialPageIndex: widget.initialPageIndex);
  bool closing = false, allowPop = false;
  String? closingId;
  Future<void> _choose({bool split = false}) async {
    await widget.services.library.refresh();
    if (!mounted) return;
    final entry = await showDialog<DocumentEntry>(
      context: context,
      builder: (context) => _DocumentPicker(
        entries: widget.services.library.entries,
        excludedId: split ? workspace.visibleIds.firstOrNull : null,
      ),
    );
    if (entry == null || !mounted) return;
    final anchor = workspace.visibleIds.firstOrNull;
    final tab = workspace.open(entry);
    if (split && anchor != null) {
      workspace.select(anchor);
      workspace.splitWith(tab.id);
    }
  }

  Future<void> _split() async {
    if (workspace.split) {
      workspace.unsplit();
      return;
    }
    final other = workspace.tabs
        .where((t) => t.id != workspace.activeId)
        .firstOrNull;
    if (other == null) {
      await _choose(split: true);
    } else {
      workspace.splitWith(other.id);
    }
  }

  void _error() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'No se pudo guardar el apunte. La pestaña sigue abierta; intentá guardar nuevamente.',
        ),
      ),
    );
  }

  Future<void> _closeTab(String id) async {
    if (closing || closingId != null) return;
    setState(() => closingId = id);
    try {
      await workspace.close(id);
      if (mounted && workspace.tabs.isEmpty) {
        setState(() => allowPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
    } catch (_) {
      _error();
    } finally {
      if (mounted) setState(() => closingId = null);
    }
  }

  Future<void> _leave() async {
    if (closing || closingId != null) return;
    setState(() => closing = true);
    try {
      await workspace.flush();
      if (!mounted) return;
      setState(() => allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    } catch (_) {
      _error();
    } finally {
      if (mounted) setState(() => closing = false);
    }
  }

  @override
  void dispose() {
    workspace.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: workspace,
    builder: (context, _) => PopScope(
      canPop: allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Material(
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Cerrar espacio de trabajo',
                      onPressed: closing ? null : _leave,
                      icon: closing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.library_books_outlined),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final tab in workspace.tabs)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                  vertical: 4,
                                ),
                                child: InputChip(
                                  key: ValueKey('workspace-tab-${tab.id}'),
                                  selected: workspace.isActive(tab.id),
                                  label: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 180,
                                    ),
                                    child: Text(
                                      tab.controller.notebook.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  tooltip: tab.controller.notebook.title,
                                  onPressed: closing
                                      ? null
                                      : () => workspace.select(tab.id),
                                  onDeleted: closing || closingId != null
                                      ? null
                                      : () => _closeTab(tab.id),
                                  deleteButtonTooltipMessage:
                                      'Cerrar ${tab.controller.notebook.title}',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Abrir otro apunte',
                      onPressed: closing ? null : () => _choose(),
                      icon: const Icon(Icons.add),
                    ),
                    IconButton(
                      tooltip: workspace.split
                          ? 'Una sola vista'
                          : 'Vista dividida',
                      onPressed: closing ? null : _split,
                      isSelected: workspace.split,
                      icon: const Icon(Icons.vertical_split_outlined),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, size) {
                    final ids = workspace.visibleIds;
                    final horizontal = size.maxWidth >= 1000;
                    final two = ids.length == 2;
                    final paneWidth = two && horizontal
                        ? size.maxWidth / 2
                        : size.maxWidth;
                    final paneHeight = two && !horizontal
                        ? size.maxHeight / 2
                        : size.maxHeight;
                    return Stack(
                      children: [
                        for (final tab in workspace.tabs)
                          Positioned(
                            key: ValueKey(tab.id),
                            left: two && horizontal && ids.indexOf(tab.id) == 1
                                ? paneWidth
                                : 0,
                            top: two && !horizontal && ids.indexOf(tab.id) == 1
                                ? paneHeight
                                : 0,
                            width: paneWidth,
                            height: paneHeight,
                            child: Offstage(
                              offstage: !ids.contains(tab.id),
                              child: TickerMode(
                                enabled: ids.contains(tab.id),
                                child: Listener(
                                  onPointerDown: (_) => workspace.focus(tab.id),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: two && workspace.isActive(tab.id)
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : Colors.transparent,
                                        width: two ? 2 : 0,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: EdgeInsets.all(two ? 2 : 0),
                                      child: MediaQuery(
                                        data: MediaQuery.of(context).copyWith(
                                          size: Size(paneWidth, paneHeight),
                                        ),
                                        child: EditorScreen(
                                          key: ValueKey(
                                            'workspace-editor-${tab.id}',
                                          ),
                                          controller: tab.controller,
                                          active:
                                              workspace.isActive(tab.id) &&
                                              !closing &&
                                              closingId != tab.id,
                                          workspaceManaged: true,
                                          onClose: _leave,
                                          onFocus: () =>
                                              workspace.focus(tab.id),
                                          registerClose: (callback) =>
                                              tab.prepareClose = callback,
                                          initialPageIndex:
                                              tab.initialPageIndex,
                                          storageRoot: widget.services.root,
                                          penPreferences:
                                              widget.services.penPreferences,
                                          pdf: widget.services.pdf,
                                          files: widget.services.files,
                                          share: widget.services.share,
                                          assets: widget.services.assets,
                                          audio: widget.services.audio,
                                          audioDirectory:
                                              '${widget.services.root}/audio-temp',
                                          cloud: widget.cloud,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DocumentPicker extends StatefulWidget {
  const _DocumentPicker({required this.entries, this.excludedId});
  final List<DocumentEntry> entries;
  final String? excludedId;
  @override
  State<_DocumentPicker> createState() => _DocumentPickerState();
}

class _DocumentPickerState extends State<_DocumentPicker> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final entries = widget.entries
        .where(
          (e) =>
              e.notebook.id != widget.excludedId &&
              '${e.notebook.title} ${e.notebook.subject}'
                  .toLowerCase()
                  .contains(query.toLowerCase()),
        )
        .toList();
    return AlertDialog(
      title: const Text('Abrir otro apunte'),
      content: SizedBox(
        width: 480,
        height: 400,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Buscar un apunte',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => query = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: entries.isEmpty
                  ? const Center(child: Text('No hay otros apuntes.'))
                  : ListView(
                      children: [
                        for (final entry in entries)
                          ListTile(
                            title: Text(entry.notebook.title),
                            subtitle: Text(entry.notebook.subject),
                            leading: const Icon(Icons.menu_book_outlined),
                            onTap: () => Navigator.pop(context, entry),
                          ),
                      ],
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
