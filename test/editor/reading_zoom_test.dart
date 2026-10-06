import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/editor/editor_controller.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/editor/paper_canvas.dart';
import 'package:apuntes/editor/zoom_controls.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/editor/viewport.dart' as paper;
import '../support/fixtures.dart';
import '../support/memory_repository.dart';

void main() {
  test('bloquear zoom conserva escala y permite desplazar', () {
    final view = paper.Viewport()
      ..setScale(1.5, const math.Point(100.0, 100.0));
    view.zoomLocked = true;
    view.zoom(2, const math.Point(100.0, 100.0));
    view.fit(800, 600, 595, 842);
    expect(view.scale, 1.5);
    final tx = view.tx;
    view.pan(30, 10);
    expect(view.tx, tx + 30);
    view.zoomLocked = false;
    view.fitWidth(800, 600, 400, 800);
    expect(view.scale, closeTo(1.88, .001));
  });
  testWidgets('leer navega con el lápiz y bloquea edición y atajos', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var id = 0;
    final controller = EditorController(
      notebook: fixtureNotebook().copyWith(
        pages: [
          fixtureNotebook().pages.first,
          NotebookPage(
            id: 'square',
            width: 300,
            height: 300,
            background: const PageBackground.paper(PaperPattern.blank),
          ),
        ],
      ),
      repository: MemoryRepository(),
      deviceId: 'pc',
      newId: () => 'r${++id}',
      now: () => DateTime.utc(2026),
    );
    await controller.apply((book) => book.copyWith(title: 'Estado de prueba'));
    await tester.pumpWidget(
      MaterialApp(home: EditorScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<ZoomControls>(find.byType(ZoomControls)).scale,
      closeTo(
        tester
            .renderObject<RenderBox>(find.byType(PaperCanvas))
            .getTransformTo(null)
            .getMaxScaleOnAxis(),
        .001,
      ),
    );
    await tester.tap(find.byTooltip('Modo lectura'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Lápiz'), findsNothing);
    final center = tester.getCenter(find.byType(PaperCanvas));
    final before = tester.getTopLeft(find.byType(PaperCanvas));
    final pen = await tester.startGesture(
      center,
      kind: PointerDeviceKind.stylus,
    );
    await pen.moveBy(const Offset(25, 15));
    await pen.up();
    await tester.pump();
    expect(
      tester.getTopLeft(find.byType(PaperCanvas)),
      before + const Offset(25, 15),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(controller.notebook.pages.first.strokes, hasLength(1));
    expect(controller.notebook.title, 'Estado de prueba');
    expect(controller.notebook.pages, hasLength(2));
    await tester.tap(find.byTooltip('Bloquear zoom'));
    await tester.pump();
    final lockedWidth = tester.getSize(find.byType(PaperCanvas)).width;
    final lockedOrigin = tester.getTopLeft(find.byType(PaperCanvas));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, -200)),
    );
    await tester.pump();
    expect(tester.getTopLeft(find.byType(PaperCanvas)), lockedOrigin);
    expect(tester.getSize(find.byType(PaperCanvas)).width, lockedWidth);
    final lockedScale = tester
        .widget<ZoomControls>(find.byType(ZoomControls))
        .scale;
    await tester.tap(find.byTooltip('Hoja siguiente'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ZoomControls>(find.byType(ZoomControls)).scale,
      lockedScale,
    );
    await tester.tap(find.byTooltip('Modo editor'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Lápiz'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
