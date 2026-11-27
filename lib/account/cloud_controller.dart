import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../bootstrap.dart';
import '../document/sqlite_notebook_repository.dart';
import '../sync/remote_store.dart';
import '../sync/server_remote_store.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_state.dart';
import 'token_store.dart';

class LocalCatalog {
  const LocalCatalog._(this.id, this.root, this.label);

  final String? id;
  final String root, label;
}

class ServerDestination {
  const ServerDestination(this.url, this.id);

  final Uri url;
  final String id;

  String get _scope =>
      sha256.convert(utf8.encode(jsonEncode([url.toString(), id]))).toString();
}

class ServerConnectionProbe {
  const ServerConnectionProbe._(
    this.destination,
    this.isNewDestination,
    this.requiresUpload,
    this._token,
  );

  final ServerDestination destination;
  final bool isNewDestination, requiresUpload;
  final String _token;
}

class _SavedConnection {
  const _SavedConnection(
    this.destination, {
    this.enabled = true,
    this.credentialId,
  });

  final ServerDestination destination;
  final bool enabled;
  final String? credentialId;

  factory _SavedConnection.fromJson(Map<String, dynamic> json) =>
      _SavedConnection(
        ServerDestination(
          Uri.parse(json['url'] as String),
          json['id'] as String,
        ),
        enabled: json['enabled'] as bool,
        credentialId: json['credentialId'] as String?,
      );

  Map<String, Object?> toJson() => {
    'url': destination.url.toString(),
    'id': destination.id,
    'enabled': enabled,
    'credentialId': ?credentialId,
  };
}

class CloudController extends ChangeNotifier {
  CloudController._(
    this.root,
    this.catalogs,
    this._activeCatalog,
    this._tokenStore,
    this._clientFactory,
    this._autoStart,
    this._allowInsecureLoopback,
  );

  final String root;
  final List<LocalCatalog> catalogs;
  LocalCatalog _activeCatalog;
  LocalCatalog get activeCatalog => _activeCatalog;
  final TokenStore _tokenStore;
  final http.Client Function() _clientFactory;
  final bool _autoStart, _allowInsecureLoopback;
  late AppServices services;
  _SavedConnection? _saved;
  ServerConnectionProbe? _pending;
  http.Client? _probeClient;
  final _remoteNotebookChanges = StreamController<Set<String>>.broadcast();
  StreamSubscription<RemoteChanges>? _remoteChangesSubscription;
  Future<void>? _operation, _closing;
  bool _closed = false, _needsCredentials = false;
  int _probeEpoch = 0;
  String? message;

  bool get busy => _operation != null;
  bool get verifying => _probeClient != null;
  bool get connected => services.sync != null;
  DateTime? get lastSuccessfulSync => services.sync?.lastSuccessfulSync;
  ServerDestination? get destination => _saved?.destination;
  ServerConnectionProbe? get pendingConnection => _pending;
  SyncStatus get status =>
      services.sync?.status ??
      SyncStatus(
        _needsCredentials ? SyncPhase.needsSignIn : SyncPhase.localOnly,
      );
  Stream<Set<String>> get remoteNotebookChanges =>
      _remoteNotebookChanges.stream;
  File get _connectionFile =>
      File(p.join(activeCatalog.root, 'server-connection.json'));
  SqliteNotebookRepository get _repository =>
      services.repository as SqliteNotebookRepository;

  static Future<CloudController> open(
    String root, {
    TokenStore? tokenStore,
    http.Client Function()? clientFactory,
    bool autoStart = true,
    bool allowInsecureLoopback = false,
  }) async {
    await Directory(root).create(recursive: true);
    final selection = await _readJson(
      File(p.join(root, 'active-library.json')),
    );
    final legacyFile = File(p.join(root, 'active-account.json'));
    final legacy = selection == null
        ? await _readJson(legacyFile)
        : await _readJson(legacyFile).catchError((Object _) => null);
    final priorId = legacy?['id'];
    if (selection == null && legacy != null && priorId is! String ||
        selection != null && !selection.containsKey('catalog')) {
      throw const FormatException('Selección de biblioteca inválida.');
    }
    final legacyId = priorId is! String
        ? null
        : sha256.convert(utf8.encode(priorId)).toString();
    final selectedId = selection == null
        ? legacyId
        : selection['catalog'] as String?;
    final catalogs = await _findCatalogs(
      root,
      selectedId,
      legacyId,
      legacy?['email'],
    );
    final active = catalogs
        .where((catalog) => catalog.id == selectedId)
        .firstOrNull;
    if (active == null) {
      throw FileSystemException(
        'No se encontró la biblioteca seleccionada',
        root,
      );
    }
    final cloud = CloudController._(
      root,
      List.unmodifiable(catalogs),
      active,
      tokenStore ?? const SecureTokenStore(),
      clientFactory ?? http.Client.new,
      autoStart,
      allowInsecureLoopback,
    );
    cloud.services = await AppServices.open(active.root);
    await cloud._restoreConnection();
    return cloud;
  }

  static Future<List<LocalCatalog>> _findCatalogs(
    String root,
    String? selectedId,
    String? legacyId,
    Object? legacyLabel,
  ) async {
    final catalogs = <LocalCatalog>[];
    if (selectedId == null || await _catalogExists(root)) {
      catalogs.add(
        LocalCatalog._(null, root, 'Biblioteca de este dispositivo'),
      );
    }
    final accounts = Directory(p.join(root, 'accounts'));
    if (!await accounts.exists()) return catalogs;

    final archived = <LocalCatalog>[];
    final partitionId = RegExp(r'^[a-f0-9]{64}$');
    await for (final directory in accounts.list(followLinks: false)) {
      final id = p.basename(directory.path);
      if (directory is! Directory ||
          !partitionId.hasMatch(id) ||
          !await _catalogExists(directory.path)) {
        continue;
      }
      final label =
          id == legacyId && legacyLabel is String && legacyLabel.isNotEmpty
          ? legacyLabel
          : 'Biblioteca local ${id.substring(0, 8)}';
      archived.add(LocalCatalog._(id, directory.path, label));
    }
    archived.sort((a, b) => a.label.compareTo(b.label));
    return catalogs..addAll(archived);
  }

  static Future<bool> _catalogExists(String root) =>
      File(p.join(root, 'local', 'notes.db')).exists();

  static Future<Map<String, dynamic>?> _readJson(File file) async =>
      await file.exists()
      ? jsonDecode(await file.readAsString()) as Map<String, dynamic>
      : null;

  static Future<void> _writeJson(File file, Map<String, Object?> value) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    await temporary.rename(file.path);
  }

  void _changed() {
    if (!_closed) notifyListeners();
  }

  void _refreshChangedContent(RemoteChanges changes) {
    if (_closed) return;
    if (changes.notebookIds.isNotEmpty) {
      _remoteNotebookChanges.add(changes.notebookIds);
    }
    unawaited(services.library.refresh().catchError((Object _) {}));
  }

  void _attach(ServerDestination destination, String token) {
    services.attachSync(
      ServerRemoteStore(
        baseUrl: destination.url,
        token: token,
        serverId: destination.id,
        cursorPath: p.join(
          services.root,
          'server-sync',
          '${destination._scope}.json',
        ),
        client: _clientFactory(),
        allowInsecureLoopback: _allowInsecureLoopback,
      ),
      autoStart: false,
    );
    _needsCredentials = false;
    final sync = services.sync!;
    _remoteChangesSubscription = sync.remoteChanges.listen(
      _refreshChangedContent,
    );
    sync.addListener(_changed);
    sync.notifyPending();
    if (_autoStart) services.coordinator!.start();
  }

  Future<void> _stop() async {
    services.sync?.removeListener(_changed);
    await _remoteChangesSubscription?.cancel();
    _remoteChangesSubscription = null;
    await services.stopSync();
  }

  Future<void> _restoreConnection() async {
    _saved = null;
    _needsCredentials = false;
    try {
      final config = await _readJson(_connectionFile);
      if (config == null) return;
      final saved = _saved = _SavedConnection.fromJson(config);
      if (!saved.enabled || _closed) return;

      _needsCredentials = true;
      final key = _credentialKey(saved);
      if (key == null) return;
      final token = await _tokenStore.read(key);
      if (token != null && !_closed) _attach(saved.destination, token);
    } catch (_) {
      message =
          'No se pudo restaurar la conexión. Tus apuntes siguen guardados acá.';
    }
  }

  Future<void> _run(Future<void> Function() action, {required String failure}) {
    if (_closed || busy) return _operation ?? Future.value();
    message = null;
    final operation = _operation = action()
        .catchError((Object _) {
          message = failure;
        })
        .whenComplete(() {
          _operation = null;
          _changed();
        });
    _changed();
    return operation;
  }

  Future<void> synchronize() {
    if (busy || status.phase == SyncPhase.needsSignIn) return Future.value();
    return services.sync?.synchronize() ?? Future.value();
  }

  Future<void> probe(String url, String token) => _run(
    () async {
      final epoch = ++_probeEpoch;
      _pending = null;
      final rawUrl = url.trim().replaceFirst(RegExp(r'/$'), '');
      final baseUrl = Uri.tryParse(rawUrl);
      final credential = token.trim();
      if (baseUrl == null ||
          baseUrl.host.isEmpty ||
          (baseUrl.scheme != 'https' && !_allowInsecureLoopback) ||
          baseUrl.hasQuery ||
          baseUrl.hasFragment ||
          baseUrl.authority.contains('@')) {
        message = 'Ingresá una URL HTTPS válida para el servidor.';
        return;
      }
      if (credential.isEmpty ||
          RegExp(r'[\x00-\x20\x7f]').hasMatch(credential)) {
        message = 'Ingresá una credencial válida para este dispositivo.';
        return;
      }

      // Quiesce the previous destination before beginning a new handshake.
      await _stop();
      final previous = _saved;
      if (previous != null && previous.enabled) {
        final paused = _SavedConnection(
          previous.destination,
          enabled: false,
          credentialId: previous.credentialId,
        );
        await _writeJson(_connectionFile, paused.toJson());
        _saved = paused;
      }
      _needsCredentials = previous != null;
      if (_closed || epoch != _probeEpoch) return;

      final client = _probeClient = _clientFactory();
      _changed();
      try {
        final id = await ServerRemoteStore.identify(
          baseUrl: baseUrl,
          token: credential,
          client: client,
          allowInsecureLoopback: _allowInsecureLoopback,
        );
        if (_closed || epoch != _probeEpoch) return;
        final target = ServerDestination(baseUrl, id);
        final current = previous?.destination;
        final newDestination =
            current?.id != target.id || current?.url != target.url;
        final hasLocalLibrary =
            newDestination && await _repository.hasSyncContent();
        if (_closed || epoch != _probeEpoch) return;
        _pending = ServerConnectionProbe._(
          target,
          newDestination,
          hasLocalLibrary,
          credential,
        );
      } on RemoteSignInRequired {
        if (!_closed && epoch == _probeEpoch) {
          message = 'El servidor rechazó la credencial de este dispositivo.';
        }
      } catch (_) {
        if (!_closed && epoch == _probeEpoch) {
          message =
              'No se pudo verificar el servidor. Revisá la URL y la conexión.';
        }
      } finally {
        if (identical(_probeClient, client)) {
          _probeClient = null;
          client.close();
        }
      }
    },
    failure:
        'No se pudo preparar la conexión. Tus apuntes siguen guardados acá.',
  );

  Future<void> confirmConnection({bool remember = true}) {
    final pending = _pending;
    if (pending == null) return Future.value();
    return _run(
      () async {
        // The current database remains the source. Freeze its retained revisions
        // before exposing the new destination to the synchronization coordinator.
        if (pending.isNewDestination) await _repository.queueAllForUpload();

        final oldKey = _credentialKey(_saved);
        var saved = _SavedConnection(pending.destination);
        if (remember) {
          final remembered = _SavedConnection(
            pending.destination,
            credentialId: const Uuid().v4(),
          );
          final secureKey = _credentialKey(remembered)!;
          try {
            await _tokenStore.write(secureKey, pending._token);
            saved = remembered;
          } catch (_) {
            await _forgetCredential(secureKey);
            message =
                'Conectado por esta sesión. El llavero del sistema no está disponible.';
          }
        }
        try {
          await _writeJson(_connectionFile, saved.toJson());
        } catch (_) {
          await _forgetCredential(_credentialKey(saved));
          rethrow;
        }
        _saved = saved;
        _pending = null;
        if (!_closed) _attach(saved.destination, pending._token);
        await _forgetCredential(oldKey);
        if (!remember) message = 'Conectado por esta sesión.';
      },
      failure:
          'No se pudo guardar la conexión. Tus apuntes siguen guardados acá.',
    );
  }

  Future<void> cancelConnection() async {
    _probeEpoch++;
    final client = _probeClient;
    _probeClient = null;
    client?.close();
    final cancelled = _pending != null || client != null;
    _pending = null;
    if (cancelled) {
      message = 'Conexión cancelada. Tus apuntes siguen guardados acá.';
      _changed();
    }
  }

  String? _credentialKey(_SavedConnection? saved) {
    final id = saved?.credentialId;
    if (id == null) return null;
    // A config file copied to another catalog or edited to use a different
    // endpoint cannot recover the credential for the previously trusted one.
    final scope = jsonEncode([
      p.normalize(p.absolute(activeCatalog.root)),
      saved!.destination._scope,
      id,
    ]);
    return 'nala-server-${sha256.convert(utf8.encode(scope))}';
  }

  Future<bool> _forgetCredential(String? key) async {
    if (key == null) return true;
    try {
      await _tokenStore.delete(key);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect() => _run(
    () async {
      await _stop();
      final saved = _saved;
      if (saved != null) {
        final offline = _SavedConnection(saved.destination, enabled: false);
        await _writeJson(_connectionFile, offline.toJson());
        _saved = offline;
        if (!await _forgetCredential(_credentialKey(saved))) {
          message =
              'El servidor quedó desconectado. No se pudo borrar la credencial del llavero.';
        }
      }
      _needsCredentials = false;
      _pending = null;
    },
    failure:
        'No se pudo guardar la desconexión. La sincronización está detenida en esta sesión.',
  );

  Future<void> selectCatalog(LocalCatalog catalog) {
    if (catalog == activeCatalog || !catalogs.contains(catalog)) {
      return Future.value();
    }
    return _run(() async {
      _pending = null;
      await _stop();
      final replacement = await AppServices.open(catalog.root);
      try {
        await _writeJson(File(p.join(root, 'active-library.json')), {
          'catalog': catalog.id,
        });
      } catch (_) {
        await replacement.close();
        rethrow;
      }
      final previous = services;
      services = replacement;
      _activeCatalog = catalog;
      await _restoreConnection();
      _changed();
      await previous.close();
    }, failure: 'No se pudo abrir la biblioteca seleccionada.');
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    await cancelConnection();
    await _operation;
    await _stop();
    await services.close();
    unawaited(_remoteNotebookChanges.close());
    super.dispose();
  }
}
