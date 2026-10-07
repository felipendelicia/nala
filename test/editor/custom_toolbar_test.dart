import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/editor/editor_controller.dart';
import 'package:apuntes/editor/toolbar_preferences.dart';
import '../support/fixtures.dart';
import '../support/memory_repository.dart';

void main() {
  for (final dock in ToolbarDock.values) {
    testWidgets('custom toolbar remains accessible at ${dock.name}', (
      tester,
    ) async {
      final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('nala-custom-'),
      );
      final prefs = (await tester.runAsync(
        () => ToolbarPreferencesController.open(root!.path),
      ))!;
      await tester.runAsync(
        () => prefs.update(
          prefs.layout.copyWith(
            dock: dock,
            visible: {ToolbarAction.latex, ToolbarAction.pen},
          ),
        ),
      );
      final controller = EditorController(
        notebook: fixtureNotebook(),
        repository: MemoryRepository(),
        deviceId: 'test',
        newId: () => 'r',
        now: DateTime.now,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: EditorScreen(
            controller: controller,
            toolbarPreferences: prefs,
            storageRoot: root!.path,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Más herramientas'), findsOneWidget);
      expect(find.byTooltip('Deshacer'), findsNothing);
      final viewport = tester.getRect(
        find.byKey(const ValueKey('document-viewport')),
      );
      if (dock == ToolbarDock.top) {
        expect(viewport.top, lessThanOrEqualTo(112));
      } else {
        expect(viewport.top, lessThanOrEqualTo(56));
      }
      await tester.tap(find.byTooltip('Más herramientas'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Personalizar barra'), findsOneWidget);
      expect(find.byTooltip('Herramienta de escritura'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Cerrar herramientas'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Modo lectura'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Insertar fórmula LaTeX'), findsNothing);
      expect(
        tester.getRect(find.byKey(const ValueKey('document-viewport'))).top,
        lessThanOrEqualTo(56),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      prefs.dispose();
      await tester.runAsync(() => root.delete(recursive: true));
    });
  }
}
