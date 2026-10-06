import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:apuntes/app.dart';
import 'package:apuntes/bootstrap.dart';
import 'package:apuntes/editor/editor_screen.dart';

Future<void> until(WidgetTester tester, bool Function() ready) async {
  final timer = Stopwatch()..start();
  while (!ready()) {
    if (timer.elapsed > const Duration(seconds: 30))
      fail('No se completó la operación de biblioteca.');
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'la biblioteca crea carpetas anidadas y guarda el apunte en su ruta',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('nala-organize-');
      final services = await AppServices.open(root.path);
      await tester.pumpWidget(NalaApp(services: services));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nueva carpeta'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre de la carpeta'),
        'Universidad',
      );
      await tester.tap(find.text('Guardar'));
      await until(tester, () => services.library.folders.length == 1);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Universidad'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nueva carpeta'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre de la carpeta'),
        'Álgebra',
      );
      await tester.tap(find.text('Guardar'));
      await until(tester, () => services.library.folders.length == 2);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Álgebra'));
      await tester.pumpAndSettle();
      expect(services.library.breadcrumbs.map((f) => f.name), [
        'Universidad',
        'Álgebra',
      ]);
      await tester.tap(find.text('Crear cuaderno'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre del cuaderno'),
        'Clase 1',
      );
      await tester.tap(find.text('Crear').last);
      await until(
        tester,
        () => find.byType(EditorScreen).evaluate().isNotEmpty,
      );
      expect(
        services.library.entries.single.notebook.folderId,
        services.library.currentFolderId,
      );
      await tester.tap(find.byTooltip('Volver a mis apuntes'));
      await until(tester, () => find.byType(EditorScreen).evaluate().isEmpty);
      expect(find.text('Clase 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await services.close();
      await root.delete(recursive: true);
    },
  );
}
