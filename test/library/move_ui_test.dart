import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/bootstrap.dart';
import 'package:apuntes/library/library_screen.dart';

void main() {
  testWidgets(
    'Mover a permite cambiar carpeta y conservar el apunte al reabrir',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late Directory root;
      late AppServices services;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('nala-move-ui-');
        services = await AppServices.open(root.path);
        await services.library.createFolder('Destino');
        await services.library.createNotebook(
          title: 'Clase importante',
          subject: 'Álgebra',
          pattern: PaperPattern.grid,
        );
      });
      await tester.pumpWidget(
        MaterialApp(home: LibraryScreen(services: services)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Opciones de apunte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mover a…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Destino').last);
      await tester.pumpAndSettle();
      final destination = services.library.folders.single.id;
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (services.library.entries.single.notebook.folderId != destination &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(services.library.entries.single.notebook.folderId, destination);
      await tester.pumpAndSettle();
      expect(find.text('Clase importante'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        final folderId = services.library.folders.single.id;
        await services.close();
        final reopened = await AppServices.open(root.path);
        expect(reopened.library.entries.single.notebook.folderId, folderId);
        expect(
          reopened.library.entries.single.notebook.title,
          'Clase importante',
        );
        await reopened.close();
        await root.delete(recursive: true);
      });
    },
  );
}
