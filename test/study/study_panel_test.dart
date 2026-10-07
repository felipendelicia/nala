import 'package:apuntes/editor/editor_controller.dart';
import 'package:apuntes/study/study_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/memory_repository.dart';

void main() {
  testWidgets('create from selected text, reveal and grade saves the card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = MemoryRepository();
    var id = 0;
    final controller = EditorController(
      notebook: fixtureNotebook(),
      repository: repository,
      deviceId: 'test',
      newId: () => 'id-${id++}',
      now: () => DateTime.utc(2026, 10, 7, 12),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudyPanel(
            controller: controller,
            initialFront: '¿Qué es una matriz?',
          ),
        ),
      ),
    );
    await tester.tap(find.text('Nueva tarjeta'));
    await tester.pumpAndSettle();
    expect(find.text('¿Qué es una matriz?'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Respuesta'),
      'Una tabla de números.',
    );
    await tester.tap(find.text('Guardar tarjeta'));
    await tester.pumpAndSettle();
    expect(controller.notebook.studyCards, hasLength(1));
    await tester.tap(find.text('Repasar pendientes'));
    await tester.pumpAndSettle();
    expect(find.text('Una tabla de números.'), findsNothing);
    await tester.tap(find.text('Mostrar respuesta'));
    await tester.pumpAndSettle();
    expect(find.text('Una tabla de números.'), findsOneWidget);
    await tester.tap(find.text('Bien'));
    await tester.pumpAndSettle();
    final saved = (await repository.load(controller.notebook.id))!;
    expect(saved.studyCards.single.dueAt, DateTime.utc(2026, 10, 9, 12));
    expect(find.text('No hay tarjetas pendientes.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
