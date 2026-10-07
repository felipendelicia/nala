import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:uuid/uuid.dart';
import 'dart:typed_data';
import '../document/asset_store.dart';
import '../document/notebook.dart';
import '../document/page_object.dart';
import 'paper_background.dart';
import 'stroke_geometry.dart';
import 'draft_ink.dart';

class PaperCanvas extends StatefulWidget {
  const PaperCanvas({
    super.key,
    required this.page,
    required this.onStroke,
    required this.tool,
    this.argb = 0xff202020,
    this.width = 2,
    this.background,
    this.externalInput = false,
    this.assets,
  });
  final NotebookPage page;
  final ValueChanged<InkStroke> onStroke;
  final EditorTool tool;
  final int argb;
  final double width;
  final Widget? background;
  final bool externalInput;
  final AssetStore? assets;
  @override
  State<PaperCanvas> createState() => _PaperCanvasState();
}

class _PaperCanvasState extends State<PaperCanvas> {
  int? pointer;
  final ink = DraftInk();
  final _images = <String, Future<Uint8List>>{};

  Widget storedImage(String assetId) {
    final assets = widget.assets;
    if (assets == null) {
      return const Center(child: Icon(Icons.broken_image_outlined));
    }
    return FutureBuilder<Uint8List>(
      future: _images.putIfAbsent(assetId, () => assets.read(assetId)),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Icon(Icons.broken_image_outlined));
        }
        if (!snapshot.hasData) return const SizedBox.shrink();
        return Image.memory(
          snapshot.data!,
          fit: BoxFit.fill,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) =>
              const Center(child: Icon(Icons.broken_image_outlined)),
        );
      },
    );
  }

  Widget pageBackground() => widget.page.background.isImage
      ? ColoredBox(
          color: Colors.white,
          child: storedImage(widget.page.background.assetId!),
        )
      : CustomPaint(
          painter: PaperBackgroundPainter(
            widget.page.background.pattern ?? PaperPattern.blank,
          ),
        );

  Widget pageObject(PageObject object) => Positioned(
    left: object.x,
    top: object.y,
    width: object.width,
    height: object.height,
    child: Transform.rotate(
      angle: object.rotation,
      child: ClipRect(
        child: object.kind == PageObjectKind.image
            ? storedImage(object.assetId!)
            : Text(
                object.text,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  color: Color(object.argb),
                  fontSize: object.fontSize,
                  height: 1.2,
                ),
              ),
      ),
    ),
  );
  InkPoint point(PointerEvent event) {
    final range = event.pressureMax - event.pressureMin;
    return InkPoint(
      x: event.localPosition.dx,
      y: event.localPosition.dy,
      pressure: (range > 0 ? (event.pressure - event.pressureMin) / range : 1.0)
          .clamp(0, 1),
    );
  }

  void down(PointerDownEvent event) {
    if (pointer != null ||
        (widget.tool != EditorTool.pen &&
            widget.tool != EditorTool.highlighter)) {
      return;
    }
    if (event.kind != PointerDeviceKind.stylus &&
        event.kind != PointerDeviceKind.invertedStylus &&
        !(event.kind == PointerDeviceKind.mouse &&
            event.buttons == kPrimaryButton)) {
      return;
    }
    pointer = event.pointer;
    ink.begin(
      point(event),
      tool: widget.tool == EditorTool.highlighter
          ? InkTool.highlighter
          : InkTool.pen,
      argb: widget.argb,
      width: widget.width,
      rasterBounds: Rect.fromLTWH(0, 0, widget.page.width, widget.page.height),
      rasterScale: MediaQuery.devicePixelRatioOf(context),
      pressureCurve: event.kind == PointerDeviceKind.mouse
          ? PressureCurve.uniform
          : PressureCurve.expressive,
    );
  }

  void move(PointerMoveEvent event) {
    if (pointer == event.pointer) ink.add(point(event));
  }

  void up(PointerUpEvent event) {
    if (pointer != event.pointer) return;
    pointer = null;
    final stroke = ink.finish(const Uuid().v4(), endpoint: point(event));
    if (stroke != null) widget.onStroke(stroke);
  }

  @override
  void didUpdateWidget(PaperCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assets != widget.assets) _images.clear();
    final used = {
      if (widget.page.background.isImage) widget.page.background.assetId!,
      for (final object in widget.page.objects)
        if (object.assetId != null) object.assetId!,
    };
    _images.removeWhere((id, _) => !used.contains(id));
    if (oldWidget.page.id != widget.page.id || oldWidget.tool != widget.tool) {
      pointer = null;
      ink.cancel();
    }
  }

  @override
  void dispose() {
    ink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.page.width,
    height: widget.page.height,
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: widget.externalInput ? null : down,
      onPointerMove: widget.externalInput ? null : move,
      onPointerUp: widget.externalInput ? null : up,
      onPointerCancel: widget.externalInput
          ? null
          : (event) {
              if (event.pointer == pointer) {
                pointer = null;
                ink.cancel();
              }
            },
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(child: widget.background ?? pageBackground()),
          if (widget.page.objects.isNotEmpty)
            RepaintBoundary(
              child: IgnorePointer(
                child: Stack(
                  children: widget.page.objects.map(pageObject).toList(),
                ),
              ),
            ),
          RepaintBoundary(
            child: CustomPaint(painter: InkPainter(widget.page.strokes)),
          ),
          if (!widget.externalInput)
            RepaintBoundary(child: CustomPaint(painter: DraftInkPainter(ink))),
        ],
      ),
    ),
  );
}

class InkPainter extends CustomPainter {
  InkPainter(this.strokes);
  final List<InkStroke> strokes;
  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      final alpha = stroke.tool == InkTool.highlighter
          ? 0x55
          : ((stroke.argb >> 24) & 0xff);
      canvas.drawPath(
        StrokeGeometry.canvasPath(stroke),
        Paint()..color = Color(stroke.argb).withAlpha(alpha),
      );
    }
  }

  @override
  bool shouldRepaint(InkPainter oldDelegate) =>
      !identical(strokes, oldDelegate.strokes);
}
