import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:apuntes/document/sqlite_notebook_repository.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/document/asset_store.dart';
import '../support/fixtures.dart';

void main() {
  late Directory dir;
  late SqliteNotebookRepository repo;
  String getPath() => '${dir.path}/notes.db';
  Revision revision(String id, String? parent, {String? title}) => Revision(
    id: id, deviceId: 'tablet', parentId: parent, createdAt: DateTime.utc(2026),
    notebook: fixtureNotebook().copyWith(title: title));
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('nala-repo-');
    repo = await SqliteNotebookRepository.open(getPath());
  });
  tearDown(() async { await repo.close(); await dir.delete(recursive: true); });
  test('un cierre conserva el cuaderno y el pendiente', () async {
    await repo.commit(revision('r1', null));
    await repo.close();
    repo = await SqliteNotebookRepository.open(getPath());
    expect((await repo.load('doc-1'))!.pages.single.strokes.single.points.last.x, 30);
    expect((await repo.pending()).single.id, 'r1');
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
  test('una revisión enviada nunca se reemplaza durante un reintento', () async {
    await repo.commit(revision('r1', null));
    await repo.pending();
    await repo.commit(revision('r2', 'r1', title: 'Después'));
    expect((await repo.history('doc-1')).map((r) => r.id).toSet(), {'r1', 'r2'});
    expect((await repo.pending()).map((r) => r.id).toSet(), {'r1', 'r2'});
    expect((await repo.pending()).last.parentId, 'r1');
  });
  test('un fallo de cola revierte también el documento', () async {
    await repo.commit(revision('r1', null));
    final sql = sqlite3.open(getPath());
    sql.execute("CREATE TRIGGER fail_queue BEFORE INSERT ON upload_queue BEGIN SELECT RAISE(ABORT,'disk failure'); END");
    sql.dispose();
    await expectLater(repo.commit(revision('r2', 'r1', title: 'No confirmado')), throwsStateError);
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
    await expectLater(repo.acceptRemote(revision('r1', null, title: 'Alterado')), throwsStateError);
    expect((await repo.load('doc-1'))!.title, 'Álgebra');
  });
  test('los recursos son reutilizables y se verifican al leer', () async {
    final assets = FileAssetStore('${dir.path}/assets');
    final bytes = await File('${dir.path}/fixture').writeAsBytes([1, 2, 3]);
    final id = await assets.put(await bytes.readAsBytes());
    expect(id, '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81');
    expect(await assets.read(id), [1, 2, 3]);
    await File('${dir.path}/assets/$id').writeAsBytes([4]);
    await expectLater(assets.read(id), throwsFormatException);
  });
}
