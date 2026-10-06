import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/editor/paper_canvas.dart';
import '../support/fixtures.dart';

void main() {
  testWidgets('el lápiz confirma un trazo en coordenadas de hoja', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final result = <InkStroke>[];
    await tester.pumpWidget(MaterialApp(home: Align(alignment: Alignment.topLeft,
      child: PaperCanvas(page: fixtureNotebook().pages.single,
        tool: EditorTool.pen, onStroke: result.add))));
    final origin = tester.getTopLeft(find.byType(PaperCanvas));
    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.down(origin + const Offset(20, 30));
    await pen.moveTo(origin + const Offset(50, 70));
    await pen.up();
    expect(result.length, 1);
    expect(result.single.points.first.x, 20);
    expect(result.single.points.last.y, 70);
  });
  testWidgets('un dedo y un lápiz cancelado no dejan tinta', (tester) async {
    final result = <InkStroke>[];
    await tester.pumpWidget(MaterialApp(home: PaperCanvas(
      page: fixtureNotebook().pages.single, tool: EditorTool.pen, onStroke: result.add)));
    final origin = tester.getTopLeft(find.byType(PaperCanvas));
    final finger = await tester.createGesture(kind: PointerDeviceKind.touch);
    await finger.down(origin + const Offset(20, 20));
    await finger.moveTo(origin + const Offset(50, 50));
    await finger.up();
    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.down(origin + const Offset(20, 20));
    await pen.cancel();
    expect(result, isEmpty);
  });
}
