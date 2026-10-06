import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:apuntes/app.dart';
import 'package:apuntes/bootstrap.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('crear un cuaderno y reabrirlo conserva título y hoja', (
    tester,
  ) async {
    final dir = await Directory.systemTemp.createTemp('nala-flow-');
    var services = await AppServices.open(dir.path);
    await tester.pumpWidget(NalaApp(services: services));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crear cuaderno').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre del cuaderno'),
      'Análisis I',
    );
    await tester.tap(find.text('Crear').last);
    await tester.pumpAndSettle();
    expect(find.text('Análisis I'), findsOneWidget);
    await tester.tap(find.byTooltip('Volver a mis apuntes'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await services.close();
    services = await AppServices.open(dir.path);
    expect(
      (await services.library.repository.list()).single.notebook.title,
      'Análisis I',
    );
    await services.close();
    await dir.delete(recursive: true);
  });
}
