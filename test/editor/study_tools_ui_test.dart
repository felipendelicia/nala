import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/page_object.dart';
import 'package:apuntes/editor/editor_controller.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/editor/paper_canvas.dart';
import '../support/fixtures.dart';
import '../support/memory_repository.dart';

Future<void> tapStudyTool(WidgetTester tester, String tooltip) async {
  final target = find.byTooltip(tooltip);
  if (target.evaluate().isEmpty) {
    await tester.tap(find.byTooltip('Más herramientas'));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  late EditorController controller;
  void createController({double? paperSize}) {
    var id = 0;
    final original = fixtureNotebook();
    controller = EditorController(
      notebook: paperSize == null
          ? original
          : original.copyWith(
              pages: [
                original.pages.single.copyWith(
                  width: paperSize,
                  height: paperSize,
                ),
              ],
            ),
      repository: MemoryRepository(),
      deviceId: 'test',
      newId: () => 'revision-${id++}',
      now: () => DateTime.utc(2026),
    );
  }

  tearDown(() => controller.dispose());
  Future<void> open(WidgetTester tester, {double? paperSize}) async {
    createController(paperSize: paperSize);
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: EditorScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('insert text, duplicate and undo persist through editor', (
    tester,
  ) async {
    await open(tester);
    await tapStudyTool(tester, 'Insertar texto');
    await tester.enterText(
      find.bySemanticsLabel('Texto'),
      'Límite y continuidad',
    );
    await tester.pump();
    await tester.tap(find.text('Insertar'));
    await tester.pumpAndSettle();
    expect(
      controller.notebook.pages.single.objects.single.text,
      'Límite y continuidad',
    );
    expect(
      controller.notebook.pages.single.objects.single.kind,
      PageObjectKind.text,
    );
    await tester.pump();
    expect(
      (tester.state(find.byType(EditorScreen)) as dynamic).selected,
      isNotEmpty,
    );
    await tapStudyTool(tester, 'Duplicar selección');
    expect(controller.notebook.pages.single.objects, hasLength(2));
    expect(
      controller.notebook.pages.single.objects.map((o) => o.id).toSet(),
      hasLength(2),
    );
    await tester.tap(find.byTooltip('Deshacer'));
    await tester.pumpAndSettle();
    expect(controller.notebook.pages.single.objects, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('explicit rectangle saves closed vector ink', (tester) async {
    await open(tester);
    await tapStudyTool(tester, 'Formas');
    await tester.tap(find.text('Rectángulo'));
    await tester.pumpAndSettle();
    final box = tester.renderObject<RenderBox>(find.byType(PaperCanvas));
    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.down(box.localToGlobal(const Offset(100, 100)));
    await pen.moveTo(box.localToGlobal(const Offset(220, 180)));
    await pen.up();
    await tester.pumpAndSettle();
    final points = controller.notebook.pages.single.strokes.last.points;
    expect(points, hasLength(5));
    expect(points.first.x, points.last.x);
    expect(points.first.y, points.last.y);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('compact editor keeps controls accessible without overflow', (
    tester,
  ) async {
    createController();
    await tester.binding.setSurfaceSize(const Size(400, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: EditorScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'text fits a small imported template without negative dimensions',
    (tester) async {
      await open(tester, paperSize: 32);
      await tapStudyTool(tester, 'Insertar texto');
      await tester.enterText(find.bySemanticsLabel('Texto'), 'x');
      await tester.pump();
      await tester.tap(find.text('Insertar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final object = controller.notebook.pages.single.objects.single;
      expect(object.width, greaterThan(0));
      expect(object.height, greaterThan(0));
      expect(object.x + object.width, lessThanOrEqualTo(32));
      expect(object.y + object.height, lessThanOrEqualTo(32));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('holding a line recognizes it despite stationary pen samples', (
    tester,
  ) async {
    await open(tester);
    final box = tester.renderObject<RenderBox>(find.byType(PaperCanvas));
    final pen = await tester.startGesture(
      box.localToGlobal(const Offset(100, 100)),
      kind: PointerDeviceKind.stylus,
    );
    await pen.moveTo(box.localToGlobal(const Offset(200, 100)));
    await pen.moveTo(box.localToGlobal(const Offset(300, 100)));
    for (var i = 0; i < 9; i++) {
      await pen.moveTo(box.localToGlobal(Offset(300 + (i % 2) * .5, 100.5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await pen.up();
    await tester.pumpAndSettle();
    expect(controller.notebook.pages.single.strokes.last.points, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
