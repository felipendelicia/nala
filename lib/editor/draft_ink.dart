import 'dart:collection';
import 'package:flutter/material.dart';
import '../document/notebook.dart';
import 'stroke_geometry.dart';

/// Only the live ink layer listens to this buffer; no widget rebuild per sample.
class DraftInk extends ChangeNotifier {
  final _points = <InkPoint>[];
  Path _path = Path();
  InkStroke? _style;
  double _stabilization = .08;
  Path get path => _path;
  List<InkPoint> get points => UnmodifiableListView(_points);
  bool get isEmpty => _points.isEmpty;
  Color get color {
    final style = _style;
    if (style == null) return Colors.transparent;
    return Color(style.argb).withAlpha(
      style.tool == InkTool.highlighter ? 0x55 : (style.argb >> 24) & 0xff,
    );
  }

  void begin(
    InkPoint point, {
    required InkTool tool,
    required int argb,
    required double width,
    PressureCurve pressureCurve = PressureCurve.expressive,
    double sensitivity = 1,
    double stabilization = .08,
  }) {
    _points.clear();
    _path = Path();
    _stabilization = stabilization.clamp(0, .4);
    _style = InkStroke(
      id: 'draft',
      tool: tool,
      argb: argb,
      width: width,
      points: [point],
      pressureCurve: tool == InkTool.highlighter
          ? PressureCurve.uniform
          : pressureCurve,
      sensitivity: sensitivity,
    );
    _append(point);
    notifyListeners();
  }

  void _append(InkPoint point) {
    final previous = _points.isEmpty ? null : _points.last;
    final r = StrokeGeometry.strokeWidth(_style!, point.pressure) / 2;
    _path.addOval(Rect.fromCircle(center: Offset(point.x, point.y), radius: r));
    if (previous != null) {
      final corners = StrokeGeometry.segmentCorners(
        previous,
        point,
        StrokeGeometry.strokeWidth(_style!, previous.pressure) / 2,
        r,
      );
      if (corners != null) _path.addPolygon(corners, true);
    }
    _points.add(point);
  }

  void add(InkPoint point) {
    if (isEmpty) return;
    final previous = _points.last;
    final raw = 1 - _stabilization;
    _append(
      InkPoint(
        x: previous.x * _stabilization + point.x * raw,
        y: previous.y * _stabilization + point.y * raw,
        pressure: previous.pressure * .25 + point.pressure * .75,
      ),
    );
    notifyListeners();
  }

  InkStroke? finish(String id, {InkPoint? endpoint}) {
    if (isEmpty) return null;
    if (endpoint != null &&
        (endpoint.x != _points.last.x || endpoint.y != _points.last.y)) {
      // Pointer-up often reports zero pressure. Preserve the last writing sample.
      _append(
        InkPoint(x: endpoint.x, y: endpoint.y, pressure: _points.last.pressure),
      );
    }
    final style = _style!;
    final stroke = InkStroke(
      id: id,
      tool: style.tool,
      argb: style.argb,
      width: style.width,
      points: _points,
      pressureCurve: style.pressureCurve,
      sensitivity: style.sensitivity,
    );
    cancel();
    return stroke;
  }

  void cancel() {
    _points.clear();
    _path = Path();
    _style = null;
    notifyListeners();
  }
}

class DraftInkPainter extends CustomPainter {
  DraftInkPainter(this.ink) : super(repaint: ink);
  final DraftInk ink;
  @override
  void paint(Canvas canvas, Size size) {
    if (!ink.isEmpty) canvas.drawPath(ink.path, Paint()..color = ink.color);
  }

  @override
  bool shouldRepaint(DraftInkPainter oldDelegate) =>
      !identical(ink, oldDelegate.ink);
}
