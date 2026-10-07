import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/bootstrap.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/library/library_screen.dart';
import 'package:apuntes/ui/app_theme.dart';

void main() {
  testWidgets(
    'nombres largos con texto grande mantienen búsqueda y mover accesibles',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late Directory root;
      late AppServices services;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('nala-long-library-');
        services = await AppServices.open(root.path);
        final folder = await services.library.createFolder(
          'Álgebra avanzada: demostraciones y problemas del primer cuatrimestre 2026',
        );
        services.library.openFolder(folder.id);
        await services.library.createNotebook(
          title:
              'Demostraciones de clase y ejercicios complementarios de álgebra avanzada',
          subject:
              'Análisis matemático: primer cuatrimestre, ejercicios y demostraciones',
          pattern: PaperPattern.grid,
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: nalaTheme(brightness: Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: LibraryScreen(services: services),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byTooltip('Opciones de apunte'));
      await tester.tap(find.byTooltip('Opciones de apunte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mover a…'));
      await tester.pumpAndSettle();
      expect(find.text('Mis apuntes').last, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(
        services.library.entries.single.notebook.folderId,
        services.library.currentFolderId,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await services.close();
        await root.delete(recursive: true);
      });
    },
  );
}
