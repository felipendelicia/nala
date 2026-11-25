import 'dart:async';

import 'package:flutter/material.dart';

import '../account/cloud_controller.dart';
import '../bootstrap.dart';
import '../document/notebook.dart';
import '../document/revision.dart';
import '../editor/paper_canvas.dart';
import '../editor/stroke_geometry.dart';
import 'document_workspace.dart';

/// Respond to navigation while the exact revision is loaded for the editor.
class WorkspaceOpeningScreen extends StatefulWidget {
  const WorkspaceOpeningScreen({
    super.key,
    required this.services,
    required this.title,
    required this.loadEntry,
    required this.initialPageIndex,
    this.preview,
    this.cloud,
  });

  final AppServices services;
  final String title;
  final Future<DocumentEntry?> Function() loadEntry;
  final int initialPageIndex;
  final NotebookPage? preview;
  final CloudController? cloud;

  @override
  State<WorkspaceOpeningScreen> createState() => _WorkspaceOpeningScreenState();
}

class _WorkspaceOpeningScreenState extends State<WorkspaceOpeningScreen> {
  DocumentEntry? _entry;
  bool _loaded = false;
  bool _showHint = false;
  bool _popped = false;
  late final Timer _hint;
  late final NotebookPage? _openingPreview = _lightPreview(widget.preview);

  @override
  void initState() {
    super.initState();
    _hint = Timer(const Duration(milliseconds: 140), () {
      if (mounted && !_popped) setState(() => _showHint = true);
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    DocumentEntry? entry;
    try {
      entry = await widget.loadEntry();
    } catch (_) {
      // Unavailable revisions use the same recoverable state and back action.
    }
    _hint.cancel();
    if (!mounted || _popped) return;
    final preview = widget.preview;
    if (entry != null && preview != null) {
      _reusePreviewInk(preview, entry.notebook.pages.first);
    }
    setState(() {
      _entry = entry;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _hint.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    final preview = _loaded ? null : _openingPreview;
    final message = _loaded
        ? 'El apunte ya no está disponible.'
        : _showHint
        ? 'Cargando apunte…'
        : null;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _popped = true;
          _hint.cancel();
        }
      },
      child: entry != null
          ? WorkspaceScreen(
              services: widget.services,
              initialEntry: entry,
              initialPageIndex: widget.initialPageIndex,
              cloud: widget.cloud,
            )
          : Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  tooltip: 'Volver a mis apuntes',
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back),
                ),
                toolbarHeight: 56,
                leadingWidth: 48,
                titleSpacing: 8,
                title: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              body: ColoredBox(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.black
                    : const Color(0xffeeeeee),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (preview != null)
                      ExcludeSemantics(
                        child: IgnorePointer(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: FittedBox(
                              child: PaperCanvas(
                                page: preview,
                                tool: EditorTool.pen,
                                externalInput: true,
                                onStroke: (_) {},
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (message != null)
                      Align(
                        alignment: preview == null
                            ? Alignment.center
                            : Alignment.bottomCenter,
                        child: Padding(
                          padding: EdgeInsets.all(preview == null ? 24 : 6),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(message, textAlign: TextAlign.center),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

NotebookPage? _lightPreview(NotebookPage? page) {
  // Keep vector work on the incoming route small while it fades in.
  if (page == null || page.objects.length > 16 || hasDenseInk(page.strokes)) {
    return null;
  }
  return page;
}

void _reusePreviewInk(NotebookPage preview, NotebookPage loaded) {
  if (preview.id != loaded.id ||
      identical(preview.strokes, loaded.strokes) ||
      preview.strokes.length != loaded.strokes.length) {
    return;
  }
  for (var index = 0; index < preview.strokes.length; index++) {
    final previous = preview.strokes[index];
    final path = StrokeGeometry.cachedCanvasPath(previous);
    final current = loaded.strokes[index];
    if (path != null && _sameInkGeometry(previous, current)) {
      StrokeGeometry.rememberCanvasPath(current, path);
    }
  }
}

bool _sameInkGeometry(InkStroke a, InkStroke b) {
  if (a.id != b.id ||
      a.tool != b.tool ||
      a.width != b.width ||
      a.pressureCurve != b.pressureCurve ||
      a.sensitivity != b.sensitivity ||
      a.points.length != b.points.length) {
    return false;
  }
  for (var index = 0; index < a.points.length; index++) {
    final first = a.points[index];
    final second = b.points[index];
    if (first.x != second.x ||
        first.y != second.y ||
        first.pressure != second.pressure) {
      return false;
    }
  }
  return true;
}
