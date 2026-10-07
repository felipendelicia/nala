import 'dart:collection';
import 'package:flutter/material.dart';
import '../document/notebook.dart';
import 'stroke_geometry.dart';
import 'live_ink_raster.dart';

/// Only the live ink layer listens to this buffer; no widget rebuild per sample.
class DraftInk extends ChangeNotifier {
  final _points = <InkPoint>[];
  Path _path = Path();
  InkStroke? _style;
  double _stabilization = 0;
  LiveInkRaster? _raster;
  Rect? _rasterBounds;
  double _rasterScale = 1;
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
    double stabilization = 0,
    Rect? rasterBounds,
    double rasterScale = 1,
  }) {
    _raster?.dispose();
    _raster = null;
    _rasterBounds = rasterBounds;
    _rasterScale = rasterScale;
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
    final segment = Path()
      ..addOval(Rect.fromCircle(center: Offset(point.x, point.y), radius: r));
    if (previous != null) {
      final corners = StrokeGeometry.segmentCorners(
        previous,
        point,
        StrokeGeometry.strokeWidth(_style!, previous.pressure) / 2,
        r,
      );
      if (corners != null) segment.addPolygon(corners, true);
    }
    _path.addPath(segment, Offset.zero);
    if (_raster == null && _rasterBounds != null && _points.length == 95) {
      _raster = LiveInkRaster(bounds: _rasterBounds!, scale: _rasterScale)
        ..add(_path);
    } else {
      _raster?.add(segment);
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
        pressure: point.pressure,
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
    StrokeGeometry.rememberCanvasPath(stroke, _path);
    cancel();
    return stroke;
  }

  void paint(Canvas canvas) {
    if (isEmpty) return;
    if (_raster != null) {
      _raster!.paint(canvas, color);
    } else {
      canvas.drawPath(_path, Paint()..color = color);
    }
  }

  @override
  void dispose() {
    _raster?.dispose();
    super.dispose();
  }

  void cancel() {
    _raster?.dispose();
    _raster = null;
    _rasterBounds = null;
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
    ink.paint(canvas);
  }

  @override
  bool shouldRepaint(DraftInkPainter oldDelegate) =>
      !identical(ink, oldDelegate.ink);
}
