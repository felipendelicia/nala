import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/editor/editor_controller.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/editor/editor_toolbar.dart';
import 'package:apuntes/editor/paper_canvas.dart';
import 'package:apuntes/editor/draft_ink.dart';
import 'package:apuntes/editor/stroke_geometry.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/notebook_codec.dart';
import '../support/fixtures.dart';
import '../support/memory_repository.dart';

void main() {
  test(
    'la presión nueva es expresiva y la tinta antigua mantiene su ancho',
    () {
      final legacy = fixtureStroke();
      expect(StrokeGeometry.strokeWidth(legacy, 0), .7);
      final stroke = InkStroke(
        id: 'new',
        tool: InkTool.pen,
        argb: 0xff202020,
        width: 4,
        pressureCurve: PressureCurve.expressive,
        points: legacy.points,
      );
      expect(
        StrokeGeometry.strokeWidth(stroke, .8),
        greaterThan(StrokeGeometry.strokeWidth(stroke, .1) * 2),
      );
      expect(StrokeGeometry.strokeWidth(stroke, 0), closeTo(.6, .001));
      expect(StrokeGeometry.strokeWidth(stroke, 1), closeTo(6, .001));
      final note = fixtureNotebook().copyWith(
        pages: [
          fixtureNotebook().pages.first.copyWith(strokes: [legacy, stroke]),
        ],
      );
      final restored = NotebookCodec.decode(NotebookCodec.encode(note));
      expect(
        restored.pages.first.strokes.first.pressureCurve,
        PressureCurve.legacy,
      );
      expect(
        restored.pages.first.strokes.last.pressureCurve,
        PressureCurve.expressive,
      );
      expect(
        StrokeGeometry.bounds(restored.pages.first.strokes.last).width,
        greaterThan(20),
      );
    },
  );
  test('un trazo largo conserva la punta y cancelar no confirma tinta', () {
    final ink = DraftInk();
    ink.begin(
      const InkPoint(x: 0, y: 0, pressure: .1),
      tool: InkTool.pen,
      argb: 0xff202020,
      width: 2,
      stabilization: .15,
    );
    for (var i = 1; i <= 3000; i++) {
      ink.add(InkPoint(x: i.toDouble(), y: 10, pressure: .8));
    }
    final path = ink.path;
    final stroke = ink.finish(
      'long',
      endpoint: const InkPoint(x: 3000, y: 10, pressure: 0),
    );
    expect(stroke!.points.last.x, 3000);
    expect(stroke.points.last.pressure, closeTo(.8, .001));
    expect(stroke.points, hasLength(3002));
    expect(path.getBounds().right, greaterThan(3000));
    expect(ink.isEmpty, isTrue);
    ink.begin(
      const InkPoint(x: 1, y: 1, pressure: 1),
      tool: InkTool.highlighter,
      argb: 0xffffff00,
      width: 8,
    );
    ink.cancel();
    expect(ink.finish('cancelled'), isNull);
    ink.dispose();
  });
  testWidgets('las muestras del lápiz no reconstruyen hoja ni barra', (
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
    final center = tester.getCenter(find.byType(PaperCanvas));
    final pen = await tester.startGesture(
      center,
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    final paper = tester.widget<PaperCanvas>(find.byType(PaperCanvas));
    final toolbar = tester.widget<EditorToolbar>(find.byType(EditorToolbar));
    for (var i = 0; i < 20; i++) {
      await pen.moveBy(const Offset(2, 1));
      await tester.pump();
      expect(
        identical(tester.widget<PaperCanvas>(find.byType(PaperCanvas)), paper),
        isTrue,
        reason: 'El movimiento sólo debe repintar tinta activa.',
      );
      expect(
        identical(
          tester.widget<EditorToolbar>(find.byType(EditorToolbar)),
          toolbar,
        ),
        isTrue,
      );
    }
    expect(controller.notebook.pages.first.strokes, hasLength(1));
    await pen.up();
    await tester.pumpAndSettle();
    expect(controller.notebook.pages.first.strokes, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
