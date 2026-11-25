import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/deferred_notebook_page.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/editor/editor_controller.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/editor/editor_toolbar.dart';
import 'package:apuntes/editor/paper_canvas.dart';
import 'package:apuntes/editor/zoom_controls.dart';
import '../support/fixtures.dart';
import '../support/memory_repository.dart';

Future<EditorController> mount(
  WidgetTester tester, {
  int count = 3,
  List<NotebookPage>? pages,
  Size size = const Size(1200, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  var id = 0;
  final first = fixtureNotebook().pages.first;
  final controller = EditorController(
    notebook: fixtureNotebook().copyWith(
      pages:
          pages ??
          [
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

class _ControlledPage extends DeferredNotebookPage {
  _ControlledPage(NotebookPage page)
    : super(
        id: page.id,
        width: page.width,
        height: page.height,
        background: page.background,
        encoded: jsonEncode(page.toJson()),
      );

  var loading = Completer<void>();
  int loadAttempts = 0;

  @override
  Future<void> prepare() async {
    loadAttempts++;
    await loading.future;
    materialize();
  }
}

void main() {
  testWidgets('escribe en la primera hoja antes de cargar la vecina visible', (
    tester,
  ) async {
    final first = fixtureNotebook().pages.first;
    final secondSource = NotebookPage(
      id: 'deferred-second',
      width: first.width,
      height: first.height,
      background: first.background,
      strokes: [fixtureStroke(id: 'second-stroke')],
    );
    final second = _ControlledPage(secondSource);
    final controller = await mount(
      tester,
      pages: [first, second],
      size: const Size(600, 1100),
    );
    final viewport = find.byKey(const ValueKey('document-viewport'));
    final secondSheet = find.byKey(ValueKey('sheet-${second.id}'));
    expect(
      tester.getRect(viewport).contains(tester.getTopLeft(secondSheet)),
      isTrue,
    );
    expect(second.isReady, isFalse);
    expect(second.loadAttempts, 0);
    expect(canvas(second.id), findsNothing);

    final firstBox = tester.renderObject<RenderBox>(canvas(first.id));
    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.down(firstBox.localToGlobal(const Offset(100, 120)));
    await pen.moveTo(firstBox.localToGlobal(const Offset(120, 130)));
    await pen.up();
    await tester.pump();
    expect(controller.notebook.pages.first.strokes, hasLength(2));
    expect(second.isReady, isFalse);

    // Touching the pending sliver to write must request it without changing it.
    final pendingPen = await tester.createGesture(
      kind: PointerDeviceKind.stylus,
    );
    final sliver = tester.getTopLeft(secondSheet) + const Offset(40, 5);
    await pendingPen.down(sliver);
    await pendingPen.moveTo(sliver + const Offset(20, 5));
    await pendingPen.up();
    await tester.pump();
    expect(second.loadAttempts, 1);
    expect(second.isReady, isFalse);
    second.loading.complete();
    await tester.pumpAndSettle();
    expect(canvas(second.id), findsOneWidget);
    expect(second.strokes.single.id, 'second-stroke');

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(viewport),
        scrollDelta: const Offset(0, 660),
      ),
    );
    await tester.pump();
    final secondBox = tester.renderObject<RenderBox>(canvas(second.id));
    final nextPen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await nextPen.down(secondBox.localToGlobal(const Offset(100, 120)));
    await nextPen.moveTo(secondBox.localToGlobal(const Offset(120, 130)));
    await nextPen.up();
    await tester.pumpAndSettle();
    expect(controller.notebook.pages[1].strokes, hasLength(2));
    expect(
      controller.notebook.pages[1].strokes.last.points.first.x,
      closeTo(100, .001),
    );
    expect(
      controller.notebook.pages[1].strokes.last.points.first.y,
      closeTo(120, .001),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('la hoja pendiente permite navegar y reintentar la carga', (
    tester,
  ) async {
    final first = fixtureNotebook().pages.first;
    final second = _ControlledPage(
      NotebookPage(
        id: 'pending',
        width: first.width,
        height: first.height,
        background: first.background,
      ),
    );
    await mount(tester, pages: [first, second]);
    final viewport = find.byKey(const ValueKey('document-viewport'));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(viewport),
        scrollDelta: const Offset(0, 650),
      ),
    );
    await tester.pump();
    expect(find.text('Cargando hoja…'), findsOneWidget);
    final sheet = find.byKey(const ValueKey('sheet-pending'));
    final top = tester.getTopLeft(sheet).dy;
    await tester.dragFrom(tester.getCenter(viewport), const Offset(0, -60));
    await tester.pump();
    expect(tester.getTopLeft(sheet).dy, lessThan(top));
    expect(second.loadAttempts, 1);

    second.loading.completeError(const FormatException('fallo de prueba'));
    await tester.pumpAndSettle();
    expect(find.text('No se pudo cargar la hoja.'), findsOneWidget);
    expect(canvas(second.id), findsNothing);
    second.loading = Completer<void>();
    await tester.tap(find.widgetWithText(TextButton, 'Reintentar'));
    await tester.pump();
    expect(second.loadAttempts, 2);
    second.loading.complete();
    await tester.pumpAndSettle();
    expect(find.text('No se pudo cargar la hoja.'), findsNothing);
    expect(canvas(second.id), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

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
  testWidgets(
    'mezclar orientaciones y cruzar la separación conserva el origen del trazo',
    (tester) async {
      final first = fixtureNotebook().pages.first;
      final second = NotebookPage(
        id: 'landscape',
        width: 841.89,
        height: 595.28,
        background: const PageBackground.paper(PaperPattern.blank),
      );
      final controller = await mount(tester, pages: [first, second]);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(
            find.byKey(const ValueKey('document-viewport')),
          ),
          scrollDelta: const Offset(0, 350),
        ),
      );
      await tester.pumpAndSettle();
      final box = tester.renderObject<RenderBox>(canvas(first.id));
      final scale = tester
          .widget<ZoomControls>(find.byType(ZoomControls))
          .scale;
      final start = box.localToGlobal(Offset(120, first.height - 10));
      final pen = await tester.startGesture(
        start,
        kind: PointerDeviceKind.stylus,
      );
      await pen.moveBy(Offset(0, 80 * scale));
      await pen.up();
      await tester.pumpAndSettle();
      expect(controller.notebook.pages.first.strokes, hasLength(2));
      expect(controller.notebook.pages.last.strokes, isEmpty);
      final gap = box.localToGlobal(Offset(120, first.height + 16));
      final outside = await tester.startGesture(
        gap,
        kind: PointerDeviceKind.stylus,
      );
      await outside.up();
      await tester.pumpAndSettle();
      expect(controller.notebook.pages.first.strokes, hasLength(2));
      expect(controller.notebook.pages.last.strokes, isEmpty);
      final landscape = tester.renderObject<RenderBox>(canvas('landscape'));
      final next = await tester.startGesture(
        landscape.localToGlobal(const Offset(100, 130)),
        kind: PointerDeviceKind.stylus,
      );
      await next.moveBy(const Offset(20, 20));
      await next.up();
      await tester.pumpAndSettle();
      expect(
        controller.notebook.pages.last.strokes.single.points.first.x,
        closeTo(100, .001),
      );
      expect(
        controller.notebook.pages.last.strokes.single.points.first.y,
        closeTo(130, .001),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'deshacer y rehacer hojas mantiene una página visible y permite ajustar',
    (tester) async {
      final controller = await mount(tester, count: 1);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('Agregar hoja'));
        await tester.pumpAndSettle();
      }
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('Deshacer'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            '${controller.notebook.pages.length}/${controller.notebook.pages.length}',
          ),
          findsOneWidget,
        );
        expect(canvas(controller.notebook.pages.last.id), findsOneWidget);
        await tester.tap(find.byTooltip('Ajustar hoja'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Ajustar ancho'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byTooltip('Rehacer'));
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);
      final first = canvas(controller.notebook.pages.first.id);
      final origin = tester.getTopLeft(first);
      final pen = await tester.startGesture(
        tester
            .renderObject<RenderBox>(first)
            .localToGlobal(const Offset(100, 120)),
        kind: PointerDeviceKind.stylus,
      );
      await pen.moveBy(const Offset(20, 20));
      await pen.up();
      await tester.pumpAndSettle();
      expect(controller.notebook.pages.first.strokes, hasLength(2));
      await tester.tap(find.byTooltip('Deshacer'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(first), origin);
      await controller.apply(
        (book) => book.copyWith(
          pages: [
            NotebookPage(
              id: 'inserted',
              width: 841.89,
              height: 595.28,
              background: const PageBackground.paper(PaperPattern.blank),
            ),
            ...book.pages,
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2/3'), findsOneWidget);
      expect(tester.getTopLeft(first), origin);
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
