import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../document/notebook.dart';
import 'draft_ink.dart';

enum ShapeKind { line, rectangle, ellipse }

class ShapeTools {
  static InkStroke stroke(
    ShapeKind kind,
    Offset start,
    Offset end, {
    required String id,
    required int argb,
    required double width,
  }) {
    final r = Rect.fromPoints(start, end);
    final positions = switch (kind) {
      ShapeKind.line => [start, end],
      ShapeKind.rectangle => [
        r.topLeft,
        r.topRight,
        r.bottomRight,
        r.bottomLeft,
        r.topLeft,
      ],
      ShapeKind.ellipse => [
        for (var i = 0; i <= 64; i++)
          Offset(
            r.center.dx + r.width / 2 * math.cos(i * math.pi / 32),
            r.center.dy + r.height / 2 * math.sin(i * math.pi / 32),
          ),
      ],
    };
    return InkStroke(
      id: id,
      tool: InkTool.pen,
      argb: argb,
      width: width,
      pressureCurve: PressureCurve.uniform,
      points: positions
          .map((p) => InkPoint(x: p.dx, y: p.dy, pressure: 1))
          .toList(),
    );
  }

  static Offset project(Offset start, Offset point, double angleDegrees) {
    final angle = angleDegrees * math.pi / 180;
    final direction = Offset(math.cos(angle), math.sin(angle));
    final delta = point - start;
    return start +
        direction * (delta.dx * direction.dx + delta.dy * direction.dy);
  }

  /// Conservative recognition: ordinary handwriting remains untouched.
  static InkStroke? recognize(InkStroke source) {
    if (source.tool != InkTool.pen || source.points.length < 3) {
      return null;
    }
    final points = source.points.map((p) => Offset(p.x, p.y)).toList();
    final start = points.first, end = points.last;
    var length = 0.0;
    for (var i = 1; i < points.length; i++) {
      length += (points[i] - points[i - 1]).distance;
    }
    final delta = end - start;
    if (delta.distance >= 18 && length <= delta.distance * 1.15) {
      final error = points
          .map(
            (p) =>
                ((p.dx - start.dx) * delta.dy - (p.dy - start.dy) * delta.dx)
                    .abs() /
                delta.distance,
          )
          .reduce(math.max);
      if (error <= math.max(2, delta.distance * .025)) {
        return stroke(
          ShapeKind.line,
          start,
          end,
          id: source.id,
          argb: source.argb,
          width: source.width,
        );
      }
    }
    final bounds = points.fold(
      Rect.fromPoints(start, start),
      (Rect r, Offset p) => r.expandToInclude(Rect.fromPoints(p, p)),
    );
    if (bounds.shortestSide < 18 ||
        delta.distance > bounds.shortestSide * .25 ||
        points.length < 12) {
      return null;
    }
    var edgeError = 0.0, ellipseError = 0.0;
    for (final p in points) {
      edgeError +=
          math.min(
            math.min((p.dx - bounds.left).abs(), (p.dx - bounds.right).abs()),
            math.min((p.dy - bounds.top).abs(), (p.dy - bounds.bottom).abs()),
          ) /
          bounds.shortestSide;
      final nx = (p.dx - bounds.center.dx) / (bounds.width / 2);
      final ny = (p.dy - bounds.center.dy) / (bounds.height / 2);
      ellipseError += (math.sqrt(nx * nx + ny * ny) - 1).abs();
    }
    final kind = edgeError / points.length < .025
        ? ShapeKind.rectangle
        : ellipseError / points.length < .12
        ? ShapeKind.ellipse
        : null;
    return kind == null
        ? null
        : stroke(
            kind,
            bounds.topLeft,
            bounds.bottomRight,
            id: source.id,
            argb: source.argb,
            width: source.width,
          );
  }
}

class ShapePreviewPainter extends CustomPainter {
  ShapePreviewPainter(this.preview, {this.ink})
    : super(repaint: Listenable.merge([preview, ?ink]));
  final ValueNotifier<InkStroke?> preview;
  final DraftInk? ink;
  @override
  void paint(Canvas canvas, Size size) {
    final s = preview.value;
    if (s == null) {
      ink?.paint(canvas);
      return;
    }
    final path = Path()..moveTo(s.points.first.x, s.points.first.y);
    for (final p in s.points.skip(1)) {
      path.lineTo(p.x, p.y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Color(s.argb)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(ShapePreviewPainter old) =>
      old.preview != preview || old.ink != ink;
}

class RulerPainter extends CustomPainter {
  RulerPainter({required this.angle, required this.scale});
  final double angle, scale;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angle * math.pi / 180);
    final extent = size.longestSide;
    canvas.drawRect(
      Rect.fromLTRB(-extent, -12 / scale, extent, 0),
      Paint()..color = const Color(0x19284cad),
    );
    final line = Paint()
      ..color = const Color(0x99284cad)
      ..strokeWidth = 1 / scale;
    canvas.drawLine(Offset(-extent, 0), Offset(extent, 0), line);
    for (var x = -extent; x < extent; x += 10) {
      canvas.drawLine(Offset(x, 0), Offset(x, -6 / scale), line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(RulerPainter old) =>
      angle != old.angle || scale != old.scale;
}
