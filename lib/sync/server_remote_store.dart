import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../document/asset_store.dart';
import '../document/document_worker.dart';
import '../document/folders.dart';
import '../document/notebook_codec.dart';
import '../document/revision.dart';
import 'remote_store.dart';

const _timeout = Duration(seconds: 30);
const _chunkSize = 4 * 1024 * 1024;
final _assetId = RegExp(r'^[a-f0-9]{64}$');
final _contentRange = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$');

class ServerRemoteStore
    implements
        RemoteStore,
        IncrementalRemoteStore,
        FolderBatchRemoteStore,
        FileTransferRemoteStore {
  ServerRemoteStore({
    required Uri baseUrl,
    required String token,
    required String serverId,
    required String cursorPath,
    http.Client? client,
    bool allowInsecureLoopback = false,
  }) : _transport = _ServerHttp(baseUrl, token, client, allowInsecureLoopback),
       _serverId = serverId,
       _cursor = File(cursorPath),
       _downloadDirectory = p.join(
         '$cursorPath.downloads',
         sha256.convert(utf8.encode(serverId)).toString(),
       );

  final _ServerHttp _transport;
  final String _serverId;
  final File _cursor;
  final String _downloadDirectory;
  final _downloads = <String, Future<void>>{};

  static Future<String> identify({
    required Uri baseUrl,
    required String token,
    http.Client? client,
    bool allowInsecureLoopback = false,
  }) async {
    final transport = _ServerHttp(
      baseUrl,
      token,
      client,
      allowInsecureLoopback,
    );
    try {
      return await transport.identify();
    } finally {
      if (client == null) transport.close();
    }
  }

  Future<int> _readCursor() async {
    if (!await _cursor.exists()) return 0;
    try {
      final saved = _jsonObject(await _cursor.readAsString());
      final after = saved['after'];
      if (saved['server'] == _serverId && after is int && after >= 0) {
        return after;
      }
    } on FormatException {
      // Replaying accepted revisions is safe if the cursor file was damaged.
    }
    return 0;
  }

  Future<void> _saveCursor(int after) async {
    await _cursor.parent.create(recursive: true);
    final staged = File('${_cursor.path}.${const Uuid().v4()}.tmp');
    try {
      await staged.writeAsString(
        jsonEncode({'server': _serverId, 'after': after}),
        flush: true,
      );
      await staged.rename(_cursor.path);
    } finally {
      if (await staged.exists()) await staged.delete();
    }
  }

  Stream<_RevisionPage> _pages(int after) async* {
    while (true) {
      final response = await _transport.send(
        'GET',
        ['revisions'],
        serverId: _serverId,
        query: {'after': '$after', 'limit': '50'},
      );
      final page = await compute(_decodePage, (await _body(response), after));
      yield page;
      if (!page.more) return;
      after = page.next;
    }
  }

  @override
  Future<void> pullRevisions(Future<void> Function(Revision) accept) async {
    var after = await _readCursor();
    await for (final page in _pages(after)) {
      for (final revision in page.items) {
        await accept(revision);
      }
      if (page.next != after) {
        await _saveCursor(page.next);
        after = page.next;
      }
    }
  }

  @override
  Future<List<Revision>> listRevisions() async => [
    await for (final page in _pages(0)) ...page.items,
  ];

  @override
  Future<void> putRevision(Revision revision) async {
    await _putJson('revisions', await const DocumentWorker().encode(revision));
  }

  @override
  Future<List<NoteFolder>> listFolders() async {
    final response = await _transport.send('GET', [
      'folders',
    ], serverId: _serverId);
    final items = _jsonObject(utf8.decode(await _body(response)))['items'];
    if (items is! List) {
      throw const FormatException('Lista de carpetas inválida.');
    }
    return [
      for (final item in items)
        NoteFolder.fromJson(item as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> putFolder(NoteFolder folder) =>
      _putJson('folders', jsonEncode(folder.toJson()));

  @override
  Future<void> putFolders(List<NoteFolder> folders) => _putJson(
    'folders',
    jsonEncode({'items': folders.map((folder) => folder.toJson()).toList()}),
  );

  Future<void> _putJson(String route, String body) async {
    final response = await _transport.send(
      'PUT',
      [route],
      serverId: _serverId,
      body: body,
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      accepted: {200, 201, 204},
    );
    await response.stream.timeout(_timeout).drain<void>();
  }

  List<String> _assetPath(String id) {
    if (!_assetId.hasMatch(id)) {
      throw const FormatException('Hash de recurso inválido.');
    }
    return ['assets', id];
  }

  Future<({bool complete, int offset, int? declaredLength})> _assetStatus(
    List<String> path,
  ) async {
    final response = await _transport.send(
      'HEAD',
      path,
      serverId: _serverId,
      accepted: {200, 404},
    );
    await response.stream.timeout(_timeout).drain<void>();
    final complete = response.statusCode == 200;
    final offset = _offset(response);
    final header = response.headers['upload-length'];
    final declaredLength = header == null ? null : int.tryParse(header);
    if (header != null &&
        (declaredLength == null ||
            declaredLength < offset ||
            (complete && declaredLength != offset))) {
      throw const FormatException('El servidor devolvió un tamaño inválido.');
    }
    return (complete: complete, offset: offset, declaredLength: declaredLength);
  }

  @override
  Future<bool> hasAsset(String assetId) async =>
      (await _assetStatus(_assetPath(assetId))).complete;

  int _offset(http.StreamedResponse response) {
    final offset = int.tryParse(response.headers['upload-offset'] ?? '');
    if (offset == null || offset < 0) {
      throw const FormatException('El servidor devolvió un offset inválido.');
    }
    return offset;
  }

  @override
  Future<void> putAsset(String assetId, Uint8List bytes) async {
    final path = _assetPath(assetId);
    if (await compute(_sha, bytes) != assetId) {
      throw const FormatException('Hash de recurso inválido.');
    }
    await _uploadAsset(
      path,
      bytes.length,
      (start, end) => Uint8List.sublistView(bytes, start, end),
    );
  }

  @override
  Future<void> putVerifiedAssetFile(String assetId, File file) async {
    final path = _assetPath(assetId);
    final source = await file.open();
    try {
      await _uploadAsset(path, await source.length(), (start, end) async {
        await source.setPosition(start);
        return source.read(end - start);
      });
    } finally {
      await source.close();
    }
  }

  Future<void> _uploadAsset(
    List<String> path,
    int total,
    FutureOr<Uint8List> Function(int start, int end) readChunk,
  ) async {
    final status = await _assetStatus(path);
    var offset = status.offset;
    if (!status.complete &&
        status.declaredLength != null &&
        status.declaredLength != total) {
      // A zero-offset block replaces the incompatible staged transfer.
      offset = 0;
    }
    if (offset > total ||
        (status.complete && offset != total) ||
        (!status.complete && offset == total && total != 0)) {
      throw const FormatException('El servidor devolvió un tamaño inválido.');
    }
    if (status.complete) return;

    var conflicts = 0;
    do {
      final end = min(offset + _chunkSize, total);
      final chunk = await readChunk(offset, end);
      if (chunk.length != end - offset) {
        throw const FormatException('El archivo de origen cambió de tamaño.');
      }
      final response = await _transport.send(
        'PATCH',
        path,
        serverId: _serverId,
        headers: {
          'Content-Type': 'application/octet-stream',
          'Upload-Offset': '$offset',
          'Upload-Length': '$total',
        },
        bytes: chunk,
        accepted: {204, 409},
      );
      await response.stream.timeout(_timeout).drain<void>();
      final received = _offset(response);
      if (response.statusCode == 409) {
        if (received > total || ++conflicts > 3) {
          throw const HttpException('La subida no pudo recuperar su avance.');
        }
      } else {
        if (received != end) {
          throw const FormatException(
            'El servidor confirmó un bloque inválido.',
          );
        }
        conflicts = 0;
      }
      offset = received;
    } while (offset < total);
  }

  @override
  Future<Uint8List> readAsset(String assetId) =>
      _consumeDownload(assetId, (file) => file.readAsBytes());

  @override
  Future<void> readAssetFile(
    String assetId,
    Future<void> Function(File) accept,
  ) => _consumeDownload(assetId, accept);

  Future<T> _consumeDownload<T>(
    String assetId,
    Future<T> Function(File) accept,
  ) async {
    final path = _assetPath(assetId);
    var active = _downloads[assetId];
    while (active != null) {
      await active;
      active = _downloads[assetId];
    }
    final completed = Completer<void>();
    _downloads[assetId] = completed.future;
    try {
      return await _downloadAsset(assetId, path, accept);
    } finally {
      _downloads.remove(assetId);
      completed.complete();
    }
  }

  Future<T> _downloadAsset<T>(
    String id,
    List<String> path,
    Future<T> Function(File) accept,
  ) async {
    final partial = File(p.join(_downloadDirectory, id));
    final offset = await partial.exists() ? await partial.length() : 0;
    final response = await _transport.send(
      'GET',
      path,
      serverId: _serverId,
      headers: {
        'Accept-Encoding': 'identity',
        if (offset > 0) 'Range': 'bytes=$offset-',
      },
      accepted: offset == 0 ? {200} : {200, 206, 416},
    );
    if (response.statusCode == 416) {
      await response.stream.timeout(_timeout).drain<void>();
      // All bytes may have reached the disk before the previous request ended.
      return _finishDownload(partial, id, accept);
    }

    var length = response.contentLength;
    final append = response.statusCode == 206;
    if (append) {
      final range = _contentRange.firstMatch(
        response.headers['content-range'] ?? '',
      );
      final start = int.tryParse(range?[1] ?? '');
      final end = int.tryParse(range?[2] ?? '');
      final total = int.tryParse(range?[3] ?? '');
      if (start != offset ||
          end == null ||
          total == null ||
          end != total - 1 ||
          end < offset ||
          (length != null && length != total - offset)) {
        await response.stream.listen(null).cancel();
        throw const FormatException('El servidor devolvió un rango inválido.');
      }
      length = total - offset;
    }

    final RandomAccessFile file;
    try {
      await partial.parent.create(recursive: true);
      file = await partial.open(
        mode: append ? FileMode.append : FileMode.write,
      );
    } catch (_) {
      await response.stream.listen(null).cancel();
      rethrow;
    }
    var received = 0;
    try {
      await for (final chunk in response.stream.timeout(_timeout)) {
        received += chunk.length;
        if (length != null && received > length) {
          throw const FormatException(
            'El servidor envió un recurso demasiado largo.',
          );
        }
        await file.writeFrom(chunk);
      }
    } finally {
      try {
        await file.flush();
      } finally {
        await file.close();
      }
    }
    if (length != null && received != length) {
      throw const HttpException('La descarga del recurso quedó incompleta.');
    }
    return _finishDownload(partial, id, accept);
  }

  Future<T> _finishDownload<T>(
    File partial,
    String id,
    Future<T> Function(File) accept,
  ) async {
    try {
      if (await assetFileHash(partial) != id) {
        throw const FormatException(
          'El recurso descargado no coincide con su hash.',
        );
      }
      return await accept(partial);
    } finally {
      await partial.delete();
    }
  }

  @override
  void close() => _transport.close();
}

typedef _RevisionPage = ({List<Revision> items, int next, bool more});

_RevisionPage _decodePage((Uint8List, int) request) {
  final (bytes, after) = request;
  final data = _jsonObject(utf8.decode(bytes));
  final items = data['items'], next = data['next'], more = data['more'];
  if (items is! List ||
      next is! int ||
      more is! bool ||
      (items.isEmpty ? (next != after || more) : next <= after)) {
    throw const FormatException('Página de revisiones inválida.');
  }
  return (
    items: [
      for (final item in items) NotebookCodec.decodeRevision(jsonEncode(item)),
    ],
    next: next,
    more: more,
  );
}

String _sha(Uint8List bytes) => sha256.convert(bytes).toString();

Future<Uint8List> _body(http.StreamedResponse response) =>
    http.ByteStream(response.stream.timeout(_timeout)).toBytes();

Map<String, dynamic> _jsonObject(String text) {
  final value = jsonDecode(text);
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Respuesta del servidor inválida.');
  }
  return value;
}

class _ServerHttp {
  _ServerHttp(Uri base, this._token, http.Client? client, bool allowLoopback)
    : _base = _validate(base, allowLoopback),
      _client = client ?? http.Client();

  final Uri _base;
  final String _token;
  final http.Client _client;
  bool _closed = false;

  static Uri _validate(Uri base, bool allowLoopback) {
    final secure = base.scheme == 'https';
    final loopback =
        allowLoopback &&
        base.scheme == 'http' &&
        (base.host == 'localhost' ||
            InternetAddress.tryParse(base.host)?.isLoopback == true);
    if ((!secure && !loopback) ||
        base.host.isEmpty ||
        base.authority.contains('@') ||
        base.hasQuery ||
        base.hasFragment) {
      throw const FormatException('Ingresá una URL HTTPS válida del servidor.');
    }
    return base;
  }

  Future<String> identify() async {
    final response = await send('GET', ['identity']);
    final id = _jsonObject(utf8.decode(await _body(response)))['id'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('Identidad de servidor inválida.');
    }
    return id;
  }

  Future<http.StreamedResponse> send(
    String method,
    List<String> route, {
    String? serverId,
    Map<String, String>? query,
    Map<String, String> headers = const {},
    String? body,
    Uint8List? bytes,
    Set<int> accepted = const {200},
  }) async {
    if (_closed) throw StateError('Se cerró la conexión al servidor.');
    final basePath = _base.pathSegments.toList();
    while (basePath.isNotEmpty && basePath.last.isEmpty) {
      basePath.removeLast();
    }
    final url = _base.replace(
      pathSegments: [...basePath, 'v1', ...route],
      queryParameters: query,
    );
    final abort = Completer<void>();
    final request =
        http.AbortableRequest(method, url, abortTrigger: abort.future)
          ..followRedirects = false
          ..headers.addAll({
            'Authorization': 'Bearer $_token',
            'X-Nala-Server': ?serverId,
            ...headers,
          });
    if (body != null) request.body = body;
    if (bytes != null) request.bodyBytes = bytes;
    final response = await _client
        .send(request)
        .timeout(
          _timeout,
          onTimeout: () {
            abort.complete();
            throw TimeoutException('El servidor no respondió a tiempo.');
          },
        );
    final status = response.statusCode;
    if (status == 409 && serverId != null) {
      if (accepted.contains(status) &&
          response.headers.containsKey('upload-offset')) {
        return response;
      }
      final bytes = await _body(response);
      // HEAD has no body even when the server replies with a conflict.
      if (method == 'HEAD') {
        if (await identify() != serverId) throw const RemoteServerChanged();
      } else if (_serverChanged(bytes)) {
        throw const RemoteServerChanged();
      }
      throw const HttpException('El servidor rechazó un registro (409).');
    }
    if (accepted.contains(status)) return response;
    await response.stream.listen(null).cancel();

    if (status == 401 || status == 403) throw const RemoteSignInRequired();
    if (status == 429 || status >= 500) {
      throw RemoteRetryLater(_retryDelay(response.headers['retry-after']));
    }
    throw HttpException(
      'El servidor no pudo completar la operación ($status).',
    );
  }

  bool _serverChanged(Uint8List bytes) {
    try {
      return _jsonObject(utf8.decode(bytes))['error'] == 'server_changed';
    } on FormatException {
      return false;
    }
  }

  Duration _retryDelay(String? header) {
    if (header != null) {
      final seconds = int.tryParse(header);
      if (seconds != null) return Duration(seconds: max(0, seconds));
      try {
        final delay = HttpDate.parse(header).difference(DateTime.now().toUtc());
        return delay.isNegative ? Duration.zero : delay;
      } on FormatException {
        // Fall back to a short delay if no Retry-After value can be read.
      }
    }
    return Duration(milliseconds: 2000 + Random().nextInt(1000));
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _client.close();
  }
}
