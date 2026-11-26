import 'package:apuntes/editor/editor_controller.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/editor/editor_toolbar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/memory_repository.dart';

void main() {
  testWidgets('el S Pen desprende, mueve y vuelve a acoplar la barra', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(980, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = EditorController(
      notebook: fixtureNotebook(),
      repository: MemoryRepository(),
      deviceId: 'pc',
      newId: () => 'revision',
      now: () => DateTime.utc(2026),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: EditorScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    final toolbar = find.byType(EditorToolbar);
    final handle = find.byTooltip('Mover barra de herramientas');
    final dock = find.byTooltip('Acoplar barra');
    final original = tester.getRect(toolbar);
    final strokeCount = controller.notebook.pages.first.strokes.length;
    expect(handle, findsOneWidget);
    expect(dock, findsNothing);

    final start = tester.getCenter(handle);
    final stylus = await tester.startGesture(
      start,
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump(kLongPressTimeout);
    expect(dock, findsOneWidget);
    await stylus.moveTo(start + const Offset(210, 180));
    await tester.pump();
    final dragged = tester.getRect(toolbar);
    expect(dragged.left, greaterThan(original.left + 120));
    expect(dragged.top, greaterThan(original.top + 120));
    await stylus.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(toolbar), dragged);
    expect(controller.notebook.pages.first.strokes.length, strokeCount);

    await tester.binding.setSurfaceSize(const Size(420, 450));
    await tester.pumpAndSettle();
    final resized = tester.getRect(toolbar);
    expect(resized.left, greaterThanOrEqualTo(0));
    expect(resized.right, lessThanOrEqualTo(420));
    expect(resized.bottom, lessThanOrEqualTo(450));

    expect(dock, findsOneWidget);
    await tester.tap(find.byTooltip('Opciones del cuaderno'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acoplar barra de herramientas'));
    await tester.pumpAndSettle();
    expect(dock, findsNothing);
    expect(tester.getTopLeft(toolbar), original.topLeft);

    final mouseStart = tester.getCenter(handle);
    final mouse = await tester.startGesture(
      mouseStart,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(kLongPressTimeout);
    expect(dock, findsOneWidget);
    final firstMousePosition = tester.getTopLeft(toolbar);
    await mouse.moveTo(mouseStart + const Offset(24, 90));
    await tester.pump();
    expect(
      tester.getTopLeft(toolbar).dy,
      greaterThan(firstMousePosition.dy + 60),
    );
    await mouse.up();
    await tester.pumpAndSettle();
    await tester.tap(dock);
    await tester.pumpAndSettle();
    expect(dock, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
