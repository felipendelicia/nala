import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../document/notebook.dart';
import '../ui/app_theme.dart';
import 'editor_controller.dart';
import 'editor_toolbar.dart';
import 'input_router.dart';
import 'page_panel.dart';
import 'paper_canvas.dart';
import 'stroke_geometry.dart';
import 'viewport.dart' as paper;

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.controller});
  final EditorController controller;
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  bool allowPop = false, closing = false, showPages = false;
  bool disposing = false;
  int pageIndex = 0;
  EditorTool tool = EditorTool.pen, gestureTool = EditorTool.pen;
  int argb = 0xff202020;
  double width = 2.5;
  final view = paper.Viewport();
  Size? viewSize;
  String? fittedPage;
  List<InkPoint> draft = [];
  final erased = <String>{};
  Set<String> selected = {};
  Offset? start, latest;
  bool movingSelection = false;
  late final router = InputRouter(
    onBegin: begin,
    onUpdate: update,
    onEnd: end,
    onCancel: cancel,
    onNavigate: (dx, dy, factor, anchor) {
      setState(() {
        view.zoom(factor, anchor);
        view.pan(dx, dy);
      });
    },
  );
  NotebookPage get page =>
      widget.controller.notebook.pages[pageIndex.clamp(
        0,
        widget.controller.notebook.pages.length - 1,
      )];
  InkPoint inkPoint(InputSample event) {
    final p = view.pagePoint(event.position);
    return InkPoint(x: p.x, y: p.y, pressure: event.pressure);
  }

  Offset offset(InputSample event) {
    final p = inkPoint(event);
    return Offset(p.x, p.y);
  }

  InputSample sample(PointerEvent event) {
    final range = event.pressureMax - event.pressureMin;
    return InputSample(
      pointerId: event.pointer,
      device: event.kind == PointerDeviceKind.touch
          ? InputDevice.touch
          : event.kind == PointerDeviceKind.mouse
          ? InputDevice.mouse
          : InputDevice.pen,
      position: math.Point(event.localPosition.dx, event.localPosition.dy),
      pressure: (range > 0 ? (event.pressure - event.pressureMin) / range : 1.0)
          .clamp(0, 1),
      buttons: event.buttons,
    );
  }

  void begin(InputSample event) {
    final p = inkPoint(event);
    gestureTool = tool;
    start = latest = Offset(p.x, p.y);
    if (p.x < 0 || p.y < 0 || p.x > page.width || p.y > page.height) {
      start = latest = null;
      return;
    }
    if (tool == EditorTool.pen || tool == EditorTool.highlighter) {
      draft = [p];
    }
    if (tool == EditorTool.eraser) eraseAt(p);
    if (tool == EditorTool.selection) {
      movingSelection = page.strokes.any(
        (s) =>
            selected.contains(s.id) &&
            StrokeGeometry.bounds(s).inflate(4).contains(start!),
      );
      if (!movingSelection) selected = {};
    }
    setState(() {});
  }

  void update(InputSample event) {
    if (start == null) return;
    final p = inkPoint(event);
    final previous = latest;
    latest = Offset(p.x, p.y);
    if (gestureTool == EditorTool.pen || gestureTool == EditorTool.highlighter) {
      draft.add(p);
    }
    if (gestureTool == EditorTool.eraser) eraseAt(p, from: previous);
    setState(() {});
  }

  void eraseAt(InkPoint p, {Offset? from}) {
    for (final s in page.strokes) {
      if (StrokeGeometry.hitSweep(s, math.Point(from?.dx ?? p.x, from?.dy ?? p.y), math.Point(p.x, p.y), 10 / view.scale)) {
        erased.add(s.id);
      }
    }
  }

  void editPage(NotebookPage Function(NotebookPage) edit) {
    final id = page.id;
    widget.controller.apply(
      (book) => book.copyWith(
        pages: book.pages.map((p) => p.id == id ? edit(p) : p).toList(),
      ),
    );
  }

  void end(InputSample event) {
    if (start == null) {
      cancel();
      return;
    }
    if (draft.isNotEmpty) {
      final stroke = InkStroke(
        id: const Uuid().v4(),
        tool: gestureTool == EditorTool.highlighter
            ? InkTool.highlighter
            : InkTool.pen,
        argb: argb,
        width: width,
        points: draft,
      );
      editPage((p) => p.copyWith(strokes: [...p.strokes, stroke]));
    } else if (gestureTool == EditorTool.eraser && erased.isNotEmpty) {
      final ids = Set<String>.of(erased);
      editPage(
        (p) => p.copyWith(
          strokes: p.strokes.where((s) => !ids.contains(s.id)).toList(),
        ),
      );
    } else if (gestureTool == EditorTool.selection && latest != null) {
      if (movingSelection) {
        final delta = latest! - start!;
        if (delta.distance > .01) {
          editPage(
            (p) => p.copyWith(
              strokes: p.strokes
                  .map(
                    (s) => selected.contains(s.id)
                        ? StrokeGeometry.translate(s, delta.dx, delta.dy)
                        : s,
                  )
                  .toList(),
            ),
          );
        }
      } else {
        final rect = Rect.fromPoints(start!, latest!);
        selected = page.strokes
            .where((s) => StrokeGeometry.bounds(s).overlaps(rect.inflate(1)))
            .map((s) => s.id)
            .toSet();
      }
    }
    cancel();
  }

  void cancel() {
    if (mounted && !disposing) {
      setState(() {
        draft = [];
        erased.clear();
        start = latest = null;
        movingSelection = false;
      });
    }
  }

  void chooseTool(EditorTool selectedTool) {
    router.reset();
    setState(() {
      tool = selectedTool;
      selected = {};
    });
  }

  void deleteSelection() {
    if (selected.isEmpty) return;
    final ids = Set<String>.of(selected);
    editPage(
      (p) => p.copyWith(
        strokes: p.strokes.where((s) => !ids.contains(s.id)).toList(),
      ),
    );
    setState(() => selected = {});
  }

  void changePage(int index) {
    router.reset();
    setState(() {
      pageIndex = index;
      selected = {};
      fittedPage = null;
    });
  }

  void addPage() {
    router.reset();
    final after = pageIndex.clamp(
      0,
      widget.controller.notebook.pages.length - 1,
    );
    final pattern = page.background.pattern ?? PaperPattern.grid;
    widget.controller.apply(
      (book) => book.copyWith(
        pages: [
          ...book.pages.take(after + 1),
          NotebookPage(
            id: const Uuid().v4(),
            width: 595.28,
            height: 841.89,
            background: PageBackground.paper(pattern),
          ),
          ...book.pages.skip(after + 1),
        ],
      ),
    );
    changePage(after + 1);
  }

  void zoom(double factor) {
    if (viewSize != null && !router.isWriting) {
      setState(
        () => view.zoom(
          factor,
          math.Point(viewSize!.width / 2, viewSize!.height / 2),
        ),
      );
    }
  }

  Future<void> close() async {
    if (closing) return;
    router.reset();
    closing = true;
    try {
      await widget.controller.flush();
      if (!mounted) return;
      setState(() => allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tus últimos cambios todavía no se guardaron. Reintentá antes de salir.',
            ),
          ),
        );
      }
    } finally {
      closing = false;
    }
  }

  Future<void> rename() async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(title: widget.controller.notebook.title),
    );
    if (title != null && title.trim().isNotEmpty && mounted) {
      widget.controller.apply((book) => book.copyWith(title: title.trim()));
    }
  }

  @override
  void dispose() {
    disposing = true;
    router.reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final currentPage = page;
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
            router.reset();
            controller.undo();
          },
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            control: true,
            shift: true,
          ): () {
            router.reset();
            controller.redo();
          },
          const SingleActivator(LogicalKeyboardKey.keyP): () =>
              chooseTool(EditorTool.pen),
          const SingleActivator(LogicalKeyboardKey.keyH): () =>
              chooseTool(EditorTool.highlighter),
          const SingleActivator(LogicalKeyboardKey.keyE): () =>
              chooseTool(EditorTool.eraser),
          const SingleActivator(LogicalKeyboardKey.keyS): () =>
              chooseTool(EditorTool.selection),
          const SingleActivator(LogicalKeyboardKey.delete): deleteSelection,
        },
        child: Focus(
          autofocus: true,
          child: PopScope(
            canPop: allowPop,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) close();
            },
            child: Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  tooltip: 'Volver a mis apuntes',
                  onPressed: close,
                  icon: const Icon(Icons.arrow_back),
                ),
                title: Text(
                  controller.notebook.title,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  IconButton(
                    tooltip: 'Renombrar cuaderno',
                    onPressed: rename,
                    icon: const Icon(Icons.drive_file_rename_outline),
                  ),
                  IconButton(
                    tooltip: 'Páginas',
                    isSelected: showPages,
                    onPressed: () => setState(() {
                      showPages = !showPages;
                      fittedPage = null;
                    }),
                    icon: const Icon(Icons.view_sidebar_outlined),
                  ),
                  IconButton(
                    tooltip: 'Hoja anterior',
                    onPressed: pageIndex > 0
                        ? () => changePage(pageIndex - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('${pageIndex + 1}/${controller.notebook.pages.length}'),
                  IconButton(
                    tooltip: 'Hoja siguiente',
                    onPressed: pageIndex + 1 < controller.notebook.pages.length
                        ? () => changePage(pageIndex + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                  IconButton(
                    tooltip: 'Agregar hoja',
                    onPressed: addPage,
                    icon: const Icon(Icons.note_add_outlined),
                  ),
                ],
              ),
              body: Column(
                children: [
                  EditorToolbar(
                    tool: tool,
                    onTool: chooseTool,
                    argb: argb,
                    onColor: (c) => setState(() => argb = c),
                    width: width,
                    onWidth: (w) => setState(() => width = w),
                    canUndo: controller.canUndo,
                    canRedo: controller.canRedo,
                    onUndo: () {
                      router.reset();
                      controller.undo();
                    },
                    onRedo: () {
                      router.reset();
                      controller.redo();
                    },
                    onDeleteSelection: selected.isEmpty
                        ? null
                        : deleteSelection,
                    pattern: currentPage.background.pattern,
                    onPattern: (pattern) {
                      router.reset();
                      editPage(
                        (p) => p.copyWith(
                          background: PageBackground.paper(pattern),
                        ),
                      );
                    },
                    onApplyPattern: currentPage.background.pattern == null
                        ? null
                        : () {
                            router.reset();
                            controller.apply(
                              (book) => book.copyWith(
                                pages: book.pages
                                    .map(
                                      (p) => p.background.pattern == null
                                          ? p
                                          : p.copyWith(
                                              background: PageBackground.paper(
                                                currentPage.background.pattern!,
                                              ),
                                            ),
                                    )
                                    .toList(),
                              ),
                            );
                          },
                  ),
                  if (controller.savingError != null)
                    MaterialBanner(
                      content: const Text(
                        'No se pudo guardar. Tus cambios siguen en memoria.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: controller.retrySave,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  Expanded(
                    child: Row(
                      children: [
                        if (showPages)
                          PagePanel(
                            pages: controller.notebook.pages,
                            currentPage: pageIndex,
                            onPage: changePage,
                            onAdd: addPage,
                          ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              if (viewSize != constraints.biggest ||
                                  fittedPage != currentPage.id) {
                                viewSize = constraints.biggest;
                                fittedPage = currentPage.id;
                                view.fit(
                                  constraints.maxWidth,
                                  constraints.maxHeight,
                                  currentPage.width,
                                  currentPage.height,
                                );
                              }
                              var displayPage = currentPage;
                              if (erased.isNotEmpty) {
                                displayPage = displayPage.copyWith(
                                  strokes: displayPage.strokes
                                      .where((s) => !erased.contains(s.id))
                                      .toList(),
                                );
                              }
                              if (movingSelection &&
                                  start != null &&
                                  latest != null) {
                                final delta = latest! - start!;
                                displayPage = displayPage.copyWith(
                                  strokes: displayPage.strokes
                                      .map(
                                        (s) => selected.contains(s.id)
                                            ? StrokeGeometry.translate(
                                                s,
                                                delta.dx,
                                                delta.dy,
                                              )
                                            : s,
                                      )
                                      .toList(),
                                );
                              }
                              final draftStroke = draft.isEmpty
                                  ? null
                                  : InkStroke(
                                      id: 'draft',
                                      tool:
                                          gestureTool == EditorTool.highlighter
                                          ? InkTool.highlighter
                                          : InkTool.pen,
                                      argb: argb,
                                      width: width,
                                      points: draft,
                                    );
                              return ClipRect(
                                child: Listener(
                                  behavior: HitTestBehavior.opaque,
                                  onPointerDown: (e) => router.down(sample(e)),
                                  onPointerMove: (e) => router.move(sample(e)),
                                  onPointerUp: (e) => router.up(sample(e)),
                                  onPointerCancel: (e) =>
                                      router.cancel(e.pointer),
                                  onPointerHover: (e) =>
                                      router.hover(sample(e)),
                                  onPointerSignal: (e) {
                                    if (e is PointerScrollEvent &&
                                        !router.isWriting) {
                                      setState(
                                        () => view.zoom(
                                          math.exp(-e.scrollDelta.dy / 500),
                                          math.Point(
                                            e.localPosition.dx,
                                            e.localPosition.dy,
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  child: ColoredBox(
                                    color: const Color(0xffe8ece6),
                                    child: Stack(
                                      children: [
                                        Positioned(
                                          left: 0,
                                          top: 0,
                                          width: currentPage.width,
                                          height: currentPage.height,
                                          child: Transform(
                                            transform: view.matrix,
                                            alignment: Alignment.topLeft,
                                            child: IgnorePointer(
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  PaperCanvas(
                                                    page: displayPage,
                                                    tool: tool,
                                                    onStroke: (_) {},
                                                  ),
                                                  if (draftStroke != null)
                                                    CustomPaint(
                                                      painter: InkPainter([
                                                        draftStroke,
                                                      ]),
                                                    ),
                                                  CustomPaint(
                                                    painter: _SelectionPainter(
                                                      displayPage,
                                                      selected,
                                                      gestureTool ==
                                                                  EditorTool
                                                                      .selection &&
                                                              !movingSelection &&
                                                              start != null &&
                                                              latest != null
                                                          ? Rect.fromPoints(
                                                              start!,
                                                              latest!,
                                                            )
                                                          : null,
                                                      view.scale,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            size: 16,
                            color: nalaGreen,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              controller.saving
                                  ? 'Guardando…'
                                  : controller.savingError != null
                                  ? 'Guardado pendiente'
                                  : 'Guardado en este dispositivo',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Alejar',
                            onPressed: () => zoom(.8),
                            icon: const Icon(Icons.remove),
                          ),
                          Text('${(view.scale * 100).round()}%'),
                          IconButton(
                            tooltip: 'Acercar',
                            onPressed: () => zoom(1.25),
                            icon: const Icon(Icons.add),
                          ),
                          IconButton(
                            tooltip: 'Ajustar hoja',
                            onPressed: () => setState(() => fittedPage = null),
                            icon: const Icon(Icons.fit_screen),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _SelectionPainter extends CustomPainter {
  _SelectionPainter(this.page, this.ids, this.rectangle, this.scale);
  final NotebookPage page;
  final Set<String> ids;
  final Rect? rectangle;
  final double scale;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = nalaGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / scale;
    for (final stroke in page.strokes) {
      if (ids.contains(stroke.id)) {
        canvas.drawRect(StrokeGeometry.bounds(stroke).inflate(3), paint);
      }
    }
    if (rectangle != null) {
      canvas.drawRect(rectangle!, Paint()..color = nalaGreen.withAlpha(24));
      canvas.drawRect(rectangle!, paint);
    }
  }

  @override
  bool shouldRepaint(_SelectionPainter old) => true;
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.title});
  final String title;
  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final text = TextEditingController(text: widget.title);
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Renombrar cuaderno'),
    content: TextField(
      controller: text,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Nombre del cuaderno'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, text.text),
        child: const Text('Guardar'),
      ),
    ],
  );
}
