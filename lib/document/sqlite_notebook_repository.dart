import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';
import 'notebook.dart';
import 'notebook_codec.dart';
import 'notebook_repository.dart';
import 'revision.dart';
import 'folders.dart';

class SqliteNotebookRepository
    implements
        NotebookRepository,
        FolderRepository,
        RevisionLookupRepository,
        NotebookCatalogRepository {
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
  int? _catalogDataVersion;
  Map<String, Revision> _catalogRevisions = const {};
  void Function()? onLocalChange;
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
        if (!ready.isCompleted) {
          ready.completeError(StateError(reply['error'] as String));
        }
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
  ]) async => ((await _call(op, args)) as List).cast<Revision>();
  @override
  Future<List<DocumentEntry>> list() async {
    final cached = _catalogRevisions;
    final (dataVersion, ids, loaded) =
        (await _call('list', {
              'dataVersion': _catalogDataVersion,
              'cachedIds': cached.keys.toList(),
            }))
            as (int, List<String>, List<Revision>);
    final revisions = {
      ...cached,
      for (final revision in loaded) revision.id: revision,
    };
    _catalogDataVersion = dataVersion;
    _catalogRevisions = {for (final id in ids) id: revisions[id]!};
    final heads = _catalogRevisions.values;
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
  Future<List<CatalogEntry>> listCatalog() async =>
      (await _call('listCatalog')) as List<CatalogEntry>;

  @override
  Future<NotebookPage?> loadPreview(
    String documentId, {
    required String headId,
  }) async =>
      (await _call('loadPreview', {'documentId': documentId, 'headId': headId}))
          as NotebookPage?;

  @override
  Future<Notebook?> load(String documentId, {String? headId}) async {
    if (headId != null) {
      return (await _loadRevision(
        documentId,
        headId,
        visibleOnly: true,
      ))?.notebook;
    }
    final entries = await list();
    for (final entry in entries) {
      if (entry.notebook.id == documentId) return entry.notebook;
    }
    return null;
  }

  @override
  Future<bool> isDeleted(String documentId) async =>
      (await _call('isDeleted', {'documentId': documentId})) as bool;

  @override
  Future<Revision?> lookupRevision(String documentId, String revisionId) =>
      _loadRevision(documentId, revisionId);

  Future<Revision?> _loadRevision(
    String documentId,
    String revisionId, {
    bool visibleOnly = false,
  }) async {
    final revision = await _call('load', {
      'documentId': documentId,
      'headId': revisionId,
      'visibleOnly': visibleOnly,
    });
    return revision as Revision?;
  }

  @override
  Future<void> commit(Revision revision) async {
    await _call('commit', {'revision': revision});
    onLocalChange?.call();
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
    await _call('remote', {'revision': revision});
  }

  Future<bool> hasSyncContent() async =>
      (await _call('hasSyncContent')) as bool;

  // Stage the retained history as immutable before enabling a new destination.
  Future<void> queueAllForUpload() async {
    await _call('queueAll');
    onLocalChange?.call();
  }

  @override
  Future<List<NoteFolder>> listFolders({bool includeDeleted = false}) async =>
      ((await _call('folders', {'includeDeleted': includeDeleted})) as List)
          .cast<String>()
          .map(
            (s) => NoteFolder.fromJson(jsonDecode(s) as Map<String, dynamic>),
          )
          .toList();
  @override
  Future<void> saveFolder(NoteFolder folder) async {
    await _call('saveFolder', {'payload': jsonEncode(folder.toJson())});
    onLocalChange?.call();
  }

  @override
  Future<bool> mergeFolders(List<NoteFolder> folders) async =>
      (await _call('mergeFolders', {
            'payload': folders.map((f) => jsonEncode(f.toJson())).toList(),
          }))
          as bool;

  @override
  Future<void> deleteFolder(String id) async {
    await _call('deleteFolder', {'folderId': id});
    onLocalChange?.call();
  }

  /// One worker request reads a consistent logical snapshot, including all
  /// retained histories and tombstones needed by older notebook revisions.
  Future<NotebookSnapshot> snapshot() async {
    final value = (await _call('snapshot')) as Map;
    return NotebookSnapshot(
      revisions: (value['revisions'] as List).cast<Revision>(),
      folders: (value['folders'] as List)
          .cast<String>()
          .map(
            (s) => NoteFolder.fromJson(jsonDecode(s) as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  /// Recovery never exposes half a folder tree or uploads half a notebook DAG.
  Future<void> importBatch({
    required List<NoteFolder> folders,
    required List<Revision> revisions,
  }) async {
    await _call('importBatch', {
      'folders': folders.map((f) => jsonEncode(f.toJson())).toList(),
      'revisions': revisions.map(NotebookCodec.encodeRevision).toList(),
    });
    try {
      onLocalChange?.call();
    } on Object {
      // The transaction has committed. A notification failure must not make
      // recovery roll back its registries while the notebooks remain saved.
    }
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

const _deletionIdPattern = "GLOB '${Revision.deletionIdPrefix}*'";
const _notDeleted =
    '''NOT EXISTS (
  SELECT 1 FROM revisions d WHERE d.document_id=r.document_id
    AND d.id $_deletionIdPattern
)''';
const _visibleHead = '''$_notDeleted AND NOT EXISTS (
  SELECT 1 FROM revisions c WHERE c.parent_id=r.id AND c.document_id=r.document_id
)''';

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
      'CREATE TABLE IF NOT EXISTS folders (id TEXT PRIMARY KEY, name TEXT NOT NULL, parent_id TEXT, updated_at TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS revisions (id TEXT PRIMARY KEY, document_id TEXT NOT NULL, parent_id TEXT, payload TEXT NOT NULL, frozen INTEGER NOT NULL DEFAULT 0)',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS revisions_document ON revisions(document_id)',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS revisions_parent_document ON revisions(parent_id, document_id)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS upload_queue (revision_id TEXT PRIMARY KEY REFERENCES revisions(id))',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS revisions_deleted_document ON revisions(document_id) WHERE id $_deletionIdPattern',
    );
  } catch (error) {
    reply.send({'error': error.toString()});
    return;
  }
  final requests = ReceivePort();
  final catalog = _CatalogSummary();
  reply.send(requests.sendPort);
  requests.listen((message) {
    final request = message as Map;
    try {
      if (request['revision'] is Revision) {
        request['payload'] = NotebookCodec.encodeRevision(
          request['revision'] as Revision,
        );
        NotebookCodec.decodeRevision(request['payload'] as String);
      }
      Object? result;
      switch (request['op']) {
        case 'snapshot':
          result = _transaction(
            db,
            () => {
              'revisions': db
                  .select('SELECT payload FROM revisions ORDER BY rowid')
                  .map(
                    (r) => NotebookCodec.decodeRevision(r['payload'] as String),
                  )
                  .toList(),
              'folders': db
                  .select('SELECT * FROM folders')
                  .map(
                    (r) => jsonEncode({
                      'id': r['id'],
                      'name': r['name'],
                      'parentId': r['parent_id'],
                      'updatedAt': r['updated_at'],
                      'deleted': r['deleted'] == 1,
                    }),
                  )
                  .toList(),
            },
          );
        case 'importBatch':
          _transaction(db, () {
            final folders = (request['folders'] as List)
                .cast<String>()
                .map(
                  (s) => NoteFolder.fromJson(
                    jsonDecode(s) as Map<String, dynamic>,
                  ),
                )
                .toList();
            final revisions = (request['revisions'] as List)
                .cast<String>()
                .map(NotebookCodec.decodeRevision)
                .toList();
            final catalog = <String, String?>{
              for (final r in db.select(
                'SELECT id,parent_id FROM folders WHERE deleted=0',
              ))
                r['id'] as String: r['parent_id'] as String?,
            };
            final folderIds = <String>{};
            for (final folder in folders) {
              if (folder.id.trim().isEmpty ||
                  folder.name.trim().isEmpty ||
                  folder.deleted ||
                  !folderIds.add(folder.id) ||
                  db.select('SELECT id FROM folders WHERE id=?', [
                    folder.id,
                  ]).isNotEmpty) {
                throw StateError(
                  'Carpeta de recuperación inválida o existente',
                );
              }
              catalog[folder.id] = folder.parentId;
            }
            for (final folder in folders) {
              final seen = <String>{folder.id};
              var parent = folder.parentId;
              while (parent != null) {
                if (!catalog.containsKey(parent) || !seen.add(parent)) {
                  throw StateError('Árbol de recuperación inválido');
                }
                parent = catalog[parent];
              }
            }
            final byId = <String, Revision>{};
            for (final revision in revisions) {
              if (byId.containsKey(revision.id) ||
                  db.select(
                    'SELECT id FROM revisions WHERE id=? OR document_id=?',
                    [revision.id, revision.notebook.id],
                  ).isNotEmpty ||
                  (revision.notebook.folderId != null &&
                      !catalog.containsKey(revision.notebook.folderId))) {
                throw StateError(
                  'Revisión de recuperación inválida o existente',
                );
              }
              byId[revision.id] = revision;
            }
            for (final revision in revisions) {
              final seen = <String>{revision.id};
              var parent = revision.parentId;
              while (parent != null) {
                final ancestor = byId[parent];
                if (ancestor == null ||
                    ancestor.notebook.id != revision.notebook.id ||
                    !seen.add(parent)) {
                  throw StateError('Historial de recuperación inválido');
                }
                parent = ancestor.parentId;
              }
            }
            for (final folder in folders) {
              db.execute(
                'INSERT INTO folders(id,name,parent_id,updated_at,deleted) VALUES(?,?,?,?,0)',
                [
                  folder.id,
                  folder.name,
                  folder.parentId,
                  folder.updatedAt.toUtc().toIso8601String(),
                ],
              );
            }
            for (final revision in revisions) {
              db.execute(
                'INSERT INTO revisions(id,document_id,parent_id,payload,frozen) VALUES(?,?,?,?,1)',
                [
                  revision.id,
                  revision.notebook.id,
                  revision.parentId,
                  NotebookCodec.encodeRevision(revision),
                ],
              );
              db.execute('INSERT INTO upload_queue VALUES(?)', [revision.id]);
            }
          });
        case 'mergeFolders':
          result = _transaction(db, () {
            final catalog = <String, NoteFolder>{
              for (final row in db.select('SELECT * FROM folders'))
                row['id'] as String: NoteFolder(
                  id: row['id'] as String,
                  name: row['name'] as String,
                  parentId: row['parent_id'] as String?,
                  updatedAt: DateTime.parse(row['updated_at'] as String),
                  deleted: row['deleted'] == 1,
                ),
            };
            for (final encoded in request['payload'] as List) {
              final folder = NoteFolder.fromJson(
                jsonDecode(encoded as String) as Map<String, dynamic>,
              );
              if (folder.id.isEmpty ||
                  folder.name.trim().isEmpty ||
                  folder.parentId == folder.id) {
                throw const FormatException('Carpeta remota inválida');
              }
              final old = catalog[folder.id];
              if (old == null ||
                  folder.updatedAt.isAfter(old.updatedAt) ||
                  (folder.updatedAt == old.updatedAt &&
                      jsonEncode(
                            folder.toJson(),
                          ).compareTo(jsonEncode(old.toJson())) >
                          0)) {
                catalog[folder.id] = folder;
              }
            }
            // Concurrent valid moves can form a cycle. Deterministically return
            // its smallest id to root, keeping every folder and notebook.
            for (final id in catalog.keys.toList()..sort()) {
              final path = <String>[];
              String? cursor = id;
              while (cursor != null &&
                  catalog[cursor] != null &&
                  !catalog[cursor]!.deleted) {
                final cycleStart = path.indexOf(cursor);
                if (cycleStart >= 0) {
                  final root = (path.sublist(cycleStart)..sort()).first;
                  catalog[root] = catalog[root]!.copyWith(parentId: null);
                  break;
                }
                path.add(cursor);
                final parent = catalog[cursor]!.parentId;
                if (parent != null &&
                    (catalog[parent] == null || catalog[parent]!.deleted)) {
                  catalog[cursor] = catalog[cursor]!.copyWith(parentId: null);
                  break;
                }
                cursor = parent;
              }
            }
            var changed = false;
            for (final folder in catalog.values) {
              db.execute(
                'INSERT INTO folders(id,name,parent_id,updated_at,deleted) VALUES(?,?,?,?,?) '
                'ON CONFLICT(id) DO UPDATE SET name=excluded.name,parent_id=excluded.parent_id,'
                'updated_at=excluded.updated_at,deleted=excluded.deleted '
                'WHERE folders.name IS NOT excluded.name '
                'OR folders.parent_id IS NOT excluded.parent_id '
                'OR folders.updated_at IS NOT excluded.updated_at '
                'OR folders.deleted IS NOT excluded.deleted',
                [
                  folder.id,
                  folder.name,
                  folder.parentId,
                  folder.updatedAt.toUtc().toIso8601String(),
                  folder.deleted ? 1 : 0,
                ],
              );
              changed = db.updatedRows > 0 || changed;
            }
            return changed;
          });
        case 'folders':
          result = db
              .select(
                'SELECT * FROM folders WHERE ? OR deleted=0 ORDER BY name COLLATE NOCASE',
                [request['includeDeleted'] == true ? 1 : 0],
              )
              .map(
                (r) => jsonEncode({
                  'id': r['id'],
                  'name': r['name'],
                  'parentId': r['parent_id'],
                  'updatedAt': r['updated_at'],
                  'deleted': r['deleted'] == 1,
                }),
              )
              .toList();
        case 'saveFolder':
          _transaction(db, () {
            final f = NoteFolder.fromJson(
              jsonDecode(request['payload'] as String) as Map<String, dynamic>,
            );
            if (f.id.trim().isEmpty || f.name.trim().isEmpty || f.deleted) {
              throw StateError('Carpeta inválida');
            }
            var parent = f.parentId;
            final visited = <String>{f.id};
            while (parent != null) {
              if (!visited.add(parent)) {
                throw StateError('Una carpeta no puede contenerse a sí misma');
              }
              final rows = db.select(
                'SELECT parent_id FROM folders WHERE id=? AND deleted=0',
                [parent],
              );
              if (rows.isEmpty) {
                throw StateError('La carpeta de destino no existe');
              }
              parent = rows.single['parent_id'] as String?;
            }
            if (db.select(
              'SELECT id FROM folders WHERE parent_id IS ? AND name=? COLLATE NOCASE AND id<>? AND deleted=0',
              [f.parentId, f.name.trim(), f.id],
            ).isNotEmpty) {
              throw StateError('Ya hay una carpeta con ese nombre');
            }
            db.execute(
              'INSERT INTO folders(id,name,parent_id,updated_at,deleted) VALUES (?,?,?,?,0) ON CONFLICT(id) DO UPDATE SET name=excluded.name,parent_id=excluded.parent_id,updated_at=excluded.updated_at,deleted=0',
              [
                f.id,
                f.name.trim(),
                f.parentId,
                f.updatedAt.toUtc().toIso8601String(),
              ],
            );
          });
        case 'deleteFolder':
          _transaction(db, () {
            final id = request['folderId'];
            if (db.select(
                  'SELECT id FROM folders WHERE parent_id=? AND deleted=0',
                  [id],
                ).isNotEmpty ||
                db
                    .select(
                      '''SELECT r.id FROM revisions r
                     WHERE json_extract(r.payload,'\$.notebook.folderId')=?
                       AND $_notDeleted
                       AND NOT EXISTS (SELECT 1 FROM revisions c WHERE c.parent_id=r.id AND c.document_id=r.document_id)''',
                      [id],
                    )
                    .isNotEmpty) {
              throw StateError(
                'La carpeta todavía contiene apuntes o subcarpetas',
              );
            }
            db.execute('UPDATE folders SET deleted=1,updated_at=? WHERE id=?', [
              DateTime.now().toUtc().toIso8601String(),
              id,
            ]);
          });
        case 'hasSyncContent':
          result =
              db
                  .select(
                    'SELECT EXISTS(SELECT 1 FROM revisions) OR EXISTS(SELECT 1 FROM folders) AS present',
                  )
                  .single['present'] ==
              1;
        case 'queueAll':
          _transaction(db, () {
            db.execute('UPDATE revisions SET frozen=1 WHERE frozen=0');
            db.execute(
              'INSERT OR IGNORE INTO upload_queue(revision_id) SELECT id FROM revisions',
            );
          });
        case 'list':
          final (version, ids, rows) = _readCatalogRows(
            db,
            request['dataVersion'] as int?,
            (request['cachedIds'] as List).cast<String>(),
            'r.payload',
          );
          result = (
            version,
            ids,
            [
              for (final row in rows)
                NotebookCodec.decodeRevision(row['payload'] as String),
            ],
          );
        case 'listCatalog':
          result = catalog.read(db);
        case 'loadPreview':
          final rows = db.select(
            r"SELECT json_extract(r.payload, '$.notebook.pages[0]') AS page "
            'FROM revisions r WHERE r.id=? AND r.document_id=? AND $_visibleHead',
            [request['headId'], request['documentId']],
          );
          result = rows.isEmpty
              ? null
              : NotebookPage.fromJson(
                  jsonDecode(rows.single['page'] as String)
                      as Map<String, dynamic>,
                );
        case 'load':
          final visibility = request['visibleOnly'] == true
              ? ' AND $_notDeleted'
              : '';
          final rows = db.select(
            'SELECT r.payload FROM revisions r WHERE r.id=? AND r.document_id=?$visibility',
            [request['headId'], request['documentId']],
          );
          result = rows.isEmpty ? null : rows.single['payload'];
        case 'isDeleted':
          result = db
              .select(
                '''SELECT 1 FROM revisions WHERE document_id=?
               AND id $_deletionIdPattern LIMIT 1''',
                [request['documentId']],
              )
              .isNotEmpty;
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
            if (revision.deleted) {
              // A head from the menu may have been coalesced while its
              // confirmation was open. Keep an existing revision as parent.
              final retained = db.select(
                '''SELECT r.id FROM revisions r WHERE r.document_id=? AND $_notDeleted
                   ORDER BY (r.id=?) DESC, r.rowid DESC LIMIT 1''',
                [revision.notebook.id, revision.parentId],
              );
              if (retained.isEmpty) return;
              revision = revision.withParent(retained.single['id'] as String);
            }
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
            if (!revision.deleted &&
                parent.isNotEmpty &&
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
              'INSERT INTO revisions (id,document_id,parent_id,payload,frozen) VALUES (?,?,?,?,?)',
              [
                revision.id,
                revision.notebook.id,
                revision.parentId,
                NotebookCodec.encodeRevision(revision),
                revision.deleted ? 1 : 0,
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
      if (result is List &&
          const {'history', 'pending'}.contains(request['op'])) {
        result = result
            .cast<String>()
            .map(NotebookCodec.decodeRevision)
            .toList();
      } else if (request['op'] == 'load' && result != null) {
        result = NotebookCodec.decodeRevision(result as String);
      }
      reply.send({'id': request['id'], 'result': result});
    } catch (error) {
      reply.send({'id': request['id'], 'error': error.toString()});
    }
  });
}

(int, List<String>, List<Row>) _readCatalogRows(
  Database db,
  int? cachedVersion,
  Iterable<String> cachedIds,
  String projection,
) => _transaction(db, write: false, () {
  // Revisions are immutable. Invalidate the cache if another connection
  // changed the database, and read IDs and payloads within the same snapshot.
  final version =
      db.select('PRAGMA data_version').single['data_version'] as int;
  final known = version == cachedVersion ? cachedIds.toSet() : const <String>{};
  final columns = known.isEmpty ? 'r.id, $projection' : 'r.id';
  final rows = db.select(
    'SELECT $columns FROM revisions r WHERE $_visibleHead',
  );
  final ids = [for (final row in rows) row['id'] as String];
  if (known.isEmpty) {
    return (version, ids, rows.toList());
  }
  return (
    version,
    ids,
    [
      for (final id in ids)
        if (!known.contains(id))
          db.select('SELECT r.id, $projection FROM revisions r WHERE r.id=?', [
            id,
          ]).single,
    ],
  );
});

const _catalogProjection = r'''r.document_id,
  json_extract(r.payload, '$.deviceId') AS device_id,
  json_extract(r.payload, '$.notebook.title') AS title,
  json_extract(r.payload, '$.notebook.subject') AS subject,
  json_extract(r.payload, '$.notebook.updatedAt') AS updated_at,
  json_extract(r.payload, '$.notebook.folderId') AS folder_id,
  json_extract(r.payload, '$.notebook.coverAssetId') AS cover_asset_id,
  json_array_length(r.payload, '$.notebook.pages') AS page_count,
  json_extract(r.payload, '$.notebook.pages[0].id') AS first_page_id,
  json_extract(r.payload, '$.notebook.pages[0].width') AS first_page_width,
  json_extract(r.payload, '$.notebook.pages[0].height') AS first_page_height,
  json_extract(r.payload, '$.notebook.pages[0].background.kind') AS first_page_background
''';

class _CatalogSummary {
  int? _version;
  Map<String, Row> _rows = const {};
  List<CatalogEntry> _entries = const [];

  List<CatalogEntry> read(Database db) {
    final (version, ids, fresh) = _readCatalogRows(
      db,
      _version,
      _rows.keys,
      _catalogProjection,
    );
    if (version == _version && fresh.isEmpty && _sameHeads(ids)) {
      return _entries;
    }
    final available = {
      if (version == _version) ..._rows,
      for (final row in fresh) row['id'] as String: row,
    };
    final rows = {for (final id in ids) id: available[id]!};
    final entries = _catalogEntries(rows.values);
    _version = version;
    _rows = rows;
    return _entries = entries;
  }

  bool _sameHeads(List<String> ids) {
    if (ids.length != _rows.length) return false;
    var index = 0;
    for (final id in _rows.keys) {
      if (id != ids[index++]) return false;
    }
    return true;
  }
}

List<CatalogEntry> _catalogEntries(Iterable<Row> rows) {
  final counts = <String, int>{};
  for (final row in rows) {
    counts.update(
      row['document_id'] as String,
      (n) => n + 1,
      ifAbsent: () => 1,
    );
  }
  return [
    for (final row in rows)
      CatalogEntry(
        documentId: row['document_id'] as String,
        title: row['title'] as String,
        subject: row['subject'] as String,
        updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
        folderId: row['folder_id'] as String?,
        headId: row['id'] as String,
        deviceId: row['device_id'] as String,
        isConflict: counts[row['document_id']]! > 1,
        pageCount: row['page_count'] as int,
        coverAssetId: row['cover_asset_id'] as String?,
        firstPageId: row['first_page_id'] as String,
        firstPageWidth: (row['first_page_width'] as num).toDouble(),
        firstPageHeight: (row['first_page_height'] as num).toDouble(),
        isPdf: row['first_page_background'] == 'pdf',
      ),
  ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}

T _transaction<T>(Database db, T Function() action, {bool write = true}) {
  db.execute(write ? 'BEGIN IMMEDIATE' : 'BEGIN');
  try {
    final result = action();
    db.execute('COMMIT');
    return result;
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}

class NotebookSnapshot {
  NotebookSnapshot({
    required List<Revision> revisions,
    required List<NoteFolder> folders,
  }) : revisions = List.unmodifiable(revisions),
       folders = List.unmodifiable(folders);
  final List<Revision> revisions;
  final List<NoteFolder> folders;
}
