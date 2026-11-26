import 'dart:io';

import 'package:apuntes/bootstrap.dart';
import 'package:apuntes/document/folders.dart';
import 'package:apuntes/document/sqlite_notebook_repository.dart';
import 'package:apuntes/library/library_controller.dart';
import 'package:apuntes/library/library_folder_tree.dart';
import 'package:apuntes/library/library_screen.dart';
import 'package:apuntes/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_repository.dart';

final _sidebar = find.byWidgetPredicate(
  (widget) => widget is Material && widget.color == nalaSidebar,
);

Finder _treeLabel(String label) =>
    find.descendant(of: _sidebar, matching: find.text(label));

Future<AppServices> _openLibrary(
  WidgetTester tester,
  List<NoteFolder> folders,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final services = (await tester.runAsync(() async {
    final root = await Directory.systemTemp.createTemp('nala-folder-tree-');
    addTearDown(() => root.delete(recursive: true));
    final repository = await SqliteNotebookRepository.open('${root.path}/db');
    final library = LibraryController(repository: repository, deviceId: 'pc');
    final services = AppServices(
      root: root.path,
      deviceId: 'pc',
      repository: repository,
      assets: MemoryAssets(),
      library: library,
    );
    addTearDown(services.close);
    for (final folder in folders) {
      await repository.saveFolder(folder);
    }
    await library.refresh();
    return services;
  }))!;
  await tester.pumpWidget(
    MaterialApp(
      theme: nalaTheme(
        brightness: Brightness.dark,
      ).copyWith(platform: TargetPlatform.linux),
      home: LibraryScreen(services: services),
    ),
  );
  await tester.pumpAndSettle();
  return services;
}

void main() {
  testWidgets('el árbol expande por rama y navega al tocar el nombre', (
    tester,
  ) async {
    final services = await _openLibrary(tester, [
      NoteFolder(id: 'uni', name: 'Universidad'),
      NoteFolder(id: 'math', name: 'Análisis', parentId: 'uni'),
      NoteFolder(id: 'work', name: 'Trabajo'),
      NoteFolder(id: 'meetings', name: 'Reuniones', parentId: 'work'),
    ]);

    expect(_treeLabel('Universidad'), findsOneWidget);
    expect(_treeLabel('Análisis'), findsNothing);
    expect(_treeLabel('Reuniones'), findsNothing);

    final expand = find.byTooltip('Expandir Universidad');
    expect(
      tester.getSemantics(expand),
      containsSemantics(
        hasTapAction: true,
        hasExpandedState: true,
        isExpanded: false,
      ),
    );
    await tester.tap(expand);
    await tester.pumpAndSettle();

    expect(services.library.currentFolderId, isNull);
    expect(
      tester.getSemantics(find.byTooltip('Contraer Universidad')),
      containsSemantics(
        hasTapAction: true,
        hasExpandedState: true,
        isExpanded: true,
      ),
    );
    expect(_treeLabel('Análisis'), findsOneWidget);
    expect(_treeLabel('Reuniones'), findsNothing);
    expect(
      tester.getTopLeft(_treeLabel('Análisis')).dx,
      greaterThan(tester.getTopLeft(_treeLabel('Universidad')).dx),
    );

    await tester.tap(_treeLabel('Análisis'));
    await tester.pumpAndSettle();
    expect(services.library.currentFolderId, 'math');

    await tester.tap(_treeLabel('Mis apuntes'));
    await tester.pumpAndSettle();
    expect(services.library.currentFolderId, isNull);
    expect(_treeLabel('Análisis'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('revela la carpeta activa cuando cambia su ruta', (tester) async {
    final unit = NoteFolder(id: 'unit', name: 'Unidad');
    final branch = NoteFolder(id: 'branch', name: 'Física', parentId: 'uni');
    final active = unit.copyWith(parentId: branch.id);
    final services = await _openLibrary(tester, [
      NoteFolder(id: 'uni', name: 'Universidad'),
      NoteFolder(id: 'archive', name: 'Archivo'),
      branch,
      active,
    ]);
    final library = services.library;

    library.openFolder(active.id);
    await tester.pumpAndSettle();
    expect(_treeLabel('Unidad'), findsOneWidget);

    await tester.tap(find.byTooltip('Contraer Universidad'));
    await tester.pumpAndSettle();
    expect(library.currentFolderId, active.id);
    expect(_treeLabel('Unidad'), findsNothing);

    await tester.runAsync(library.refresh);
    await tester.pumpAndSettle();
    expect(_treeLabel('Unidad'), findsNothing);

    await tester.runAsync(() => library.moveFolder(branch, 'archive'));
    await tester.pumpAndSettle();
    expect(library.currentFolderId, active.id);
    expect(find.byTooltip('Contraer Archivo'), findsOneWidget);
    expect(_treeLabel('Unidad'), findsOneWidget);

    await tester.runAsync(() async {
      await library.folderRepository!.deleteFolder(active.id);
      await library.refresh();
    });
    await tester.pumpAndSettle();
    expect(library.currentFolderId, isNull);
    expect(_treeLabel('Unidad'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('desplaza el árbol al nivel activo en una ventana baja', (
    tester,
  ) async {
    const longName = 'Una carpeta con un nombre largo que se muestra completo';
    final path = [
      for (var i = 0; i < 14; i++)
        NoteFolder(
          id: '$i',
          name: 'Nivel $i',
          parentId: i > 0 ? '${i - 1}' : null,
        ),
      NoteFolder(id: 'active', name: longName, parentId: '13'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 224,
            height: 348,
            child: LibraryFolderTree(
              folders: path,
              selectedPath: path,
              onNavigate: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final activeLabel = _treeLabel(longName).hitTestable();
    expect(activeLabel, findsOneWidget);
    expect(
      find.ancestor(of: activeLabel, matching: find.byTooltip(longName)),
      findsOneWidget,
    );
    expect(_treeLabel('Nivel 0').hitTestable(), findsNothing);

    await tester.drag(_sidebar, const Offset(0, 440));
    await tester.pumpAndSettle();
    expect(_treeLabel('Nivel 0').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
