import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../document/asset_store.dart';
import '../document/folders.dart';
import '../document/notebook.dart';
import '../document/notebook_codec.dart';
import '../document/notebook_repository.dart';
import '../document/revision.dart';
import '../document/sqlite_notebook_repository.dart';
import '../editor/pen_favorites.dart';
import '../editor/toolbar_preferences.dart';
import '../elements/element_store.dart';
import '../templates/template_store.dart';
import 'backup_zip.dart';

const _configs = {
  'templates/registry.json',
  'elements/registry.json',
  'pen-favorites.json',
  'pen.json',
  'toolbar.json',
  'appearance.json',
};

class BackupPreview {
  BackupPreview._(this._data);
  final _BackupData _data;
  int get notebookCount =>
      _data.revisions.map((r) => r.notebook.id).toSet().length;
  int get headCount => _data.heads.length;
  int get revisionCount => _data.revisions.length;
  int get assetCount =>
      _data.files.keys.where((p) => p.startsWith('assets/')).length;
  int get folderCount => _data.folders.length;
  int get templateCount =>
      (_data.configs['templates/registry.json']?['templates'] as List? ?? [])
          .length;
  int get elementCount =>
      (_data.configs['elements/registry.json']?['elements'] as List? ?? [])
          .length;
  int get preferenceCount =>
      _data.configs.keys.where((k) => !k.contains('/registry')).length;
  DateTime get createdAt => _data.createdAt;
  List<String> get warnings => List.unmodifiable(_data.warnings);
}

class BackupRestoreResult {
  BackupRestoreResult({
    required this.recoveryFolderId,
    required this.notebookCount,
    required this.templateCount,
    required this.elementCount,
    required this.preferencesRestored,
    required this.warnings,
  });
  final String recoveryFolderId;
  final int notebookCount, templateCount, elementCount;
  final bool preferencesRestored;
  final List<String> warnings;
}

/// Logical, portable backups contain content and an explicit settings whitelist.
/// Database files, cloud credentials and device identity are never enumerated.
class BackupService {
  BackupService({
    required this.root,
    required this.repository,
    required this.assets,
    required this.deviceId,
    this.appearanceFile,
  });
  final String root, deviceId;
  final NotebookRepository repository;
  final AssetStore assets;
  // The app-wide appearance file can live above an account library partition.
  // This trusted path comes from the running controller, never from ZIP input.
  final File? appearanceFile;
  File _configFile(String key) =>
      key == 'appearance.json' && appearanceFile != null
      ? appearanceFile!
      : File(p.join(root, key));
  static final Map<String, Future<void>> _queues = {};

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final key = Directory(root).absolute.path;
    final result = (_queues[key] ?? Future<void>.value()).then(
      (_) => operation(),
    );
    _queues[key] = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<T> _registries<T>(Future<T> Function() operation) =>
      TemplateStore.withRegistryLock(
        root,
        () => ElementStore.withRegistryLock(root, operation),
      );

  Future<Uint8List> export() => _serialized(
    () => _registries(() async {
      final repo = repository;
      if (repo is! SqliteNotebookRepository) {
        throw StateError('El backup requiere el repositorio local de Nala');
      }
      final snapshot = await repo.snapshot();
      final files = <String, Uint8List>{};
      final configs = <String, dynamic>{};
      var totalSize = 0;
      void addFile(String name, Uint8List bytes) {
        final limit = name.startsWith('assets/')
            ? 64 * 1024 * 1024
            : 8 * 1024 * 1024;
        if (bytes.length > limit ||
            totalSize + bytes.length > 256 * 1024 * 1024) {
          throw const FormatException(
            'El contenido supera el límite del backup',
          );
        }
        if (files.length >= 20000) {
          throw const FormatException('El backup tiene demasiados archivos');
        }
        totalSize += bytes.length;
        files[name] = bytes;
      }

      final parents = snapshot.revisions.map((r) => r.parentId).toSet();
      final heads = snapshot.revisions
          .where((r) => !parents.contains(r.id))
          .map((r) => r.id)
          .toList();
      var interruptedStrokes = 0;
      for (final relative in _configs) {
        final file = _configFile(relative);
        if (await file.exists()) {
          if (await file.length() > 8 * 1024 * 1024) {
            throw const FormatException('Un registro local supera los 8 MB');
          }
          final bytes = await file.readAsBytes();
          configs[relative] = _validateConfig(relative, bytes);
          addFile('config/$relative', bytes);
        }
      }
      final refs = <String>{};
      for (var index = 0; index < snapshot.revisions.length; index++) {
        final revision = snapshot.revisions[index];
        // Original author identifiers are private local identity metadata.
        final json =
            jsonDecode(NotebookCodec.encodeRevision(revision))
                as Map<String, dynamic>;
        json['deviceId'] = 'backup';
        if (heads.contains(revision.id)) {
          final recordingIds = revision.notebook.recordings
              .map((r) => r.id)
              .toSet();
          for (final page in (json['notebook'] as Map)['pages'] as List) {
            for (final stroke in page['strokes'] as List) {
              if (stroke['audioRecordingId'] != null &&
                  !recordingIds.contains(stroke['audioRecordingId'])) {
                stroke.remove('audioRecordingId');
                stroke.remove('audioOffsetMs');
                interruptedStrokes++;
              }
            }
          }
        }
        _assetRefs(json, refs);
        addFile(
          'revisions/${index.toString().padLeft(6, '0')}.json',
          _bytes(json),
        );
      }
      for (final value in configs.values) {
        _assetRefs(value, refs);
      }
      addFile(
        'folders.json',
        _bytes(snapshot.folders.map((f) => f.toJson()).toList()),
      );
      for (final id in refs) {
        final store = assets;
        if (store is FileAssetStore) {
          final length = await File(p.join(store.directory, id)).length();
          if (length > 64 * 1024 * 1024 ||
              totalSize + length > 256 * 1024 * 1024) {
            throw const FormatException(
              'Los recursos superan el límite del backup',
            );
          }
        }
        addFile('assets/$id', await assets.read(id));
      }
      final manifest = {
        'format': 'nala-backup',
        'version': 1,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'heads': heads,
        if (interruptedStrokes > 0)
          'warnings': [
            'Se conservaron $interruptedStrokes trazos de una grabación interrumpida. Ese audio no estaba guardado y las copias no lo incluyen.',
          ],
        'files': {
          for (final entry in files.entries)
            entry.key: {
              'size': entry.value.length,
              'sha256': sha256.convert(entry.value).toString(),
            },
        },
      };
      addFile('manifest.json', _bytes(manifest));
      return _encodeFiles(files);
    }),
  );

  Future<BackupPreview> inspect(Uint8List bytes) async =>
      BackupPreview._(await _inspectBytes(bytes));

  Future<BackupRestoreResult> restore(
    Uint8List bytes, {
    bool restorePreferences = false,
  }) => _serialized(() async {
    // No filesystem or database mutations precede this complete validation.
    final data = await _inspectBytes(bytes);
    final repo = repository;
    if (repo is! SqliteNotebookRepository) {
      throw StateError('La recuperación requiere el repositorio local de Nala');
    }
    return _registries(() async {
      final now = DateTime.now().toUtc();
      String id() => const Uuid().v4();
      final recoveryId = id();
      final folderIds = {for (final folder in data.folders) folder.id: id()};
      final documentIds = {for (final r in data.revisions) r.notebook.id: id()};
      final revisionIds = {for (final r in data.revisions) r.id: id()};
      final scopedIds = <(String, String), String>{};
      String remap(String scope, String old) =>
          scopedIds.putIfAbsent((scope, old), id);
      final folders = [
        NoteFolder(
          id: recoveryId,
          name:
              'Recuperado ${now.toLocal().toIso8601String().substring(0, 16).replaceAll('T', ' ')}',
          updatedAt: now,
        ),
        for (final folder in data.folders)
          NoteFolder(
            id: folderIds[folder.id]!,
            name: folder.name,
            parentId: folder.parentId == null
                ? recoveryId
                : folderIds[folder.parentId]!,
            updatedAt: now,
          ),
      ];
      final revisions = <Revision>[];
      for (final revision in data.revisions) {
        final map =
            jsonDecode(NotebookCodec.encodeRevision(revision))
                as Map<String, dynamic>;
        final book = map['notebook'] as Map<String, dynamic>;
        final oldId = revision.notebook.id;
        book['id'] = documentIds[oldId]!;
        book['folderId'] = book['folderId'] == null
            ? recoveryId
            : folderIds[book['folderId']]!;
        for (final page in book['pages'] as List) {
          page['id'] = remap('page:$oldId', page['id'] as String);
          for (final stroke in page['strokes'] as List) {
            stroke['id'] = remap('stroke:$oldId', stroke['id'] as String);
            if (stroke['audioRecordingId'] != null) {
              stroke['audioRecordingId'] = remap(
                'recording:$oldId',
                stroke['audioRecordingId'] as String,
              );
            }
          }
          for (final comment in page['comments'] as List? ?? []) {
            comment['id'] = remap('comment:$oldId', comment['id'] as String);
          }
          for (final object in page['objects'] as List? ?? []) {
            object['id'] = remap('object:$oldId', object['id'] as String);
            _remapLinks(object, documentIds, remap);
          }
        }
        for (final recording in book['recordings'] as List? ?? []) {
          recording['id'] = remap(
            'recording:$oldId',
            recording['id'] as String,
          );
        }
        for (final card in book['studyCards'] as List? ?? []) {
          card['id'] = remap('card:$oldId', card['id'] as String);
        }
        map['id'] = revisionIds[revision.id]!;
        map['parentId'] = revision.parentId == null
            ? null
            : revisionIds[revision.parentId]!;
        map['deviceId'] = deviceId;
        revisions.add(NotebookCodec.decodeRevision(jsonEncode(map)));
      }
      final writes = <String, Uint8List>{};
      final warnings = [...data.warnings];
      final mergedCounts = <String, int>{};
      for (final key in const [
        'templates/registry.json',
        'elements/registry.json',
      ]) {
        final incoming = data.configs[key];
        if (incoming == null) continue;
        final field = key.startsWith('templates') ? 'templates' : 'elements';
        final currentFile = _configFile(key);
        final current = await currentFile.exists()
            ? _validateConfig(key, await currentFile.readAsBytes()) as Map
            : {field: <dynamic>[]};
        final additions = <dynamic>[];
        for (final item in incoming[field] as List) {
          final copy = jsonDecode(jsonEncode(item)) as Map<String, dynamic>;
          copy['id'] = id();
          _remapLinks(copy, documentIds, remap);
          if (field == 'elements') {
            for (final stroke in copy['strokes'] as List) {
              stroke['id'] = id();
            }
            for (final object in copy['objects'] as List) {
              object['id'] = id();
            }
          }
          additions.add(copy);
        }
        final combined = _bytes({
          'version': 1,
          field: [...current[field] as List, ...additions],
        });
        if ((current[field] as List).length + additions.length > 1000 ||
            combined.length > 8 * 1024 * 1024) {
          final recoveredPath = 'recovery-registries/$recoveryId/$key';
          final recovered = _bytes({'version': 1, field: additions});
          _validateConfig(key, recovered);
          writes[recoveredPath] = recovered;
          warnings.add(
            'La biblioteca actual de ${field == 'elements' ? 'elementos' : 'plantillas'} alcanzó su límite. El contenido recuperado se guardó en $recoveredPath.',
          );
          mergedCounts[field] = 0;
        } else {
          _validateConfig(key, combined);
          writes[key] = combined;
          mergedCounts[field] = additions.length;
        }
      }
      if (restorePreferences) {
        for (final key in _configs.where((k) => !k.contains('/registry'))) {
          if (!data.configs.containsKey(key)) continue;
          final oldFile = _configFile(key);
          if (await oldFile.exists()) {
            writes['recovery-preferences/$recoveryId/$key'] = await oldFile
                .readAsBytes();
          }
          if (key == 'pen-favorites.json') {
            final old = await oldFile.exists()
                ? _validateConfig(key, await oldFile.readAsBytes()) as List
                : <dynamic>[];
            final additions = <dynamic>[];
            for (final item in data.configs[key] as List) {
              if (old.length + additions.length >= 12) break;
              final copy = Map<String, dynamic>.from(item as Map);
              copy['id'] = id();
              additions.add(copy);
            }
            if (additions.length < (data.configs[key] as List).length) {
              warnings.add(
                'Se conservaron los lápices actuales; algunos favoritos recuperados superan el límite de doce y están guardados en recovery-preferences/$recoveryId/pen-favorites-recovered.json.',
              );
              writes['recovery-preferences/$recoveryId/pen-favorites-recovered.json'] =
                  data.files['config/$key']!;
            }
            writes[key] = _bytes([...old, ...additions]);
          } else {
            writes[key] = data.files['config/$key']!;
          }
        }
        if (writes.keys.any((k) => k.startsWith('recovery-preferences/'))) {
          warnings.add(
            'Los ajustes anteriores están guardados en recovery-preferences/$recoveryId.',
          );
        }
      }
      // Content-addressed assets are validated already. Unreferenced bytes
      // left by a disk failure are harmless; no existing asset is replaced.
      for (final entry in data.files.entries.where(
        (e) => e.key.startsWith('assets/'),
      )) {
        final assetId = entry.key.substring(7);
        if (!await assets.contains(assetId)) {
          if (await assets.put(entry.value) != assetId) {
            throw StateError('Recurso de recuperación inconsistente');
          }
        } else {
          await assets.read(assetId);
        }
      }
      final staged = <_StagedFile>[];
      var committed = false;
      try {
        for (final entry in writes.entries) {
          final destination = _configFile(entry.key);
          await destination.parent.create(recursive: true);
          final temp = File('${destination.path}.${id()}.tmp');
          final rollback = File('${destination.path}.${id()}.rollback');
          final file = _StagedFile(destination, temp, rollback);
          staged.add(file);
          await temp.writeAsBytes(entry.value, flush: true);
        }
        for (final file in staged) {
          if (await file.destination.exists()) {
            await file.destination.rename(file.rollback.path);
            file.backedUp = true;
          }
          await file.temp.rename(file.destination.path);
          file.applied = true;
        }
        await repo.importBatch(folders: folders, revisions: revisions);
        committed = true;
      } catch (_) {
        for (final file in staged.reversed) {
          if (file.backedUp) {
            await file.rollback.rename(file.destination.path);
          } else if (file.applied && await file.destination.exists()) {
            await file.destination.delete();
          }
        }
        rethrow;
      } finally {
        for (final file in staged) {
          try {
            if (await file.temp.exists()) await file.temp.delete();
            if (committed && await file.rollback.exists()) {
              await file.rollback.delete();
            }
          } on FileSystemException {
            if (committed) {
              warnings.add(
                'Las copias están guardadas; no se pudo limpiar algún archivo temporal.',
              );
            }
          }
        }
      }
      return BackupRestoreResult(
        recoveryFolderId: recoveryId,
        notebookCount: documentIds.length,
        templateCount: mergedCounts['templates'] ?? 0,
        elementCount: mergedCounts['elements'] ?? 0,
        preferencesRestored:
            restorePreferences &&
            data.configs.keys.any((k) => !k.contains('/registry')),
        warnings: warnings,
      );
    });
  });
}

// Top-level spawn scopes keep database ports/controllers out of isolate messages.
Future<_BackupData> _inspectBytes(Uint8List bytes) =>
    Isolate.run(() => _validate(bytes));
Future<Uint8List> _encodeFiles(Map<String, Uint8List> files) => Isolate.run(() {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  final bytes = ZipEncoder().encodeBytes(archive);
  _validate(bytes);
  return bytes;
});

Uint8List _bytes(Object? value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

void _assetRefs(Object? value, Set<String> refs) {
  if (value is Map) {
    for (final entry in value.entries) {
      if (const {
            'assetId',
            'originalAssetId',
            'audioAssetId',
            'coverAssetId',
          }.contains(entry.key) &&
          entry.value != null) {
        refs.add(validAssetId(entry.value));
      } else {
        _assetRefs(entry.value, refs);
      }
    }
  } else if (value is List) {
    for (final item in value) {
      _assetRefs(item, refs);
    }
  }
}

void _remapLinks(
  Object? value,
  Map<String, String> documents,
  String Function(String, String) remap,
) {
  if (value is Map) {
    if (value['link'] is Map) {
      final link = value['link'] as Map;
      final original = link['notebookId'] as String;
      if (documents.containsKey(original)) {
        link['notebookId'] = documents[original]!;
        link['pageId'] = remap('page:$original', link['pageId'] as String);
      }
    }
    for (final item in value.values) {
      _remapLinks(item, documents, remap);
    }
  } else if (value is List) {
    for (final item in value) {
      _remapLinks(item, documents, remap);
    }
  }
}

_BackupData _validate(Uint8List bytes) {
  try {
    final files = readBackupZip(bytes);
    final manifestBytes = files['manifest.json'];
    if (manifestBytes == null) {
      throw const FormatException('Falta el manifiesto');
    }
    final manifest = jsonDecode(utf8.decode(manifestBytes)) as Map;
    if (manifest['format'] != 'nala-backup' || manifest['version'] != 1) {
      throw const FormatException('Versión de backup no compatible');
    }
    final createdAt = DateTime.parse(manifest['createdAt'] as String).toUtc();
    final catalog = manifest['files'] as Map;
    if (catalog.length != files.length - 1 ||
        catalog.containsKey('manifest.json')) {
      throw const FormatException(
        'El manifiesto contiene archivos faltantes o sobrantes',
      );
    }
    for (final entry in catalog.entries) {
      final name = entry.key as String;
      final metadata = entry.value as Map;
      final content = files[name];
      if (!safeBackupPath(name) ||
          content == null ||
          metadata['size'] is! int ||
          metadata['size'] != content.length ||
          metadata['sha256'] != sha256.convert(content).toString()) {
        throw const FormatException('Tamaño o hash incorrecto en el backup');
      }
      if (name.startsWith('assets/') &&
          name.substring(7) != metadata['sha256']) {
        throw const FormatException('Identificador de recurso incorrecto');
      }
    }
    final folders = (jsonDecode(utf8.decode(files['folders.json']!)) as List)
        .map((f) => NoteFolder.fromJson(f as Map<String, dynamic>))
        .toList();
    if (folders.length > 10000) {
      throw const FormatException('Demasiadas carpetas');
    }
    final folderMap = <String, NoteFolder>{};
    for (final folder in folders) {
      if (folder.id.trim().isEmpty ||
          folder.name.trim().isEmpty ||
          folderMap.containsKey(folder.id)) {
        throw const FormatException('Carpeta inválida o duplicada');
      }
      folderMap[folder.id] = folder;
    }
    for (final folder in folders) {
      final seen = <String>{folder.id};
      var parent = folder.parentId;
      while (parent != null) {
        if (!folderMap.containsKey(parent) || !seen.add(parent)) {
          throw const FormatException('Árbol de carpetas inválido');
        }
        parent = folderMap[parent]!.parentId;
      }
    }
    final revisions = files.entries
        .where((e) => e.key.startsWith('revisions/'))
        .map((e) => NotebookCodec.decodeRevision(utf8.decode(e.value)))
        .toList();
    final byId = <String, Revision>{};
    final pages = <String, Set<String>>{};
    final refs = <String>{};
    for (final revision in revisions) {
      if (byId.containsKey(revision.id) ||
          (revision.notebook.folderId != null &&
              !folderMap.containsKey(revision.notebook.folderId))) {
        throw const FormatException('Revisión duplicada o carpeta ausente');
      }
      byId[revision.id] = revision;
      pages
          .putIfAbsent(revision.notebook.id, () => {})
          .addAll(revision.notebook.pages.map((p) => p.id));
      _assetRefs(jsonDecode(NotebookCodec.encodeRevision(revision)), refs);
    }
    if (pages.length > 10000) {
      throw const FormatException('Demasiados cuadernos');
    }
    final parentIds = <String>{};
    for (final revision in revisions) {
      final seen = <String>{revision.id};
      var parent = revision.parentId;
      while (parent != null) {
        final ancestor = byId[parent];
        if (ancestor == null ||
            ancestor.notebook.id != revision.notebook.id ||
            !seen.add(parent)) {
          throw const FormatException('Historial incompleto o cíclico');
        }
        parentIds.add(parent);
        parent = ancestor.parentId;
      }
    }
    final heads = (manifest['heads'] as List).cast<String>();
    final actualHeads = byId.keys.where((k) => !parentIds.contains(k)).toSet();
    if (heads.toSet().length != heads.length ||
        heads.length != actualHeads.length ||
        !heads.toSet().containsAll(actualHeads)) {
      throw const FormatException('Versiones actuales inconsistentes');
    }
    // Ink saved while a recording is active precedes its finalized audio
    // attachment; cancelled captures can leave those immutable ancestors too.
    // Current heads must be complete, while valid historical snapshots survive.
    for (final head in heads) {
      final revision = byId[head]!;
      final recordingIds = revision.notebook.recordings
          .map((r) => r.id)
          .toSet();
      for (final page in revision.notebook.pages) {
        for (final stroke in page.strokes) {
          if (stroke.audioRecordingId != null &&
              !recordingIds.contains(stroke.audioRecordingId)) {
            throw const FormatException('Referencia a grabación ausente');
          }
        }
      }
    }
    final configs = <String, dynamic>{};
    for (final key in _configs) {
      final bytes = files['config/$key'];
      if (bytes != null) {
        configs[key] = _validateConfig(key, bytes);
        _assetRefs(configs[key], refs);
      }
    }
    if (refs.any((r) => !files.containsKey('assets/$r'))) {
      throw const FormatException('El backup tiene recursos faltantes');
    }
    final warnings = (manifest['warnings'] as List? ?? [])
        .cast<String>()
        .toList();
    if (warnings.length > 100 || warnings.any((w) => w.length > 2000)) {
      throw const FormatException('Demasiados avisos en el manifiesto');
    }
    final missingLinks = <String>{};
    void links(Object? item) {
      if (item is Map) {
        if (item['link'] is Map) {
          final link = item['link'] as Map;
          final note = nonEmpty(link['notebookId']),
              page = nonEmpty(link['pageId']);
          if (!pages.containsKey(note)) {
            missingLinks.add(note);
          } else if (!pages[note]!.contains(page)) {
            throw const FormatException(
              'Un enlace apunta a una página ausente',
            );
          }
        }
        for (final value in item.values) {
          links(value);
        }
      } else if (item is List) {
        for (final value in item) {
          links(value);
        }
      }
    }

    for (final revision in revisions) {
      links(jsonDecode(NotebookCodec.encode(revision.notebook)));
    }
    for (final config in configs.values) {
      links(config);
    }
    if (missingLinks.isNotEmpty) {
      warnings.add(
        '${missingLinks.length} destinos de enlaces no están en este backup y se conservarán como referencias externas.',
      );
    }
    return _BackupData(
      files,
      revisions,
      folders,
      configs,
      heads,
      createdAt,
      warnings,
    );
  } on FormatException {
    rethrow;
  } on Object {
    throw const FormatException('El backup está dañado o no es compatible');
  }
}

dynamic _validateConfig(String key, Uint8List bytes) {
  if (bytes.length > 8 * 1024 * 1024) {
    throw const FormatException('Registro demasiado grande');
  }
  final text = utf8.decode(bytes), value = jsonDecode(text);
  switch (key) {
    case 'templates/registry.json':
      final map = value as Map;
      if (map['version'] != 1 || (map['templates'] as List).length > 1000) {
        throw const FormatException('Plantillas inválidas');
      }
      final ids = <String>{};
      for (final item in map['templates'] as List) {
        final template = PageTemplate.fromJson(item as Map<String, dynamic>);
        if (!ids.add(template.id)) {
          throw const FormatException('Plantilla duplicada');
        }
      }
    case 'elements/registry.json':
      ElementStore.validateRegistry(text);
    case 'pen-favorites.json':
      final list = value as List;
      if (list.length > 12) {
        throw const FormatException('Demasiados lápices favoritos');
      }
      final ids = <String>{};
      for (final item in list) {
        if (!ids.add(PenFavorite.fromJson(item as Map<String, dynamic>).id)) {
          throw const FormatException('Lápiz favorito duplicado');
        }
      }
    case 'pen.json':
      final map = value as Map;
      finiteNumber(map['pressure'], min: 0, max: 1);
      finiteNumber(map['stabilization'], min: 0, max: .4);
      if (!const {
            'none',
            'pen',
            'highlighter',
            'eraser',
            'selection',
          }.contains(map['buttonTool']) ||
          !const {'hold', 'toggle'}.contains(map['buttonMode'])) {
        throw const FormatException('Ajustes del lápiz inválidos');
      }
    case 'toolbar.json':
      ToolbarLayout.fromJson(value as Map<String, dynamic>);
    case 'appearance.json':
      if (!const {
        'system',
        'light',
        'dark',
      }.contains((value as Map)['theme'])) {
        throw const FormatException('Apariencia inválida');
      }
    default:
      throw const FormatException('Preferencia no permitida');
  }
  return value;
}

class _BackupData {
  _BackupData(
    this.files,
    this.revisions,
    this.folders,
    this.configs,
    this.heads,
    this.createdAt,
    this.warnings,
  );
  final Map<String, Uint8List> files;
  final List<Revision> revisions;
  final List<NoteFolder> folders;
  final Map<String, dynamic> configs;
  final List<String> heads, warnings;
  final DateTime createdAt;
}

class _StagedFile {
  _StagedFile(this.destination, this.temp, this.rollback);
  final File destination, temp, rollback;
  bool applied = false, backedUp = false;
}
