import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/account/cloud_controller.dart';
import 'package:apuntes/account/cloud_panel.dart';

void main() {
  testWidgets(
    'Drive sin OAuth explica la configuración y no muestra conexión falsa',
    (tester) async {
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('nala-cloud-ui-'),
      ))!;
      final cloud = (await tester.runAsync(
        () => CloudController.open(dir.path, autoStart: false),
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CloudControls(cloud: cloud)),
        ),
      );
      await tester.tap(find.byTooltip('Google Drive'));
      await tester.pumpAndSettle();
      expect(find.text('Google Drive'), findsOneWidget);
      expect(find.textContaining('necesita configurar'), findsOneWidget);
      expect(find.text('Conectar con Google'), findsNothing);
      expect(cloud.connected, isFalse);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await cloud.close();
        await dir.delete(recursive: true);
      });
    },
  );
}
