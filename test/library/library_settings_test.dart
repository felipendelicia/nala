import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:apuntes/account/cloud_controller.dart';
import 'package:apuntes/ai/chat_gpt_client.dart';
import 'package:apuntes/backup/backup_dialog.dart';
import 'package:apuntes/backup/backup_files.dart';
import 'package:apuntes/backup/backup_service.dart';
import 'package:apuntes/bootstrap.dart';
import 'package:apuntes/document/asset_store.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/library/library_controller.dart';
import 'package:apuntes/library/library_screen.dart';
import 'package:apuntes/library/library_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_repository.dart';

class _BackupFiles implements BackupFiles {
  const _BackupFiles(this.bytes);
  final Uint8List bytes;

  @override
  Future<SelectedBackup?> open() async =>
      SelectedBackup(bytes: bytes, name: 'Parcial.nala.zip');

  @override
  Future<bool> save(Uint8List bytes, {required String name}) async => false;
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 150; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsOneWidget);
}

void main() {
  testWidgets('Ajustes muestra la versión instalada junto a Actualizaciones', (
    tester,
  ) async {
    final repository = MemoryRepository();
    final chatGpt = ChatGptClient();
    addTearDown(chatGpt.dispose);
    final services = AppServices(
      root: '/unused',
      deviceId: 'pc',
      repository: repository,
      assets: MemoryAssets(),
      library: LibraryController(repository: repository, deviceId: 'pc'),
      chatGpt: chatGpt,
    );
    addTearDown(services.close);
    final version = Completer<String>();

    await tester.pumpWidget(
      MaterialApp(
        home: LibrarySettingsScreen(
          services: services,
          readInstalledVersion: () => version.future,
        ),
      ),
    );
    final tile = find.widgetWithText(ListTile, 'Buscar actualizaciones');
    expect(tile, findsOneWidget);
    version.complete('0.7.42');
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: tile,
        matching: find.text('Versión instalada 0.7.42'),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Ajustes abre el backup y el servidor desde la biblioteca', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late Directory root;
    late Uint8List backupBytes;
    final cloud = (await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('nala-library-settings-');
      final cloud = await CloudController.open(root.path, autoStart: false);
      final services = cloud.services;
      await services.library.createNotebook(
        title: 'Parcial de álgebra',
        pattern: PaperPattern.grid,
      );
      backupBytes = await BackupService(
        root: root.path,
        repository: services.repository,
        assets: services.assets,
        deviceId: services.deviceId,
      ).export();
      return cloud;
    }))!;
    addTearDown(() async {
      await cloud.close();
      await root.delete(recursive: true);
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: LibraryScreen(
          services: cloud.services,
          cloud: cloud,
          backupFiles: _BackupFiles(backupBytes),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final settings = find.byTooltip('Ajustes');
    expect(settings, findsOneWidget);
    expect(find.byTooltip('Apariencia'), findsNothing);
    expect(find.byTooltip('Servidor de Nala'), findsNothing);
    expect(find.byTooltip('Más opciones de la biblioteca'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Parcial');
    await tester.tap(settings);
    await tester.pumpAndSettle();

    final title = find.widgetWithText(AppBar, 'Ajustes');
    expect(title, findsOneWidget);
    expect(find.text('Apariencia'), findsOneWidget);
    expect(find.text('Buscar actualizaciones'), findsOneWidget);
    await tester.tap(find.text('ChatGPT'));
    final continueWithChatGpt = find.ancestor(
      of: find.text('Continuar con ChatGPT'),
      matching: find.byWidgetPredicate(
        (widget) => widget is FilledButton && widget.enabled,
      ),
    );
    await _waitFor(tester, continueWithChatGpt);
    await tester.pumpAndSettle();
    expect(find.text('Conectar tu plan de ChatGPT'), findsOneWidget);
    expect(continueWithChatGpt, findsOneWidget);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Backup de la biblioteca'));
    await tester.pumpAndSettle();
    final backup = find.byType(BackupDialog);
    expect(backup, findsOneWidget);
    expect(find.text('Guardar backup'), findsOneWidget);
    expect(find.text('Abrir backup'), findsOneWidget);
    await tester.tap(
      find.descendant(of: backup, matching: find.text('Cerrar')),
    );
    await tester.pumpAndSettle();
    expect(title, findsOneWidget);

    await tester.tap(find.text('Servidor privado'));
    await tester.pumpAndSettle();
    expect(find.text('Servidor de Nala'), findsOneWidget);
    expect(find.text('URL del servidor'), findsOneWidget);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(title, findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(title, findsNothing);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'Parcial',
    );
    expect(find.text('Parcial de álgebra'), findsOneWidget);

    await tester.tap(settings);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Backup de la biblioteca'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir backup'));
    final restore = find.text('Recuperar copias');
    await _waitFor(tester, restore);
    await tester.tap(restore);
    final openFolder = find.text('Abrir carpeta recuperada');
    await _waitFor(tester, openFolder);
    await tester.tap(openFolder);
    await tester.pumpAndSettle();
    expect(title, findsNothing);
    expect(
      cloud.services.library.breadcrumbs.single.name,
      startsWith('Recuperado '),
    );
    expect(find.text('Parcial de álgebra'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
