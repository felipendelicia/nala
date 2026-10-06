import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/editor/editor_controller.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/editor/paper_canvas.dart';
import '../support/fixtures.dart';
import '../support/memory_repository.dart';

void main() {
  testWidgets('mover una selección conserva presión e ids', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var id = 0;
    final controller = EditorController(
      notebook: fixtureNotebook(),
      repository: MemoryRepository(),
      deviceId: 'pc',
      newId: () => 'r${++id}',
      now: () => DateTime.utc(2026),
    );
    await tester.pumpWidget(
      MaterialApp(home: EditorScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Selección'));
    await tester.pump();
    var box = tester.renderObject<RenderBox>(find.byType(PaperCanvas));
    var gesture = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await gesture.down(box.localToGlobal(const Offset(5, 10)));
    await gesture.moveTo(box.localToGlobal(const Offset(40, 50)));
    await gesture.up();
    await tester.pump();
    box = tester.renderObject<RenderBox>(find.byType(PaperCanvas));
    gesture = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await gesture.down(box.localToGlobal(const Offset(12, 23)));
    await gesture.moveTo(box.localToGlobal(const Offset(32, 38)));
    await gesture.up();
    await tester.pumpAndSettle();
    final stroke = controller.notebook.pages.single.strokes.single;
    expect(stroke.id, 'stroke-1');
    expect(stroke.points.first.x, closeTo(30, .001));
    expect(stroke.points.last.y, closeTo(55, .001));
    expect(stroke.points.last.pressure, .75);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
  testWidgets('cerrar la vista durante un trazo lo descarta', (tester) async {
    final controller = EditorController(
      notebook: fixtureNotebook(),
      repository: MemoryRepository(),
      deviceId: 'pc',
      newId: () => 'r1',
      now: () => DateTime.utc(2026),
    );
    await tester.pumpWidget(
      MaterialApp(home: EditorScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    final box = tester.renderObject<RenderBox>(find.byType(PaperCanvas));
    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.down(box.localToGlobal(const Offset(100, 100)));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
    expect(controller.notebook.pages.single.strokes.length, 1);
    controller.dispose();
  });
  testWidgets('borrar y deshacer desde el editor mantiene la hoja', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var id = 0;
    final controller = EditorController(
      notebook: fixtureNotebook(),
      repository: MemoryRepository(),
      deviceId: 'pc',
      newId: () => 'r${++id}',
      now: () => DateTime.utc(2026),
    );
    await tester.pumpWidget(
      MaterialApp(home: EditorScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Borrador'));
    await tester.pump();
    final box = tester.renderObject<RenderBox>(find.byType(PaperCanvas));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await gesture.down(box.localToGlobal(const Offset(20, 30)));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.notebook.pages.first.strokes, isEmpty);
    await tester.tap(find.byTooltip('Deshacer'));
    await tester.pumpAndSettle();
    expect(controller.notebook.pages.first.strokes.single.points.last.x, 30);
    await tester.tap(find.byTooltip('Agregar hoja'));
    await tester.pumpAndSettle();
    expect(controller.notebook.pages.length, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
