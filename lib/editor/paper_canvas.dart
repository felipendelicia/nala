import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:uuid/uuid.dart';
import '../document/notebook.dart';
import 'paper_background.dart';

class PaperCanvas extends StatefulWidget {
  const PaperCanvas({
    super.key,
    required this.page,
    required this.onStroke,
    required this.tool,
    this.argb = 0xff202020,
    this.width = 2,
  });
  final NotebookPage page;
  final ValueChanged<InkStroke> onStroke;
  final EditorTool tool;
  final int argb;
  final double width;
  @override
  State<PaperCanvas> createState() => _PaperCanvasState();
}

class _PaperCanvasState extends State<PaperCanvas> {
  int? pointer;
  List<InkPoint> points = [];
  InkPoint point(PointerEvent event) {
    final range = event.pressureMax - event.pressureMin;
    final pressure = range > 0
        ? (event.pressure - event.pressureMin) / range
        : 1.0;
    return InkPoint(
      x: event.localPosition.dx,
      y: event.localPosition.dy,
      pressure: pressure.clamp(0, 1),
    );
  }

  void down(PointerDownEvent event) {
    if (pointer != null ||
        (widget.tool != EditorTool.pen &&
            widget.tool != EditorTool.highlighter))
      return;
    if (event.kind != PointerDeviceKind.stylus &&
        event.kind != PointerDeviceKind.invertedStylus &&
        !(event.kind == PointerDeviceKind.mouse &&
            event.buttons == kPrimaryButton))
      return;
    setState(() {
      pointer = event.pointer;
      points = [point(event)];
    });
  }

  void move(PointerMoveEvent event) {
    if (pointer != event.pointer) return;
    setState(() => points = [...points, point(event)]);
  }

  void up(PointerUpEvent event) {
    if (pointer != event.pointer) return;
    final stroke = InkStroke(
      id: const Uuid().v4(),
      tool: widget.tool == EditorTool.highlighter
          ? InkTool.highlighter
          : InkTool.pen,
      argb: widget.argb,
      width: widget.width,
      points: points,
    );
    setState(() {
      pointer = null;
      points = [];
    });
    widget.onStroke(stroke);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.page.width,
    height: widget.page.height,
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: down,
      onPointerMove: move,
      onPointerUp: up,
      onPointerCancel: (event) {
        if (event.pointer == pointer)
          setState(() {
            pointer = null;
            points = [];
          });
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: PaperBackgroundPainter(
                widget.page.background.pattern ?? PaperPattern.blank,
              ),
            ),
          ),
          RepaintBoundary(
            child: CustomPaint(painter: InkPainter(widget.page.strokes)),
          ),
          CustomPaint(
            painter: InkPainter(
              points.isEmpty
                  ? []
                  : [
                      InkStroke(
                        id: 'draft',
                        tool: widget.tool == EditorTool.highlighter
                            ? InkTool.highlighter
                            : InkTool.pen,
                        argb: widget.argb,
                        width: widget.width,
                        points: points,
                      ),
                    ],
            ),
          ),
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
      final paint = Paint()
        ..color = Color(stroke.argb).withAlpha(255)
        ..strokeCap = StrokeCap.round;
      if (stroke.tool == InkTool.highlighter)
        canvas.saveLayer(
          Offset.zero & size,
          Paint()..color = const Color(0x55ffffff),
        );
      for (var i = 0; i < stroke.points.length; i++) {
        final p = stroke.points[i];
        paint.strokeWidth = stroke.width * (.35 + .65 * p.pressure);
        canvas.drawCircle(Offset(p.x, p.y), paint.strokeWidth / 2, paint);
        if (i > 0) {
          final previous = stroke.points[i - 1];
          canvas.drawLine(
            Offset(previous.x, previous.y),
            Offset(p.x, p.y),
            paint,
          );
        }
      }
      if (stroke.tool == InkTool.highlighter) canvas.restore();
    }
  }

  @override
  bool shouldRepaint(InkPainter oldDelegate) =>
      !identical(strokes, oldDelegate.strokes);
}
