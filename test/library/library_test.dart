import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/deferred_notebook_page.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/notebook_repository.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/document/sqlite_notebook_repository.dart';
import 'package:apuntes/editor/editor_controller.dart';
import 'package:apuntes/library/library_controller.dart';

import '../support/fixtures.dart';
import '../support/memory_repository.dart';

class _OpeningRepository extends MemoryRepository
    implements NotebookCatalogRepository, EditableNotebookRepository {
  final previewResult = Completer<NotebookPage?>();
  final previewRequests = <(String, String)>[];
  final editRequests = <(String, String, int, String?)>[];

  @override
  Future<List<CatalogEntry>> listCatalog() async =>
      (await super.list()).map(CatalogEntry.fromDocument).toList();

  @override
  Future<NotebookPage?> loadPreview(
    String documentId, {
    required String headId,
  }) {
    previewRequests.add((documentId, headId));
    return previewResult.future;
  }

  @override
  Future<Notebook?> loadForEditing(
    String documentId, {
    required String headId,
    required int initialPageIndex,
    String? preparedPagePayload,
  }) async {
    editRequests.add((
      documentId,
      headId,
      initialPageIndex,
      preparedPagePayload,
    ));
    final notebook = await super.load(documentId, headId: headId);
    if (notebook == null || preparedPagePayload == null) return notebook;
    final page = notebook.pages.single;
    return notebook.copyWith(
      pages: [
        DeferredNotebookPage(
          id: page.id,
          width: page.width,
          height: page.height,
          background: page.background,
          encoded: jsonEncode(page.toJson()),
        ),
      ],
    );
  }
}

void main() {
  for (final fails in [false, true]) {
    test(
      fails
          ? 'abre la revisión exacta si falla su miniatura en curso'
          : 'reutiliza la miniatura en curso al abrir la primera página',
      () async {
        final repository = _OpeningRepository();
        final library = LibraryController(
          repository: repository,
          deviceId: 'tablet',
        );
        addTearDown(library.dispose);
        final notebook = fixtureNotebook();
        final document = await library.add(notebook);
        final entry = library.entries.single;
        final original = notebook.pages.single;
        final encoded = jsonEncode(original.toJson());
        final prepared = DeferredNotebookPage(
          id: original.id,
          width: original.width,
          height: original.height,
          background: original.background,
          encoded: encoded,
          decoded: original,
        );

        final preview = library.loadPreview(entry);
        final observedPreview = fails
            ? expectLater(preview, throwsStateError)
            : expectLater(preview, completion(same(prepared)));
        final opening = library.loadForEditing(entry, initialPageIndex: 0);
        await Future<void>.delayed(Duration.zero);
        final sentBeforePreview = List.of(repository.editRequests);

        if (fails) {
          repository.previewResult.completeError(
            StateError('No se pudo leer la miniatura.'),
          );
        } else {
          repository.previewResult.complete(prepared);
        }
        await observedPreview;
        final opened = await opening;

        expect(sentBeforePreview, isEmpty);
        expect(repository.previewRequests, [(notebook.id, document.headId)]);
        expect(repository.editRequests, [
          (notebook.id, document.headId, 0, fails ? null : encoded),
        ]);
        expect(opened?.headId, document.headId);
        final active = opened!.notebook.pages.single;
        if (!fails) expect((active as DeferredNotebookPage).isReady, isTrue);
        expect(active.strokes.single.id, original.strokes.single.id);
      },
    );
  }

  test(
    'crear, renombrar, deshacer y recuperar mantienen la escritura',
    () async {
      final dir = await Directory.systemTemp.createTemp('nala-library-');
      final repo = await SqliteNotebookRepository.open('${dir.path}/notes.db');
      addTearDown(() async {
        await repo.close();
        await dir.delete(recursive: true);
      });
      final library = LibraryController(repository: repo, deviceId: 'pc');
      final entry = await library.createNotebook(
        title: 'Álgebra',
        subject: 'Matemática',
        pattern: PaperPattern.dots,
      );
      var n = 0;
      final editor = EditorController(
        notebook: entry.notebook,
        repository: repo,
        deviceId: 'pc',
        newId: () => 'revision-${++n}',
        now: () => DateTime.utc(2026),
        headId: entry.headId,
      );
      await editor.apply((book) => book.copyWith(title: 'Álgebra II'));
      await editor.undo();
      await editor.flush();
      expect(editor.notebook.title, 'Álgebra');
      await editor.redo();
      await editor.flush();
      await library.refresh();
      expect(
        library.filtered(query: 'ALGEBRA', subject: 'Matemática').single.title,
        'Álgebra II',
      );
      expect(library.filtered(subject: 'Física'), isEmpty);
      expect(
        (await repo.load(entry.notebook.id))!.pages.single.background.pattern,
        PaperPattern.dots,
      );
      editor.dispose();
      library.dispose();
    },
  );
}
