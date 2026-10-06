import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../account/auth_service.dart';
import '../document/folders.dart';
import '../document/revision.dart';
import '../document/document_worker.dart';
import 'drive_http.dart';
import 'remote_store.dart';
import 'upload_session_store.dart';

String _sha(Uint8List bytes) => sha256.convert(bytes).toString();
String _md5(Uint8List bytes) => md5.convert(bytes).toString();
String _quote(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
String _property(String key, String value) =>
    "appProperties has { key='${_quote(key)}' and value='${_quote(value)}' }";

class DriveRemoteStore implements RemoteStore {
  DriveRemoteStore({
    required AuthService auth,
    required http.Client client,
    required this.accountId,
    required this.sessions,
    this.codecEvents,
  }) : _http = DriveHttp(auth: auth, client: client, accountId: accountId);
  final String accountId;
  final SendPort? codecEvents;
  DocumentWorker get _worker => DocumentWorker(events: codecEvents);
  final UploadSessionStore sessions;
  final DriveHttp _http;
  String? _root;
  final _revisions = <String, Revision>{};
  final _verifiedAssets = <String, Uint8List>{};
  Uri _uri(String path, [Map<String, String> query = const {}]) =>
      Uri.https('www.googleapis.com', path, query);
  Future<List<Map<String, dynamic>>> _list(String condition) async {
    final files = <Map<String, dynamic>>[];
    final tokens = <String>{};
    String? token;
    do {
      final response = await _http.request(
        'GET',
        _uri('/drive/v3/files', {
          'q':
              "trashed = false and ${_property('application', 'nala-v1')} and $condition",
          'fields':
              'nextPageToken,files(id,name,appProperties,modifiedTime,md5Checksum,size)',
          'pageSize': '1000',
          'pageToken': ?token,
        }),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      files.addAll((data['files'] as List? ?? []).cast<Map<String, dynamic>>());
      token = data['nextPageToken'] as String?;
      if (token != null && !tokens.add(token)) {
        throw const FormatException('Listado cíclico de Drive');
      }
    } while (token != null);
    return files;
  }

  Future<List<Map<String, dynamic>>> _find(
    String kind,
    String property,
    String value,
  ) => _list('${_property('kind', kind)} and ${_property(property, value)}');
  Future<Uint8List> _read(Map<String, dynamic> file) async {
    final id = file['id'] as String;
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('Archivo Drive inválido');
    }
    return (await _http.request(
      'GET',
      _uri('/drive/v3/files/$id', {'alt': 'media'}),
    )).bodyBytes;
  }

  @override
  Future<List<Revision>> listRevisions() async {
    _root = null;
    final result = <String, Revision>{};
    for (final file in await _list(_property('kind', 'revision'))) {
      final properties = file['appProperties'] as Map<String, dynamic>;
      final revisionId = properties['revisionId'] as String;
      final cacheKey =
          '${file['id']}:${file['md5Checksum']}:${file['modifiedTime']}';
      final revision = file['md5Checksum'] == null
          ? await _worker.decode(await _read(file))
          : (_revisions[cacheKey] ??= await _worker.decode(await _read(file)));
      if (revision.id != revisionId ||
          (properties['documentId'] != null &&
              revision.notebook.id != properties['documentId'])) {
        throw const FormatException('Identidad de revisión inválida');
      }
      final old = result[revision.id];
      if (old != null && !await _worker.equal(old, revision)) {
        throw const FormatException(
          'Revisión duplicada con contenido diferente',
        );
      }
      result[revision.id] = revision;
    }
    return result.values.toList();
  }

  Future<String> _rootId() async {
    if (_root != null) return _root!;
    final roots = await _list(_property('kind', 'root'));
    if (roots.isNotEmpty) {
      return _root =
          (roots.map((f) => f['id'] as String).toList()..sort()).first;
    }
    try {
      final response = await _http.request(
        'POST',
        _uri('/drive/v3/files', {'fields': 'id'}),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({
          'name': 'Nala',
          'mimeType': 'application/vnd.google-apps.folder',
          'appProperties': {'application': 'nala-v1', 'kind': 'root'},
        }),
      );
      return _root =
          (jsonDecode(response.body) as Map<String, dynamic>)['id'] as String;
    } on TimeoutException {
      final recovered = await _list(_property('kind', 'root'));
      if (recovered.isEmpty) rethrow;
      return _root =
          (recovered.map((f) => f['id'] as String).toList()..sort()).first;
    }
  }

  Future<bool> _confirmed(
    String kind,
    String property,
    String id,
    String expected,
  ) async {
    final files = await _find(kind, property, id);
    if (files.isEmpty) return false;
    for (final file in files) {
      final bytes = await _read(file);
      final canonical = kind == 'revision'
          ? await _worker.canonical(bytes)
          : jsonEncode(
              NoteFolder.fromJson(
                jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
              ).toJson(),
            );
      if (canonical != expected) {
        throw const FormatException('Un registro remoto cambió de contenido');
      }
    }
    return true;
  }

  Future<void> _putJson(
    String kind,
    String property,
    String id,
    String payload,
    Map<String, String> extra,
  ) async {
    if (await _confirmed(kind, property, id, payload)) return;
    final root = await _rootId();
    final boundary = 'nala-${const Uuid().v4()}';
    final metadata = jsonEncode({
      'name': '$kind-$id.json',
      'parents': [root],
      'appProperties': {
        'application': 'nala-v1',
        'kind': kind,
        property: id,
        ...extra,
      },
    });
    final body = await _worker.multipart(metadata, payload, boundary);
    try {
      await _http.request(
        'POST',
        _uri('/upload/drive/v3/files', {
          'uploadType': 'multipart',
          'fields': 'id',
        }),
        headers: {'Content-Type': 'multipart/related; boundary=$boundary'},
        bytes: body,
      );
    } on TimeoutException {
      if (!await _confirmed(kind, property, id, payload)) rethrow;
    } on http.ClientException {
      if (!await _confirmed(kind, property, id, payload)) rethrow;
    }
  }

  @override
  Future<void> putRevision(Revision revision) async => _putJson(
    'revision',
    'revisionId',
    revision.id,
    await _worker.encode(revision),
    {'documentId': revision.notebook.id},
  );
  @override
  Future<List<NoteFolder>> listFolders() async {
    final result = <String, NoteFolder>{};
    for (final file in await _list(_property('kind', 'folder'))) {
      final folder = NoteFolder.fromJson(
        jsonDecode(utf8.decode(await _read(file))) as Map<String, dynamic>,
      );
      final properties = file['appProperties'] as Map<String, dynamic>;
      if (folder.id != properties['folderId']) {
        throw const FormatException('Carpeta remota inválida');
      }
      final old = result[folder.id];
      if (old == null ||
          folder.updatedAt.isAfter(old.updatedAt) ||
          (folder.updatedAt == old.updatedAt &&
              jsonEncode(folder.toJson()).compareTo(jsonEncode(old.toJson())) >
                  0)) {
        result[folder.id] = folder;
      }
    }
    return result.values.toList();
  }

  @override
  Future<void> putFolder(NoteFolder folder) async {
    final payload = jsonEncode(folder.toJson());
    final id = await compute(_sha, Uint8List.fromList(utf8.encode(payload)));
    await _putJson('folder', 'folderOpId', id, payload, {
      'folderId': folder.id,
    });
  }

  String _assetKey(Map<String, dynamic> file) =>
      '${file['id']}:${file['md5Checksum']}:${file['modifiedTime']}';
  Future<Uint8List?> _findAsset(String id) async {
    for (final file in await _find('asset', 'assetId', id)) {
      final key = _assetKey(file);
      final cached = file['md5Checksum'] == null ? null : _verifiedAssets[key];
      if (cached != null) return cached;
      final bytes = await _read(file);
      if (await compute(_sha, bytes) == id) {
        if (file['md5Checksum'] != null) {
          _verifiedAssets.clear();
          _verifiedAssets[key] = bytes;
        }
        return bytes;
      }
    }
    return null;
  }

  @override
  Future<bool> hasAsset(String assetId) async =>
      await _findAsset(assetId) != null;
  @override
  Future<Uint8List> readAsset(String assetId) async {
    final bytes = await _findAsset(assetId);
    if (bytes == null) {
      throw const FormatException('Recurso Drive ausente o dañado');
    }
    return bytes;
  }

  int _received(http.Response response, int total) {
    final range = response.headers['range'];
    if (range == null) return 0;
    final match = RegExp(r'^bytes=0-(\d+)$').firstMatch(range);
    if (match == null) throw const FormatException('Rango Drive inválido');
    final offset = int.parse(match[1]!) + 1;
    if (offset > total) throw const FormatException('Rango fuera del recurso');
    return offset;
  }

  Future<void> _finishAsset(
    String id,
    Uint8List bytes,
    http.Response response,
  ) async {
    final metadata = jsonDecode(response.body) as Map<String, dynamic>;
    if (metadata['md5Checksum'] != null) {
      if (metadata['md5Checksum'] != await compute(_md5, bytes)) {
        throw const FormatException('Drive confirmó un recurso diferente');
      }
    } else {
      final returned = await _read(metadata);
      if (await compute(_sha, returned) != id) {
        throw const FormatException('Drive confirmó un recurso diferente');
      }
    }
    await sessions.delete(accountId, id);
  }

  @override
  Future<void> putAsset(String assetId, Uint8List bytes) async {
    if (await compute(_sha, bytes) != assetId) {
      throw const FormatException('Hash de recurso inválido');
    }
    if (await hasAsset(assetId)) {
      await sessions.delete(accountId, assetId);
      return;
    }
    Uri? url = await sessions.read(accountId, assetId);
    var offset = 0;
    if (url != null) {
      final response = await _http.request(
        'PUT',
        url,
        headers: {
          'Content-Range': 'bytes */${bytes.length}',
          'Content-Length': '0',
        },
        accepted: {200, 201, 308, 404, 410},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        await _finishAsset(assetId, bytes, response);
        return;
      }
      if (response.statusCode == 404 || response.statusCode == 410) {
        await sessions.delete(accountId, assetId);
        url = null;
      } else {
        offset = _received(response, bytes.length);
      }
    }
    if (url == null) {
      final root = await _rootId();
      final response = await _http.request(
        'POST',
        _uri('/upload/drive/v3/files', {
          'uploadType': 'resumable',
          'fields': 'id,md5Checksum',
        }),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'X-Upload-Content-Type': 'application/octet-stream',
          'X-Upload-Content-Length': bytes.length.toString(),
        },
        body: jsonEncode({
          'name': 'asset-$assetId',
          'parents': [root],
          'appProperties': {
            'application': 'nala-v1',
            'kind': 'asset',
            'assetId': assetId,
          },
        }),
      );
      final location = response.headers['location'];
      if (location == null) {
        throw const FormatException('Drive no devolvió una sesión de subida');
      }
      url = Uri.parse(location);
      if (url.scheme != 'https' ||
          !{
            'www.googleapis.com',
            'content.googleapis.com',
          }.contains(url.host)) {
        throw const FormatException('Sesión de subida inválida');
      }
      await sessions.write(accountId, assetId, url);
    }
    while (offset < bytes.length) {
      final end = min(offset + 256 * 1024, bytes.length);
      final response = await _http.request(
        'PUT',
        url,
        headers: {
          'Content-Type': 'application/octet-stream',
          'Content-Range': 'bytes $offset-${end - 1}/${bytes.length}',
        },
        bytes: Uint8List.sublistView(bytes, offset, end),
        accepted: {200, 201, 308},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        await _finishAsset(assetId, bytes, response);
        return;
      }
      final received = _received(response, bytes.length);
      if (received <= offset) {
        throw const FormatException('Drive no confirmó avance de la subida');
      }
      offset = received;
    }
    throw const FormatException('Drive no confirmó el recurso completo');
  }

  @override
  void close() {
    _http.close();
    _revisions.clear();
    _verifiedAssets.clear();
  }
}
