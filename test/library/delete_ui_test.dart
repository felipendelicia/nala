import 'package:apuntes/bootstrap.dart';
import 'package:apuntes/library/library_controller.dart';
import 'package:apuntes/library/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/memory_repository.dart';

void main() {
  testWidgets('Eliminar apunte requiere confirmación desde las opciones', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = MemoryRepository();
    final library = LibraryController(repository: repository, deviceId: 'pc');
    final services = AppServices(
      root: '/unused',
      deviceId: 'pc',
      repository: repository,
      assets: MemoryAssets(),
      library: library,
    );
    addTearDown(services.close);
    final notebook = fixtureNotebook();
    await library.add(notebook);
    await tester.pumpWidget(
      MaterialApp(home: LibraryScreen(services: services)),
    );
    await tester.pumpAndSettle();

    Future<void> confirmDialog() async {
      await tester.tap(find.byTooltip('Opciones de apunte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar apunte'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    }

    await confirmDialog();
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text(notebook.title), findsOneWidget);

    await confirmDialog();
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();
    expect(find.text(notebook.title), findsNothing);
    expect(library.entries, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
