import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/editor/viewport.dart';

void main() {
  test('el zoom conserva la hoja bajo el ancla', () {
    final view = Viewport();
    view.pan(40, -20);
    final before = view.pagePoint(const Point(120.0, 80.0));
    view.zoom(2, const Point(120.0, 80.0));
    final after = view.pagePoint(const Point(120.0, 80.0));
    expect(after.x, closeTo(before.x, .0001));
    expect(after.y, closeTo(before.y, .0001));
    expect(view.pagePoint(const Point(200.0, 240.0)).y, 180);
  });
}
