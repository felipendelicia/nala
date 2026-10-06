import 'dart:math';
import 'package:vector_math/vector_math_64.dart';

class Viewport {
  double scale = 1, tx = 0, ty = 0;
  bool zoomLocked = false;
  Point<double> pagePoint(Point<double> point) =>
      Point((point.x - tx) / scale, (point.y - ty) / scale);
  void pan(double dx, double dy) {
    tx += dx;
    ty += dy;
  }

  void zoom(double factor, Point<double> anchor) {
    if (zoomLocked) return;
    final fixed = pagePoint(anchor);
    scale = (scale * factor).clamp(.25, 6.0);
    tx = anchor.x - fixed.x * scale;
    ty = anchor.y - fixed.y * scale;
  }

  void setScale(double value, Point<double> anchor) =>
      zoom(value / scale, anchor);
  void fitWidth(
    double availableWidth,
    double availableHeight,
    double pageWidth,
    double pageHeight,
  ) {
    if (zoomLocked) return;
    scale = ((availableWidth - 48) / pageWidth).clamp(.25, 6.0);
    tx = (availableWidth - pageWidth * scale) / 2;
    ty = pageHeight * scale < availableHeight
        ? (availableHeight - pageHeight * scale) / 2
        : 24;
  }

  Matrix4 get matrix =>
      Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(tx, ty, 0);
  void fit(
    double availableWidth,
    double availableHeight,
    double pageWidth,
    double pageHeight,
  ) {
    if (zoomLocked) return;
    scale = min(
      (availableWidth - 48) / pageWidth,
      (availableHeight - 48) / pageHeight,
    ).clamp(.25, 2.0);
    tx = (availableWidth - pageWidth * scale) / 2;
    ty = (availableHeight - pageHeight * scale) / 2;
  }
}
