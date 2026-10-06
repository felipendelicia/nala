import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:sqlite3/sqlite3.dart';
import 'notebook.dart';
import 'notebook_codec.dart';
import 'notebook_repository.dart';
import 'revision.dart';

class SqliteNotebookRepository implements NotebookRepository {
  SqliteNotebookRepository._(
    this._port,
    this._receive,
    this._worker,
    this._responses,
  );
  final SendPort _port;
  final ReceivePort _receive;
  final Isolate _worker;
  final Map<int, Completer<Object?>> _responses;
  int _requestId = 0;
  bool _closed = false;
  static Future<SqliteNotebookRepository> open(String path) async {
    await File(path).parent.create(recursive: true);
    final receive = ReceivePort();
    final ready = Completer<SendPort>();
    final responses = <int, Completer<Object?>>{};
    receive.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
        return;
      }
      final reply = message as Map;
      if (reply['id'] == null) {
        if (!ready.isCompleted)
          ready.completeError(StateError(reply['error'] as String));
        return;
      }
      final pending = responses.remove(reply['id']);
      if (reply.containsKey('error')) {
        pending?.completeError(StateError(reply['error'] as String));
      } else {
        pending?.complete(reply['result']);
      }
    });
    final worker = await Isolate.spawn(_databaseWorker, (
      receive.sendPort,
      path,
    ));
    try {
      return SqliteNotebookRepository._(
        await ready.future,
        receive,
        worker,
        responses,
      );
    } catch (_) {
      worker.kill();
      receive.close();
      rethrow;
    }
  }

  Future<Object?> _call(String op, [Map<String, Object?> args = const {}]) {
    if (_closed) return Future.error(StateError('Repositorio cerrado'));
    final id = ++_requestId;
    final response = Completer<Object?>();
    _responses[id] = response;
    _port.send({'id': id, 'op': op, ...args});
    return response.future;
  }

  Future<List<Revision>> _revisions(
    String op, [
    Map<String, Object?> args = const {},
  ]) async => ((await _call(op, args)) as List)
      .cast<String>()
      .map(NotebookCodec.decodeRevision)
      .toList();
  @override
  Future<List<DocumentEntry>> list() async {
    final heads = await _revisions('list');
    final counts = <String, int>{};
    for (final r in heads) {
      counts.update(r.notebook.id, (n) => n + 1, ifAbsent: () => 1);
    }
    return heads
        .map(
          (r) => DocumentEntry(
            notebook: r.notebook,
            headId: r.id,
            deviceId: r.deviceId,
            isConflict: counts[r.notebook.id]! > 1,
          ),
        )
        .toList()
      ..sort((a, b) => b.notebook.updatedAt.compareTo(a.notebook.updatedAt));
  }

  @override
  Future<Notebook?> load(String documentId, {String? headId}) async {
    if (headId != null) {
      final json = await _call('load', {
        'documentId': documentId,
        'headId': headId,
      });
      return json == null
          ? null
          : NotebookCodec.decodeRevision(json as String).notebook;
    }
    final entries = await list();
    for (final entry in entries) {
      if (entry.notebook.id == documentId) return entry.notebook;
    }
    return null;
  }

  @override
  Future<void> commit(Revision revision) async {
    final payload = NotebookCodec.encodeRevision(revision);
    NotebookCodec.decodeRevision(payload);
    await _call('commit', {'payload': payload});
  }

  @override
  Future<List<Revision>> pending() => _revisions('pending');
  @override
  Future<List<Revision>> history(String documentId) =>
      _revisions('history', {'documentId': documentId});
  @override
  Future<void> markUploaded(String revisionId) async {
    await _call('uploaded', {'revisionId': revisionId});
  }

  @override
  Future<void> acceptRemote(Revision revision) async {
    final payload = NotebookCodec.encodeRevision(revision);
    NotebookCodec.decodeRevision(payload);
    await _call('remote', {'payload': payload});
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    await _call('close');
    _closed = true;
    _receive.close();
    _worker.kill();
  }
}

void _databaseWorker((SendPort, String) config) {
  final (reply, path) = config;
  late Database db;
  try {
    db = sqlite3.open(path);
    db.execute('PRAGMA journal_mode=WAL');
    db.execute('PRAGMA synchronous=FULL');
    db.execute('PRAGMA busy_timeout=5000');
    db.execute('PRAGMA foreign_keys=ON');
    db.execute(
      'CREATE TABLE IF NOT EXISTS revisions (id TEXT PRIMARY KEY, document_id TEXT NOT NULL, parent_id TEXT, payload TEXT NOT NULL, frozen INTEGER NOT NULL DEFAULT 0)',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS revisions_document ON revisions(document_id)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS upload_queue (revision_id TEXT PRIMARY KEY REFERENCES revisions(id))',
    );
  } catch (error) {
    reply.send({'error': error.toString()});
    return;
  }
  final requests = ReceivePort();
  reply.send(requests.sendPort);
  requests.listen((message) {
    final request = message as Map;
    try {
      Object? result;
      switch (request['op']) {
        case 'list':
          result = db
              .select(
                'SELECT r.payload FROM revisions r WHERE NOT EXISTS (SELECT 1 FROM revisions c WHERE c.parent_id=r.id AND c.document_id=r.document_id)',
              )
              .map((row) => row['payload'])
              .toList();
        case 'load':
          final rows = db.select(
            'SELECT payload FROM revisions WHERE id=? AND document_id=?',
            [request['headId'], request['documentId']],
          );
          result = rows.isEmpty ? null : rows.single['payload'];
        case 'history':
          result = db
              .select(
                'SELECT payload FROM revisions WHERE document_id=? ORDER BY rowid',
                [request['documentId']],
              )
              .map((r) => r['payload'])
              .toList();
        case 'commit':
          _transaction(db, () {
            var revision = NotebookCodec.decodeRevision(
              request['payload'] as String,
            );
            final parent = db.select('SELECT * FROM revisions WHERE id=?', [
              revision.parentId,
            ]);
            if (parent.isNotEmpty &&
                parent.single['document_id'] != revision.notebook.id) {
              throw StateError('Padre de otro cuaderno');
            }
            final children = db.select(
              'SELECT id FROM revisions WHERE parent_id=?',
              [revision.parentId],
            );
            if (parent.isNotEmpty &&
                parent.single['frozen'] == 0 &&
                children.isEmpty) {
              final previous = revision.parentId;
              revision = revision.withParent(
                parent.single['parent_id'] as String?,
              );
              db.execute('DELETE FROM upload_queue WHERE revision_id=?', [
                previous,
              ]);
              db.execute('DELETE FROM revisions WHERE id=?', [previous]);
            }
            db.execute(
              'INSERT INTO revisions (id,document_id,parent_id,payload) VALUES (?,?,?,?)',
              [
                revision.id,
                revision.notebook.id,
                revision.parentId,
                NotebookCodec.encodeRevision(revision),
              ],
            );
            db.execute('INSERT INTO upload_queue VALUES (?)', [revision.id]);
          });
        case 'pending':
          result = _transaction(db, () {
            db.execute(
              'UPDATE revisions SET frozen=1 WHERE id IN (SELECT revision_id FROM upload_queue)',
            );
            return db
                .select(
                  'SELECT payload FROM revisions WHERE id IN (SELECT revision_id FROM upload_queue) ORDER BY rowid',
                )
                .map((r) => r['payload'])
                .toList();
          });
        case 'uploaded':
          db.execute('DELETE FROM upload_queue WHERE revision_id=?', [
            request['revisionId'],
          ]);
        case 'remote':
          final revision = NotebookCodec.decodeRevision(
            request['payload'] as String,
          );
          final existing = db.select(
            'SELECT payload FROM revisions WHERE id=?',
            [revision.id],
          );
          if (existing.isNotEmpty &&
              existing.single['payload'] != request['payload']) {
            throw StateError('Revisión remota alterada');
          }
          db.execute(
            'INSERT OR IGNORE INTO revisions (id,document_id,parent_id,payload,frozen) VALUES (?,?,?,?,1)',
            [
              revision.id,
              revision.notebook.id,
              revision.parentId,
              request['payload'],
            ],
          );
        case 'close':
          db.close();
          requests.close();
        default:
          throw StateError('Operación desconocida');
      }
      reply.send({'id': request['id'], 'result': result});
    } catch (error) {
      reply.send({'id': request['id'], 'error': error.toString()});
    }
  });
}

T _transaction<T>(Database db, T Function() action) {
  db.execute('BEGIN IMMEDIATE');
  try {
    final result = action();
    db.execute('COMMIT');
    return result;
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}
