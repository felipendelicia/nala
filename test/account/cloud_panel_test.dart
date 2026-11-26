import 'dart:io';
import 'package:apuntes/sync/sync_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/account/cloud_controller.dart';
import 'package:apuntes/account/cloud_panel.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('la configuración permite ingresar una credencial oculta', (
    tester,
  ) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('nala-cloud-ui-'),
    ))!;
    final cloud = (await tester.runAsync(
      () => CloudController.open(dir.path, autoStart: false),
    ))!;
    addTearDown(() async {
      await cloud.close();
      await dir.delete(recursive: true);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ServerSettingsTile(cloud: cloud)),
      ),
    );
    await tester.tap(find.widgetWithText(ListTile, 'Servidor privado'));
    await tester.pumpAndSettle();
    expect(find.text('Servidor de Nala'), findsOneWidget);
    expect(find.text('URL del servidor'), findsOneWidget);
    expect(find.text('Credencial del dispositivo'), findsOneWidget);
    expect(
      tester
          .widgetList<EditableText>(find.byType(EditableText))
          .where((input) => input.obscureText),
      hasLength(1),
    );
    expect(find.text('Verificar conexión'), findsOneWidget);
    expect(cloud.connected, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('una sesión revocada muestra por qué necesita reconexión', (
    tester,
  ) async {
    late Directory dir;
    final cloud = (await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('nala-cloud-ui-revoked-');
      final controller = await CloudController.open(
        dir.path,
        autoStart: false,
        clientFactory: () => MockClient((request) async {
          if (request.url.path == '/v1/identity') {
            return http.Response('{"id":"test-generation"}', 200);
          }
          return http.Response('{"error":"unauthorized"}', 401);
        }),
      );
      await controller.probe('https://nala.example.invalid', 'device-token');
      await controller.confirmConnection(remember: false);
      await controller.synchronize();
      return controller;
    }))!;
    addTearDown(() async {
      await cloud.close();
      await dir.delete(recursive: true);
    });

    expect(cloud.status.phase, SyncPhase.needsSignIn);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ServerSettingsTile(cloud: cloud)),
      ),
    );
    await tester.tap(find.widgetWithText(ListTile, 'Servidor privado'));
    await tester.pumpAndSettle();
    expect(find.text(cloud.status.message!), findsOneWidget);
    expect(find.text('Conectado por esta sesión.'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
