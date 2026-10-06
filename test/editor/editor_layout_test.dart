import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/editor/editor_controller.dart';
import 'package:apuntes/editor/editor_screen.dart';
import '../support/fixtures.dart';
import '../support/memory_repository.dart';

void main() {
  for (final size in [
    const Size(1200, 800),
    const Size(800, 1200),
    const Size(1440, 900),
  ]) {
    testWidgets('editor con paneles y texto grande en $size', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var id = 0;
      final controller = EditorController(
        notebook: fixtureNotebook().copyWith(
          title:
              'Demostraciones y ejercicios de Álgebra lineal — Segundo cuatrimestre',
        ),
        repository: MemoryRepository(),
        deviceId: 'pc',
        newId: () => 'r${++id}',
        now: () => DateTime.utc(2026),
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: EditorScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Páginas'));
      await tester.tap(find.byTooltip('Comentarios'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Lápiz'), findsOneWidget);
      expect(find.text('Agregar comentario'), findsOneWidget);
      await tester.tap(find.byTooltip('Bloquear zoom'));
      await tester.tap(find.byTooltip('Modo lectura'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Desbloquear zoom'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  }
}
