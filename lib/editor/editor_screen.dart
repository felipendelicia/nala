import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' show PdfPasswordException;
import '../document/notebook.dart';
import '../document/page_comment.dart';
import '../document/asset_store.dart';
import '../audio/audio_service.dart';
import '../audio/comment_audio_player.dart';
import 'comment_dialog.dart';
import 'comments_panel.dart';
import '../ui/app_theme.dart';
import '../ui/appearance.dart';
import 'editor_controller.dart';
import 'editor_toolbar.dart';
import 'draft_ink.dart';
import 'pen_settings_dialog.dart';
import 'zoom_controls.dart';
import 'input_router.dart';
import 'page_panel.dart';
import 'page_layout.dart';
import 'paper_canvas.dart';
import 'stroke_geometry.dart';
import 'viewport.dart' as paper;
import '../pdf/document_files.dart';
import '../pdf/pdf_service.dart';
import '../pdf/pdf_share.dart';
import '../pdf/pdf_export_service.dart';
import '../pdf/pdf_page_background.dart';
import '../pdf/password_dialog.dart';
import '../account/cloud_controller.dart';
import '../account/cloud_panel.dart';
import '../sync/sync_state.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.controller,
    this.pdf,
    this.files,
    this.share,
    this.assets,
    this.audio,
    this.audioDirectory,
    this.cloud,
  });
  final EditorController controller;
  final PdfService? pdf;
  final DocumentFiles? files;
  final PdfShare? share;
  final AssetStore? assets;
  final AudioDevice? audio;
  final String? audioDirectory;
  final CloudController? cloud;
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  bool allowPop = false, closing = false, showPages = false;
  bool disposing = false, reading = false;
  bool exporting = false, choosingShare = false;
  Notebook? exportedSnapshot;
  Uint8List? exportedBytes;
  bool showComments = false, placingComment = false, commentOpen = false;
  bool remoteDirty = false, refreshingRemote = false;
  bool get canReceiveRemote =>
      mounted &&
      !disposing &&
      !closing &&
      !exporting &&
      !choosingShare &&
      !commentOpen &&
      !router.isWriting &&
      start == null &&
      !widget.controller.saving;
  @override
  void initState() {
    super.initState();
    widget.cloud?.addListener(syncChanged);
    widget.controller.addListener(localSettled);
    rememberPageFocus();
  }

  void syncChanged() {
    if (widget.cloud?.status.phase == SyncPhase.synced) {
      remoteDirty = true;
      unawaited(refreshRemote());
    }
  }

  void localSettled() {
    reconcilePages();
    if (!widget.controller.saving) unawaited(refreshRemote());
  }

  List<NotebookPage>? observedPages;
  String? observedPageId;
  Rect? observedBounds;
  void rememberPageFocus() {
    observedPages = widget.controller.notebook.pages;
    observedPageId = page.id;
    observedBounds = layout.rect(pageIndex);
  }

  void reconcilePages() {
    final pages = widget.controller.notebook.pages;
    if (identical(pages, observedPages)) return;
    final retained =
        pageIndex < pages.length && pages[pageIndex].id == observedPageId
        ? pageIndex
        : pages.indexWhere((p) => p.id == observedPageId);
    final previousIndex = pageIndex;
    pageIndex = retained < 0 ? pageIndex.clamp(0, pages.length - 1) : retained;
    final bounds = layout.rect(pageIndex);
    if (retained < 0) {
      router.reset();
      selected = {};
      placingComment = false;
      pdfError = null;
      audioPlayer?.stop();
      if (viewSize != null) {
        view.ty = 24 - bounds.top * view.scale;
        if (!view.horizontalLocked) {
          view.tx = (viewSize!.width - layout.width * view.scale) / 2;
        }
      }
    } else if (viewSize != null && observedBounds != null) {
      // Keep the current sheet's origin when pages before it are inserted/removed.
      // Ordinary ink edits have identical bounds and leave the camera untouched.
      view.tx += (observedBounds!.left - bounds.left) * view.scale;
      view.ty += (observedBounds!.top - bounds.top) * view.scale;
    }
    if (previousIndex != pageIndex) pdfError = null;
    rememberPageFocus();
  }

  Future<void> refreshRemote() async {
    if (!remoteDirty || refreshingRemote || !canReceiveRemote) return;
    refreshingRemote = true;
    final previousPage = page.id;
    try {
      final applied = await widget.controller.refreshRemote(
        canApply: () => canReceiveRemote,
      );
      if (canReceiveRemote) remoteDirty = false;
      if (applied && mounted) {
        setState(() {
          final index = widget.controller.notebook.pages.indexWhere(
            (p) => p.id == previousPage,
          );
          if (index >= 0) pageIndex = index;
          rememberPageFocus();
          selected = {};
        });
      }
    } catch (_) {
      remoteDirty = false; // Keep local state; a later sync can retry.
    } finally {
      refreshingRemote = false;
      if (remoteDirty && canReceiveRemote) unawaited(refreshRemote());
    }
  }

  late final CommentAudioPlayer? audioPlayer =
      widget.audio != null &&
          widget.assets != null &&
          widget.audioDirectory != null
      ? CommentAudioPlayer(
          device: widget.audio!,
          assets: widget.assets!,
          directory: widget.audioDirectory!,
        )
      : null;
  Object? pdfError;
  int pdfRenderVersion = 0;
  String? neighborKey;
  final neighborTokens = <PdfRenderCancellation>[];
  int pageIndex = 0;
  EditorTool tool = EditorTool.pen, gestureTool = EditorTool.pen;
  int penColor = 0xff202020, markerColor = 0xffe9ba3b;
  double penWidth = 2.5, markerWidth = 14;
  int get argb => tool == EditorTool.highlighter ? markerColor : penColor;
  set argb(int value) {
    if (tool == EditorTool.highlighter) {
      markerColor = value;
    } else {
      penColor = value;
    }
  }

  double get width => tool == EditorTool.highlighter ? markerWidth : penWidth;
  set width(double value) {
    if (tool == EditorTool.highlighter) {
      markerWidth = value;
    } else {
      penWidth = value;
    }
  }

  List<NotebookPage>? layoutPages;
  PageLayout? cachedLayout;
  PageLayout get layout {
    final pages = widget.controller.notebook.pages;
    if (!identical(pages, layoutPages)) {
      layoutPages = pages;
      cachedLayout = PageLayout(pages);
    }
    return cachedLayout!;
  }

  final view = paper.Viewport();
  Size? viewSize;
  String? fittedPage;
  final draft = DraftInk();
  double pressureSensitivity = 1, stabilization = .08;
  final erased = <String>{};
  Set<String> selected = {};
  Offset? start, latest;
  bool movingSelection = false;
  late final router = InputRouter(
    onBegin: begin,
    onUpdate: update,
    onEnd: end,
    onCancel: cancel,
    onNavigate: navigate,
  );
  NotebookPage get page =>
      widget.controller.notebook.pages[pageIndex.clamp(
        0,
        widget.controller.notebook.pages.length - 1,
      )];
  InkPoint inkPoint(InputSample event) {
    final p = view.pagePoint(event.position), bounds = layout.rect(pageIndex);
    return InkPoint(
      x: p.x - bounds.left,
      y: p.y - bounds.top,
      pressure: event.pressure,
    );
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
    if (reading) return;
    final p = inkPoint(event);
    gestureTool = tool;
    start = latest = Offset(p.x, p.y);
    if (p.x < 0 || p.y < 0 || p.x > page.width || p.y > page.height) {
      start = latest = null;
      return;
    }
    if (tool == EditorTool.pen || tool == EditorTool.highlighter) {
      draft.begin(
        p,
        tool: tool == EditorTool.highlighter
            ? InkTool.highlighter
            : InkTool.pen,
        argb: argb,
        width: width,
        sensitivity: pressureSensitivity,
        stabilization: stabilization,
        pressureCurve: event.device == InputDevice.mouse
            ? PressureCurve.uniform
            : PressureCurve.expressive,
      );
      // The live painter is already mounted: first contact needs no UI rebuild.
      return;
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
    if (gestureTool == EditorTool.pen ||
        gestureTool == EditorTool.highlighter) {
      draft.add(p);
      return;
    }
    if (gestureTool == EditorTool.eraser) eraseAt(p, from: previous);
    setState(() {});
  }

  void eraseAt(InkPoint p, {Offset? from}) {
    for (final s in page.strokes) {
      if (StrokeGeometry.hitSweep(
        s,
        math.Point(from?.dx ?? p.x, from?.dy ?? p.y),
        math.Point(p.x, p.y),
        10 / view.scale,
      )) {
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
    final stroke = draft.finish(const Uuid().v4(), endpoint: inkPoint(event));
    if (stroke != null) {
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
        draft.cancel();
        erased.clear();
        start = latest = null;
        movingSelection = false;
      });
      unawaited(refreshRemote());
    }
  }

  void chooseTool(EditorTool selectedTool) {
    if (reading) return;
    router.reset();
    setState(() {
      tool = selectedTool;
      selected = {};
    });
  }

  Future<void> penSettings() async {
    router.reset();
    final result = await showDialog<PenSettings>(
      context: context,
      builder: (_) => PenSettingsDialog(
        settings: (pressure: pressureSensitivity, stabilization: stabilization),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        pressureSensitivity = result.pressure;
        stabilization = result.stabilization;
      });
    }
  }

  void deleteSelection() {
    if (reading) return;
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
    audioPlayer?.stop();
    setState(() {
      placingComment = false;
      pageIndex = index;
      selected = {};
      if (viewSize != null) {
        final bounds = layout.rect(index);
        view.ty = 24 - bounds.top * view.scale;
        if (!view.horizontalLocked) {
          view.tx = (viewSize!.width - layout.width * view.scale) / 2;
        }
      }
      pdfError = null;
      rememberPageFocus();
    });
  }

  void addPage() {
    if (reading) return;
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

  void navigate(
    double dx,
    double dy,
    double factor,
    math.Point<double> anchor,
  ) {
    if (router.isWriting || commentOpen) return;
    setState(() {
      view.zoom(factor, anchor);
      view.pan(dx, dy);
      if (viewSize != null) {
        // A small elastic margin lets users position the first/last line comfortably.
        final margin = viewSize!.height / 3;
        view.ty = view.ty.clamp(
          math.min(
            -margin,
            viewSize!.height - layout.height * view.scale - margin,
          ),
          margin,
        );
        final index = layout.nearest(
          (viewSize!.height / 2 - view.ty) / view.scale,
        );
        if (index != pageIndex) {
          pageIndex = index;
          selected = {};
          pdfError = null;
          audioPlayer?.stop();
        }
      }
      rememberPageFocus();
    });
  }

  Widget buildDocument(BuildContext context, BoxConstraints constraints) {
    if (viewSize == null || fittedPage == null) {
      view.fit(
        constraints.maxWidth,
        constraints.maxHeight,
        page.width,
        page.height,
      );
      final bounds = layout.rect(pageIndex);
      view.tx -= bounds.left * view.scale;
      view.ty -= bounds.top * view.scale;
      fittedPage = page.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !disposing) setState(() {});
      });
    }
    viewSize = constraints.biggest;
    final visible = layout.visible(
      Rect.fromLTWH(
        -view.tx / view.scale,
        -view.ty / view.scale,
        constraints.maxWidth / view.scale,
        constraints.maxHeight / view.scale,
      ),
    );
    return ClipRect(
      child: Listener(
        key: const ValueKey('document-viewport'),
        behavior: HitTestBehavior.opaque,
        onPointerDown: pointerDown,
        onPointerMove: (e) => router.move(sample(e)),
        onPointerUp: (e) => router.up(sample(e)),
        onPointerCancel: (e) => router.cancel(e.pointer),
        onPointerHover: (e) => router.hover(sample(e)),
        onPointerPanZoomUpdate: (e) {
          navigate(
            e.panDelta.dx,
            e.panDelta.dy,
            e.scale / trackpadScale,
            math.Point(e.localPosition.dx, e.localPosition.dy),
          );
          trackpadScale = e.scale;
        },
        onPointerPanZoomStart: (_) {
          trackpadScale = 1;
        },
        onPointerPanZoomEnd: (_) {
          trackpadScale = 1;
        },
        onPointerSignal: (e) {
          if (e is! PointerScrollEvent || router.isWriting) return;
          final zooming = HardwareKeyboard.instance.isControlPressed;
          navigate(
            zooming ? 0 : -e.scrollDelta.dx,
            zooming ? 0 : -e.scrollDelta.dy,
            zooming ? math.exp(-e.scrollDelta.dy / 500) : 1,
            math.Point(e.localPosition.dx, e.localPosition.dy),
          );
        },
        child: ColoredBox(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xff11191e)
              : const Color(0xffe8eef0),
          child: Stack(
            children: [for (final index in visible) buildPage(context, index)],
          ),
        ),
      ),
    );
  }

  double trackpadScale = 1;

  Widget buildPage(BuildContext context, int index) {
    final source = widget.controller.notebook.pages[index],
        bounds = layout.rect(index);
    final active = index == pageIndex;
    var display = source;
    if (active && erased.isNotEmpty) {
      display = display.copyWith(
        strokes: display.strokes.where((s) => !erased.contains(s.id)).toList(),
      );
    }
    if (active && movingSelection && start != null && latest != null) {
      final delta = latest! - start!;
      display = display.copyWith(
        strokes: display.strokes
            .map(
              (s) => selected.contains(s.id)
                  ? StrokeGeometry.translate(s, delta.dx, delta.dy)
                  : s,
            )
            .toList(),
      );
    }
    return Positioned(
      key: ValueKey('sheet-${source.id}'),
      left: view.tx + bounds.left * view.scale,
      top: view.ty + bounds.top * view.scale,
      width: source.width,
      height: source.height,
      child: Transform.scale(
        scale: view.scale,
        alignment: Alignment.topLeft,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Color(0x1c29424b),
                  blurRadius: 18,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PaperCanvas(
                    key: ValueKey('canvas-${source.id}'),
                    page: display,
                    externalInput: true,
                    tool: tool,
                    onStroke: (_) {},
                    background:
                        widget.pdf == null || source.background.assetId == null
                        ? null
                        : PdfPageBackground(
                            key: ValueKey('${source.id}-$pdfRenderVersion'),
                            pdf: widget.pdf!,
                            page: source,
                            scale:
                                view.scale *
                                MediaQuery.devicePixelRatioOf(context),
                            onError: (error) {
                              if (mounted && source.id == page.id) {
                                setState(() => pdfError = error);
                              }
                            },
                            onRendered: preloadNeighbors,
                          ),
                  ),
                  if (active)
                    RepaintBoundary(
                      child: CustomPaint(painter: DraftInkPainter(draft)),
                    ),
                  CustomPaint(
                    painter: CommentPinsPainter(source.comments, view.scale),
                  ),
                  if (active)
                    CustomPaint(
                      painter: _SelectionPainter(
                        display,
                        selected,
                        gestureTool == EditorTool.selection &&
                                !movingSelection &&
                                start != null &&
                                latest != null
                            ? Rect.fromPoints(start!, latest!)
                            : null,
                        view.scale,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> close() async {
    if (closing) return;
    router.reset();
    closing = true;
    try {
      await audioPlayer?.stop();
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

  void placeComment() {
    if (reading) return;
    router.reset();
    setState(() => placingComment = true);
  }

  Future<void> openComment(PageComment comment, {bool creating = false}) async {
    if (commentOpen) return;
    router.reset();
    final pageId = page.id;
    commentOpen = true;
    try {
      await audioPlayer?.stop();
      if (!mounted) return;
      final result = await showDialog<PageComment>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CommentDialog(
          comment: comment,
          readOnly: reading,
          assets: widget.assets,
          audio: widget.audio,
          directory: widget.audioDirectory,
          player: audioPlayer,
        ),
      );
      if (result != null && mounted && !reading) {
        widget.controller.apply(
          (book) => book.copyWith(
            pages: book.pages
                .map(
                  (p) => p.id != pageId
                      ? p
                      : p.copyWith(
                          comments: creating
                              ? [...p.comments, result]
                              : p.comments
                                    .map((c) => c.id == result.id ? result : c)
                                    .toList(),
                        ),
                )
                .toList(),
          ),
        );
      }
    } finally {
      commentOpen = false;
      unawaited(refreshRemote());
    }
  }

  void pointerDown(PointerDownEvent event) {
    if (commentOpen) return;
    final documentPoint = view.pagePoint(
      math.Point(event.localPosition.dx, event.localPosition.dy),
    );
    final hit = layout.hit(Offset(documentPoint.x, documentPoint.y));
    if (!router.isWriting && hit != null && hit != pageIndex) {
      setState(() {
        pageIndex = hit;
        rememberPageFocus();
        selected = {};
        pdfError = null;
      });
    }
    final bounds = layout.rect(pageIndex);
    final position = math.Point(
      documentPoint.x - bounds.left,
      documentPoint.y - bounds.top,
    );
    if (hit == null && placingComment) return;
    if (placingComment && !reading) {
      if (position.x < 0 ||
          position.y < 0 ||
          position.x > page.width ||
          position.y > page.height) {
        return;
      }
      setState(() => placingComment = false);
      openComment(
        PageComment(
          id: const Uuid().v4(),
          x: position.x,
          y: position.y,
          text: '',
          createdAt: DateTime.now().toUtc(),
        ),
        creating: true,
      );
      return;
    }
    if (!router.isWriting) {
      for (final comment in page.comments.reversed) {
        if (math.sqrt(
              math.pow(position.x - comment.x, 2) +
                  math.pow(position.y - comment.y, 2),
            ) <=
            15 / view.scale) {
          openComment(comment);
          return;
        }
      }
    }
    router.down(sample(event));
  }

  void deleteComment(PageComment comment) {
    if (reading) return;
    audioPlayer?.stop();
    editPage(
      (p) => p.copyWith(
        comments: p.comments.where((c) => c.id != comment.id).toList(),
      ),
    );
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

  Future<bool> unlockPdf({String? assetId}) async {
    final id = assetId ?? page.background.assetId;
    if (id == null || widget.pdf == null) return false;
    var incorrect = false;
    while (true) {
      if (!mounted) return false;
      final password = await askPdfPassword(context, incorrect: incorrect);
      if (password == null || !mounted) return false;
      try {
        await widget.pdf!.unlock(id, password);
        if (mounted) {
          setState(() {
            pdfError = null;
            pdfRenderVersion++;
            neighborKey = null;
          });
        }
        return true;
      } on PdfPasswordException {
        incorrect = true;
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo abrir el PDF.')),
          );
        }
        return false;
      }
    }
  }

  void preloadNeighbors() {
    final pdf = widget.pdf;
    if (pdf == null || !mounted) return;
    final key =
        '${page.id}:${PdfService.scaleStep(view.scale)}:${widget.controller.notebook.pages.length}';
    if (key == neighborKey) return;
    neighborKey = key;
    for (final token in neighborTokens) {
      token.cancel();
    }
    neighborTokens.clear();
    final pages = widget.controller.notebook.pages;
    for (final index in [pageIndex - 1, pageIndex + 1]) {
      if (index < 0 ||
          index >= pages.length ||
          pages[index].background.assetId == null) {
        continue;
      }
      final neighbor = pages[index];
      final token = PdfRenderCancellation();
      neighborTokens.add(token);
      pdf
          .renderBackground(
            neighbor.background.assetId!,
            neighbor.background.pageNumber!,
            scale: view.scale,
            cancellation: token,
          )
          .then<void>((_) {
            if (mounted && !token.isCancelled) setState(() {});
          }, onError: (Object _) {});
    }
    setState(() {});
  }

  Future<void> sharePdf() async {
    final service = widget.share;
    if (service == null || exporting || choosingShare) return;
    ShareTarget? target;
    if (service.targets.length == 1) {
      target = service.targets.single;
    } else {
      choosingShare = true;
      router.reset();
      try {
        target = await showModalBottomSheet<ShareTarget>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Compartir PDF',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (service.targets.contains(ShareTarget.copyFile))
                    ListTile(
                      leading: const Icon(Icons.copy_outlined),
                      title: const Text('Copiar archivo PDF'),
                      subtitle: const Text(
                        'Pegalo en un chat o en otra aplicación.',
                      ),
                      onTap: () => Navigator.pop(context, ShareTarget.copyFile),
                    ),
                  if (service.targets.contains(ShareTarget.email))
                    ListTile(
                      leading: const Icon(Icons.mail_outline),
                      title: const Text('Compartir por correo'),
                      subtitle: const Text(
                        'Abrir un mensaje con el PDF adjunto.',
                      ),
                      onTap: () => Navigator.pop(context, ShareTarget.email),
                    ),
                ],
              ),
            ),
          ),
        );
      } finally {
        choosingShare = false;
      }
    }
    if (mounted && target != null) await deliverPdf(shareTarget: target);
  }

  Future<void> exportPdf() => deliverPdf();
  Future<void> deliverPdf({ShareTarget? shareTarget}) async {
    if (exporting ||
        widget.pdf == null ||
        (shareTarget == null ? widget.files == null : widget.share == null)) {
      return;
    }
    setState(() => exporting = true);
    try {
      final snapshot = widget.controller.notebook;
      await widget.controller.flush();
      Uint8List? bytes;
      if (identical(snapshot, exportedSnapshot)) bytes = exportedBytes;
      bytes ??= await PdfExportService(widget.pdf!).exportWithUnlock(
        snapshot,
        (assetId) =>
            mounted ? unlockPdf(assetId: assetId) : Future.value(false),
      );
      if (!mounted || bytes == null) return;
      // Cache one reasonably sized snapshot, never a growing set of PDFs.
      if (bytes.length <= 32 * 1024 * 1024) {
        exportedSnapshot = snapshot;
        exportedBytes = bytes;
      }
      if (shareTarget != null) {
        final accepted = await widget.share!.share(
          bytes,
          name: snapshot.title,
          target: shareTarget,
        );
        if (!accepted) throw StateError('No hay una aplicación disponible.');
        if (mounted && shareTarget == ShareTarget.copyFile) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDF copiado. Pegalo donde quieras compartirlo.'),
            ),
          );
        }
      } else {
        final saved = await widget.files!.savePdf(bytes, name: snapshot.title);
        if (mounted && saved) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('PDF guardado.')));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              shareTarget == null
                  ? 'No se pudo exportar el PDF. Tus anotaciones siguen guardadas en Nala.'
                  : 'No se pudo compartir el PDF. Tus anotaciones siguen guardadas. Podés reintentar o guardar una copia.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => exporting = false);
        unawaited(refreshRemote());
      }
    }
  }

  @override
  void dispose() {
    disposing = true;
    widget.cloud?.removeListener(syncChanged);
    widget.controller.removeListener(localSettled);
    for (final token in neighborTokens) {
      token.cancel();
    }
    router.reset();
    draft.dispose();
    audioPlayer?.dispose();
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
            if (reading) return;
            router.reset();
            controller.undo();
          },
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            control: true,
            shift: true,
          ): () {
            if (reading) return;
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
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      controller.notebook.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (controller.notebook.subject.isNotEmpty)
                      Text(
                        controller.notebook.subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                actions: [
                  AppearanceButton(beforeChange: router.reset),
                  IconButton(
                    tooltip: reading ? 'Modo editor' : 'Modo lectura',
                    isSelected: reading,
                    onPressed: () {
                      router.reset();
                      setState(() {
                        reading = !reading;
                        placingComment = false;
                        router.readOnly = reading;
                        selected = {};
                      });
                    },
                    icon: Icon(
                      reading ? Icons.edit_outlined : Icons.menu_book_outlined,
                    ),
                  ),
                  if (widget.pdf != null && widget.share != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Tooltip(
                        message: 'Compartir PDF',
                        child: MediaQuery.sizeOf(context).width >= 1100
                            ? FilledButton.icon(
                                onPressed: exporting || choosingShare
                                    ? null
                                    : sharePdf,
                                icon: const Icon(
                                  Icons.share_outlined,
                                  size: 19,
                                ),
                                label: const Text('Compartir'),
                              )
                            : IconButton.filledTonal(
                                onPressed: exporting || choosingShare
                                    ? null
                                    : sharePdf,
                                icon: const Icon(Icons.share_outlined),
                              ),
                      ),
                    ),
                  if (widget.pdf != null && widget.files != null)
                    IconButton(
                      tooltip: 'Exportar PDF',
                      onPressed: exporting ? null : exportPdf,
                      icon: const Icon(Icons.ios_share_outlined),
                    ),
                  PopupMenuButton<String>(
                    tooltip: 'Opciones del cuaderno',
                    onSelected: (_) {
                      router.reset();
                      rename();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'rename',
                        enabled: !reading,
                        child: const Text('Renombrar cuaderno'),
                      ),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Páginas',
                    isSelected: showPages,
                    onPressed: () {
                      router.reset();
                      setState(() => showPages = !showPages);
                    },
                    icon: const Icon(Icons.view_sidebar_outlined),
                  ),
                  IconButton(
                    tooltip: 'Comentarios',
                    isSelected: showComments,
                    onPressed: () {
                      router.reset();
                      setState(() => showComments = !showComments);
                    },
                    icon: const Icon(Icons.chat_bubble_outline),
                  ),
                ],
              ),
              body: Column(
                children: [
                  if (!reading)
                    EditorToolbar(
                      tool: tool,
                      onTool: chooseTool,
                      onPenSettings: penSettings,
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
                                                background:
                                                    PageBackground.paper(
                                                      currentPage
                                                          .background
                                                          .pattern!,
                                                    ),
                                              ),
                                      )
                                      .toList(),
                                ),
                              );
                            },
                    ),
                  Expanded(
                    child: Stack(
                      children: [
                        Row(
                          children: [
                            if (showPages)
                              PagePanel(
                                pages: controller.notebook.pages,
                                currentPage: pageIndex,
                                onPage: changePage,
                                onAdd: reading ? null : addPage,
                                pdf: widget.pdf,
                              ),
                            Expanded(
                              child: LayoutBuilder(builder: buildDocument),
                            ),
                            if (showComments)
                              CommentsPanel(
                                comments: currentPage.comments,
                                onOpen: openComment,
                                onClose: () {
                                  router.reset();
                                  setState(() => showComments = false);
                                },
                                onAdd: reading ? null : placeComment,
                                onDelete: reading ? null : deleteComment,
                                player: audioPlayer,
                              ),
                          ],
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Column(
                            children: [
                              if (exporting)
                                const LinearProgressIndicator(minHeight: 2),
                              if (placingComment)
                                MaterialBanner(
                                  content: const Text(
                                    'Elegí un lugar de la hoja para tu comentario.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => setState(
                                        () => placingComment = false,
                                      ),
                                      child: const Text('Cancelar'),
                                    ),
                                  ],
                                ),
                              if (exporting)
                                const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Text(
                                    'Preparando PDF… Podés seguir anotando.',
                                  ),
                                ),
                              if (pdfError != null)
                                MaterialBanner(
                                  content: Text(
                                    pdfError is PdfPasswordException
                                        ? 'Este PDF necesita su contraseña.'
                                        : 'No se pudo mostrar el fondo PDF.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed:
                                          pdfError is PdfPasswordException
                                          ? () => unlockPdf()
                                          : () => setState(() {
                                              pdfError = null;
                                              pdfRenderVersion++;
                                              neighborKey = null;
                                            }),
                                      child: Text(
                                        pdfError is PdfPasswordException
                                            ? 'Desbloquear'
                                            : 'Reintentar',
                                      ),
                                    ),
                                  ],
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
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              if (MediaQuery.sizeOf(context).width >= 1100)
                                SizedBox(
                                  width: 180,
                                  child:
                                      controller.saving ||
                                          controller.savingError != null
                                      ? Text(
                                          controller.saving
                                              ? 'Guardando…'
                                              : controller.savingError != null
                                              ? 'Guardado pendiente'
                                              : 'Guardado en este dispositivo',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        )
                                      : CloudStatus(cloud: widget.cloud),
                                ),
                              IconButton(
                                tooltip: 'Hoja anterior',
                                onPressed: pageIndex > 0
                                    ? () => changePage(pageIndex - 1)
                                    : null,
                                icon: const Icon(Icons.chevron_left, size: 20),
                              ),
                              Tooltip(
                                message: 'Hoja actual',
                                child: Text(
                                  '${pageIndex + 1}/${controller.notebook.pages.length}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Hoja siguiente',
                                onPressed:
                                    pageIndex + 1 <
                                        controller.notebook.pages.length
                                    ? () => changePage(pageIndex + 1)
                                    : null,
                                icon: const Icon(Icons.chevron_right, size: 20),
                              ),
                              if (!reading)
                                IconButton(
                                  tooltip: 'Agregar hoja',
                                  onPressed: addPage,
                                  icon: const Icon(
                                    Icons.note_add_outlined,
                                    size: 20,
                                  ),
                                ),
                              Container(
                                width: 1,
                                height: 24,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                              ZoomControls(
                                scale: view.scale,
                                locked: view.zoomLocked,
                                horizontalLocked: view.horizontalLocked,
                                onHorizontalLock: () {
                                  router.reset();
                                  setState(
                                    () => view.horizontalLocked =
                                        !view.horizontalLocked,
                                  );
                                },
                                onZoom: zoom,
                                onScale: (value) {
                                  if (viewSize != null && !router.isWriting) {
                                    setState(
                                      () => view.setScale(
                                        value,
                                        math.Point(
                                          viewSize!.width / 2,
                                          viewSize!.height / 2,
                                        ),
                                      ),
                                    );
                                  }
                                },
                                onFit: () {
                                  router.reset();
                                  setState(() => fittedPage = null);
                                },
                                onFitWidth: () {
                                  if (viewSize != null && !router.isWriting) {
                                    setState(() {
                                      view.fitWidth(
                                        viewSize!.width,
                                        viewSize!.height,
                                        page.width,
                                        page.height,
                                      );
                                      view.tx -=
                                          layout.rect(pageIndex).left *
                                          view.scale;
                                      view.ty -=
                                          layout.rect(pageIndex).top *
                                          view.scale;
                                    });
                                  }
                                },
                                onLock: () {
                                  router.reset();
                                  setState(
                                    () => view.zoomLocked = !view.zoomLocked,
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
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
