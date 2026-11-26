import 'package:apuntes/bootstrap.dart';
import 'package:apuntes/document/folders.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/library/library_controller.dart';
import 'package:apuntes/library/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_repository.dart';

class _Folders implements FolderRepository {
  _Folders(this.folder);

  final NoteFolder folder;

  @override
  Future<List<NoteFolder>> listFolders({bool includeDeleted = false}) async => [
    folder,
  ];

  @override
  Future<void> saveFolder(NoteFolder folder) => throw UnimplementedError();

  @override
  Future<void> deleteFolder(String id) => throw UnimplementedError();

  @override
  Future<bool> mergeFolders(List<NoteFolder> folders) =>
      throw UnimplementedError();
}

void main() {
  testWidgets('Mis apuntes permite reabrir un reciente de otra carpeta', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.utc(2026);
    final folder = NoteFolder(id: 'folder', name: 'Carpeta de prueba');
    final notebook = Notebook.blank(
      id: 'note',
      pageId: 'page',
      title: 'Apunte en carpeta',
      pattern: PaperPattern.blank,
      now: now,
    ).copyWith(folderId: folder.id);
    final repository = MemoryRepository();
    await repository.commit(
      Revision(
        id: 'head',
        deviceId: 'test',
        parentId: null,
        createdAt: now,
        notebook: notebook,
      ),
    );
    final library = LibraryController(
      repository: repository,
      deviceId: 'test',
      folders: _Folders(folder),
    );
    final services = AppServices(
      root: '/unused',
      deviceId: 'test',
      repository: repository,
      assets: MemoryAssets(),
      library: library,
    );
    addTearDown(services.close);
    await library.refresh();
    library.openFolder(folder.id);

    await tester.pumpWidget(
      MaterialApp(home: LibraryScreen(services: services)),
    );
    expect(find.text('Recientes'), findsNothing);
    await tester.tap(find.text(notebook.title));
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsOneWidget);
    expect(services.recentNotes.entries.single.documentId, notebook.id);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(LibraryScreen), findsOneWidget);
    await tester.tap(find.text('Mis apuntes'));
    await tester.pumpAndSettle();
    expect(find.text('Recientes'), findsOneWidget);
    expect(find.text(notebook.title), findsOneWidget);

    await tester.tap(find.text(notebook.title));
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
