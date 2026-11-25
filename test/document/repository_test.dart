import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/notebook_codec.dart';
import 'package:apuntes/document/sqlite_notebook_repository.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/document/asset_store.dart';
import '../support/fixtures.dart';

void main() {
  late Directory dir;
  late SqliteNotebookRepository repo;
  String getPath() => '${dir.path}/notes.db';
  Revision revision(String id, String? parent, {String? title}) => Revision(
    id: id,
    deviceId: 'tablet',
    parentId: parent,
    createdAt: DateTime.utc(2026),
    notebook: fixtureNotebook().copyWith(title: title),
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('nala-repo-');
    repo = await SqliteNotebookRepository.open(getPath());
  });
  tearDown(() async {
    await repo.close();
    await dir.delete(recursive: true);
  });
  test('un cierre conserva el cuaderno y el pendiente', () async {
    await repo.commit(revision('r1', null));
    await repo.close();
    repo = await SqliteNotebookRepository.open(getPath());
    expect(
      (await repo.load('doc-1'))!.pages.single.strokes.single.points.last.x,
      30,
    );
    expect((await repo.pending()).single.id, 'r1');
  });
  test('actualiza el índice de cabeceras de una base existente', () async {
    await repo.acceptRemote(revision('r1', null));
    await repo.acceptRemote(revision('r2', 'r1'));
    await repo.close();

    final before = sqlite3.open(getPath());
    before.execute('DROP INDEX IF EXISTS revisions_parent_document');
    before.close();

    repo = await SqliteNotebookRepository.open(getPath());
    expect((await repo.list()).single.headId, 'r2');
    final after = sqlite3.open(getPath());
    addTearDown(after.close);
    final plan = after.select(
      'EXPLAIN QUERY PLAN SELECT r.payload FROM revisions r WHERE NOT EXISTS '
      '(SELECT 1 FROM revisions c WHERE c.parent_id=r.id AND c.document_id=r.document_id)',
    );
    expect(
      plan.map((row) => row['detail'] as String),
      contains(contains('COVERING INDEX revisions_parent_document')),
    );
  });
  test('releer el catálogo conserva los cuadernos que no cambiaron', () async {
    final original = revision('a1', null);
    final other = Revision(
      id: 'b1',
      parentId: null,
      deviceId: original.deviceId,
      createdAt: original.createdAt,
      notebook: fixtureNotebook(id: 'second'),
    );
    await repo.acceptRemote(original);
    await repo.acceptRemote(other);

    final initial = {
      for (final entry in await repo.list()) entry.headId: entry,
    };
    final repeat = {for (final entry in await repo.list()) entry.headId: entry};
    expect(repeat['a1']!.notebook, same(initial['a1']!.notebook));
    expect(repeat['b1']!.notebook, same(initial['b1']!.notebook));

    await repo.acceptRemote(revision('a2', 'a1', title: 'Revisión nueva'));
    final updated = {
      for (final entry in await repo.list()) entry.headId: entry,
    };
    expect(updated.keys, unorderedEquals(['a2', 'b1']));
    expect(updated['a2']!.notebook.title, 'Revisión nueva');
    expect(updated['b1']!.notebook, same(initial['b1']!.notebook));

    await repo.acceptRemote(revision(Revision.deletionId('deleted'), 'a2'));
    final afterDeletion = (await repo.list()).single;
    expect(afterDeletion.headId, 'b1');
    expect(afterDeletion.notebook, same(initial['b1']!.notebook));
  });
  test('el catálogo vuelve a leer tras un cambio en otra conexión', () async {
    await repo.acceptRemote(revision('head', null));
    expect((await repo.list()).single.notebook.title, 'Álgebra');

    final sql = sqlite3.open(getPath());
    try {
      sql.execute('UPDATE revisions SET payload=? WHERE id=?', [
        NotebookCodec.encodeRevision(
          revision('head', null, title: 'Biblioteca reemplazada'),
        ),
        'head',
      ]);
    } finally {
      sql.close();
    }

    expect((await repo.list()).single.notebook.title, 'Biblioteca reemplazada');
  });
  test('proyecta los metadatos de la versión y la primera página', () async {
    final cover = 'a' * 64;
    final background = 'b' * 64;
    final date = DateTime.utc(2026, 11, 1, 2, 3, 4, 5, 6);
    final page = fixtureNotebook().pages.single;
    final book = fixtureNotebook().copyWith(
      title: 'Funciones y límites',
      subject: 'Análisis',
      updatedAt: date,
      folderId: 'materias',
      coverAssetId: cover,
      pages: [
        page.copyWith(
          width: 400,
          height: 500.25,
          background: PageBackground.pdf(background, 2),
        ),
        NotebookPage(
          id: 'page-2',
          width: 1200,
          height: 900,
          background: const PageBackground.paper(PaperPattern.dots),
        ),
      ],
    );
    await repo.acceptRemote(
      Revision(
        id: 'pdf',
        deviceId: 'pc',
        parentId: null,
        createdAt: date,
        notebook: book,
      ),
    );

    final entry = (await repo.listCatalog()).single;
    expect(entry.documentId, 'doc-1');
    expect(entry.title, 'Funciones y límites');
    expect(entry.subject, 'Análisis');
    expect(entry.updatedAt, date);
    expect(entry.folderId, 'materias');
    expect(entry.headId, 'pdf');
    expect(entry.deviceId, 'pc');
    expect(entry.isConflict, isFalse);
    expect(entry.pageCount, 2);
    expect(entry.coverAssetId, cover);
    expect(entry.firstPageId, 'page-1');
    expect(entry.firstPageWidth, 400.0);
    expect(entry.firstPageHeight, 500.25);
    expect(entry.isPdf, isTrue);

    final preview = (await repo.loadPreview('doc-1', headId: 'pdf'))!;
    expect(preview.id, 'page-1');
    expect(preview.background.assetId, background);
    expect(preview.background.pageNumber, 2);
    expect(preview.strokes.single.points.last.x, 30);

    final full = (await repo.list()).single;
    expect(full.notebook.pages, hasLength(2));
    final converted = CatalogEntry.fromDocument(full);
    expect(converted.firstPageHeight, 500.25);
    expect(converted.isPdf, isTrue);
    final materialized = converted.withNotebook(book);
    expect(materialized.notebook, same(book));
    expect(materialized.headId, 'pdf');
    expect(materialized.deviceId, 'pc');
    expect(materialized.isConflict, isFalse);
  });
  test(
    'catálogo y vista previa respetan cabeceras, conflictos y borrado',
    () async {
      await repo.acceptRemote(revision('base', null));
      await repo.commit(revision('a', 'base', title: 'Tablet'));
      expect((await repo.listCatalog()).single.isConflict, isFalse);
      await repo.acceptRemote(revision('b', 'base', title: 'PC'));
      await repo.acceptRemote(
        Revision(
          id: 'c',
          deviceId: 'pc',
          parentId: null,
          createdAt: DateTime.utc(2026),
          notebook: fixtureNotebook(
            id: 'second',
          ).copyWith(updatedAt: DateTime.utc(2026, 11)),
        ),
      );

      final entries = await repo.listCatalog();
      expect(
        entries.map((entry) => entry.headId),
        (await repo.list()).map((entry) => entry.headId),
      );
      expect(entries.first.headId, 'c');
      expect(entries.first.isConflict, isFalse);
      expect(entries.skip(1).every((entry) => entry.isConflict), isTrue);
      expect(entries.first.coverAssetId, isNull);
      expect(entries.first.isPdf, isFalse);
      expect(await repo.loadPreview('doc-1', headId: 'base'), isNull);
      expect(await repo.loadPreview('second', headId: 'a'), isNull);
      expect(await repo.loadPreview('doc-1', headId: 'a'), isNotNull);
      expect(await repo.loadPreview('doc-1', headId: 'b'), isNotNull);

      final sql = sqlite3.open(getPath());
      try {
        sql.execute('DELETE FROM revisions WHERE id=?', ['b']);
      } finally {
        sql.close();
      }
      final remaining = await repo.listCatalog();
      expect(remaining.map((entry) => entry.headId), ['c', 'a']);
      expect(remaining.every((entry) => !entry.isConflict), isTrue);

      await repo.acceptRemote(revision(Revision.deletionId('gone'), 'a'));
      expect((await repo.listCatalog()).single.headId, 'c');
      expect(await repo.loadPreview('doc-1', headId: 'a'), isNull);
      expect(await repo.loadPreview('doc-1', headId: 'b'), isNull);
    },
  );
  test('lee datos existentes sin decodificar las otras páginas', () async {
    await repo.acceptRemote(revision('head', null));
    expect((await repo.listCatalog()).single.title, 'Álgebra');
    final sql = sqlite3.open(getPath());
    try {
      sql.execute(
        '''UPDATE revisions SET payload=json_set(payload,
          '\$.notebook.title', 'Cambio desde otra conexión',
          '\$.notebook.pages[#]', json('{"id":"segunda-inválida"}')) WHERE id=?''',
        ['head'],
      );
    } finally {
      sql.close();
    }

    final entry = (await repo.listCatalog()).single;
    expect(entry.title, 'Cambio desde otra conexión');
    expect(entry.pageCount, 2);
    expect((await repo.loadPreview('doc-1', headId: 'head'))!.id, 'page-1');
    await expectLater(repo.load('doc-1', headId: 'head'), throwsStateError);
  });
  test('cien guardados locales se agrupan sin perder el último', () async {
    String? parent;
    for (var i = 0; i < 100; i++) {
      await repo.commit(revision('r$i', parent, title: 'Cambio $i'));
      parent = 'r$i';
    }
    expect((await repo.pending()).single.id, 'r99');
    expect((await repo.history('doc-1')).length, 1);
    expect((await repo.load('doc-1'))!.title, 'Cambio 99');
  });
  test(
    'una revisión enviada nunca se reemplaza durante un reintento',
    () async {
      await repo.commit(revision('r1', null));
      await repo.pending();
      await repo.commit(revision('r2', 'r1', title: 'Después'));
      expect((await repo.history('doc-1')).map((r) => r.id).toSet(), {
        'r1',
        'r2',
      });
      expect((await repo.pending()).map((r) => r.id).toSet(), {'r1', 'r2'});
      expect((await repo.pending()).last.parentId, 'r1');
    },
  );
  test('un fallo de cola revierte también el documento', () async {
    await repo.commit(revision('r1', null));
    final sql = sqlite3.open(getPath());
    sql.execute(
      "CREATE TRIGGER fail_queue BEFORE INSERT ON upload_queue BEGIN SELECT RAISE(ABORT,'disk failure'); END",
    );
    sql.close();
    await expectLater(
      repo.commit(revision('r2', 'r1', title: 'No confirmado')),
      throwsStateError,
    );
    expect((await repo.load('doc-1'))!.title, 'Álgebra');
    expect((await repo.history('doc-1')).single.id, 'r1');
  });
  test('hijo antes del padre y reintentos no duplican heads', () async {
    await repo.acceptRemote(revision('r2', 'r1'));
    await repo.acceptRemote(revision('r1', null));
    await repo.acceptRemote(revision('r2', 'r1'));
    expect((await repo.list()).single.headId, 'r2');
    expect(await repo.pending(), isEmpty);
  });
  test('conserva ambas versiones concurrentes', () async {
    await repo.acceptRemote(revision('base', null));
    await repo.commit(revision('a', 'base', title: 'Tablet'));
    await repo.acceptRemote(revision('b', 'base', title: 'PC'));
    final entries = await repo.list();
    expect(entries.map((e) => e.notebook.title).toSet(), {'Tablet', 'PC'});
    expect(entries.every((e) => e.isConflict), isTrue);
  });
  test('rechaza un id remoto existente con distinto contenido', () async {
    await repo.acceptRemote(revision('r1', null));
    await expectLater(
      repo.acceptRemote(revision('r1', null, title: 'Alterado')),
      throwsStateError,
    );
    expect((await repo.load('doc-1'))!.title, 'Álgebra');
  });
  test('los recursos son reutilizables y se verifican al leer', () async {
    final assets = FileAssetStore('${dir.path}/assets');
    final bytes = await File('${dir.path}/fixture').writeAsBytes([1, 2, 3]);
    final id = await assets.put(await bytes.readAsBytes());
    expect(
      id,
      '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
    );
    expect(await assets.read(id), [1, 2, 3]);
    await File('${dir.path}/assets/$id').writeAsBytes([4]);
    await expectLater(assets.read(id), throwsFormatException);
  });
}
