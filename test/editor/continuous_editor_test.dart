import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/editor/editor_controller.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/editor/editor_toolbar.dart';
import 'package:apuntes/editor/paper_canvas.dart';
import 'package:apuntes/editor/zoom_controls.dart';
import '../support/fixtures.dart';
import '../support/memory_repository.dart';

Future<EditorController> mount(WidgetTester tester, {int count = 3}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  var id = 0;
  final first = fixtureNotebook().pages.first;
  final controller = EditorController(
    notebook: fixtureNotebook().copyWith(
      pages: [
        first,
        for (var i = 1; i < count; i++)
          NotebookPage(
            id: 'p$i',
            width: first.width,
            height: first.height,
            background: const PageBackground.paper(PaperPattern.grid),
          ),
      ],
    ),
    repository: MemoryRepository(),
    deviceId: 'pc',
    newId: () => 'r${++id}',
    now: () => DateTime.utc(2026),
  );
  await tester.pumpWidget(
    MaterialApp(home: EditorScreen(controller: controller)),
  );
  await tester.pumpAndSettle();
  addTearDown(controller.dispose);
  return controller;
}

Finder canvas(String id) =>
    find.byWidgetPredicate((w) => w is PaperCanvas && w.page.id == id);

void main() {
  testWidgets('bajar encuentra la segunda hoja y escribe en sus coordenadas', (
    tester,
  ) async {
    final controller = await mount(tester);
    final center = tester.getCenter(canvas(controller.notebook.pages.first.id));
    final scale = tester.widget<ZoomControls>(find.byType(ZoomControls)).scale;
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, 650)),
    );
    await tester.pumpAndSettle();
    expect(canvas('p1'), findsOneWidget);
    expect(tester.widget<ZoomControls>(find.byType(ZoomControls)).scale, scale);
    final box = tester.renderObject<RenderBox>(canvas('p1'));
    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.down(box.localToGlobal(const Offset(100, 120)));
    await pen.moveTo(box.localToGlobal(const Offset(120, 130)));
    await pen.up();
    await tester.pumpAndSettle();
    expect(controller.notebook.pages.first.strokes, hasLength(1));
    expect(
      controller.notebook.pages[1].strokes.single.points.first.x,
      closeTo(100, .001),
    );
    expect(
      controller.notebook.pages[1].strokes.single.points.first.y,
      closeTo(120, .001),
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('bloquear X y zoom permite bajar y saltar sin mover X', (
    tester,
  ) async {
    final controller = await mount(tester);
    await tester.tap(find.byTooltip('Bloquear movimiento horizontal'));
    await tester.tap(find.byTooltip('Bloquear zoom'));
    await tester.pump();
    final first = canvas(controller.notebook.pages.first.id);
    final origin = tester.getTopLeft(first);
    final scale = tester.widget<ZoomControls>(find.byType(ZoomControls)).scale;
    final touch = await tester.startGesture(
      tester.getCenter(first),
      kind: PointerDeviceKind.touch,
    );
    await touch.moveBy(const Offset(90, -250));
    await touch.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(first).dx, origin.dx);
    expect(tester.getTopLeft(first).dy, closeTo(origin.dy - 250, .001));
    await tester.tap(find.byTooltip('Hoja siguiente'));
    await tester.pumpAndSettle();
    expect(canvas('p1'), findsOneWidget);
    expect(tester.getTopLeft(canvas('p1')).dx, origin.dx);
    expect(tester.widget<ZoomControls>(find.byType(ZoomControls)).scale, scale);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'resaltador ancho y ajustes independientes se guardan en trazos',
    (tester) async {
      final controller = await mount(tester, count: 1);
      await tester.tap(find.byTooltip('Resaltador'));
      await tester.pump();
      Future<void> draw() async {
        final pen = await tester.startGesture(
          tester.getCenter(find.byType(PaperCanvas)),
          kind: PointerDeviceKind.stylus,
        );
        await pen.moveBy(const Offset(10, 10));
        await pen.up();
        await tester.pumpAndSettle();
      }

      await draw();
      final highlighted = controller.notebook.pages.single.strokes.last;
      expect(highlighted.width, greaterThan(2.5 * 3));
      expect(highlighted.argb, 0xffe9ba3b);
      expect(highlighted.pressureCurve, PressureCurve.uniform);
      await tester.tap(find.byTooltip('Lápiz'));
      await tester.pump();
      await draw();
      final penned = controller.notebook.pages.single.strokes.last;
      expect(penned.width, 2.5);
      expect(penned.argb, 0xff202020);
      await tester.tap(find.byTooltip('Resaltador'));
      await tester.pump();
      expect(
        tester.widget<EditorToolbar>(find.byType(EditorToolbar)).width,
        highlighted.width,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('mil hojas no montan mil lienzos', (tester) async {
    await mount(tester, count: 1000);
    expect(
      tester.widgetList<PaperCanvas>(find.byType(PaperCanvas)).length,
      lessThan(5),
    );
    await tester.pumpWidget(const SizedBox());
  });
}
