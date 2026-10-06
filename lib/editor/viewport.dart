import 'dart:math';
import 'package:vector_math/vector_math_64.dart';

class Viewport {
  double scale = 1, tx = 0, ty = 0;
  Point<double> pagePoint(Point<double> point) =>
      Point((point.x - tx) / scale, (point.y - ty) / scale);
  void pan(double dx, double dy) {
    tx += dx;
    ty += dy;
  }

  void zoom(double factor, Point<double> anchor) {
    final fixed = pagePoint(anchor);
    scale = (scale * factor).clamp(.25, 6.0);
    tx = anchor.x - fixed.x * scale;
    ty = anchor.y - fixed.y * scale;
  }

  Matrix4 get matrix =>
      Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(tx, ty, 0);
  void fit(
    double availableWidth,
    double availableHeight,
    double pageWidth,
    double pageHeight,
  ) {
    scale = min(
      (availableWidth - 48) / pageWidth,
      (availableHeight - 48) / pageHeight,
    ).clamp(.25, 2.0);
    tx = (availableWidth - pageWidth * scale) / 2;
    ty = (availableHeight - pageHeight * scale) / 2;
  }
}
