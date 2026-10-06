import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../bootstrap.dart';
import '../document/sqlite_notebook_repository.dart';
import '../document/folders.dart';
import '../sync/remote_store.dart';
import '../sync/drive_remote_store.dart';
import '../sync/upload_session_store.dart';
import '../sync/sync_state.dart';
import 'auth_service.dart';

typedef RemoteFactory =
    RemoteStore Function(GoogleAccount account, String root);

class CloudController extends ChangeNotifier {
  CloudController._(this.root, this.auth, this.remoteFactory, this.autoStart);
  final String root;
  final AuthService? auth;
  final RemoteFactory remoteFactory;
  final bool autoStart;
  late AppServices services;
  GoogleAccount? account;
  String? message;
  bool busy = false, _closed = false;
  int _epoch = 0;
  Future<void>? _operation, _closing;
  bool get configured => auth != null;
  bool get connected => services.sync != null;
  SyncStatus get status =>
      services.sync?.status ?? const SyncStatus(SyncPhase.localOnly);
  String _accountRoot(GoogleAccount account) => p.join(
    root,
    'accounts',
    sha256.convert(utf8.encode(account.id)).toString(),
  );
  File get _selection => File(p.join(root, 'active-account.json'));

  static Future<CloudController> open(
    String root, {
    AuthService? auth,
    RemoteFactory? remoteFactory,
    bool autoStart = true,
  }) async {
    final cloud = CloudController._(
      root,
      auth,
      remoteFactory ??
          ((account, partition) => DriveRemoteStore(
            auth: auth!,
            client: http.Client(),
            accountId: account.id,
            sessions: FileUploadSessionStore(
              p.join(partition, 'upload-sessions'),
            ),
          )),
      autoStart,
    );
    await Directory(root).create(recursive: true);
    var reconnect = true;
    if (await cloud._selection.exists()) {
      // Never fall back silently to an empty library if the saved catalog fails.
      final selection =
          jsonDecode(await cloud._selection.readAsString())
              as Map<String, dynamic>;
      cloud.account = GoogleAccount.fromJson(selection);
      reconnect = selection['connected'] != false;
    }
    cloud.services = await AppServices.open(
      cloud.account == null ? root : cloud._accountRoot(cloud.account!),
    );
    GoogleAccount? restored;
    try {
      if (reconnect) restored = await auth?.restore();
    } catch (_) {
      cloud.message =
          'No se pudo restaurar Drive. Tus apuntes están disponibles sin conexión.';
    }
    if (restored != null && restored.id == cloud.account?.id) cloud._attach();
    return cloud;
  }

  void _changed() {
    if (!_closed) notifyListeners();
  }

  void _syncChanged() {
    _changed();
    if (status.phase == SyncPhase.synced) {
      // An open editor keeps its in-memory branch; downloaded heads are shown
      // after returning to the library, without overwriting handwriting.
      unawaited(services.library.refresh().catchError((Object _) {}));
    }
  }

  void _attach() {
    services.attachSync(
      remoteFactory(account!, services.root),
      autoStart: false,
    );
    services.sync!.addListener(_syncChanged);
    if (autoStart) services.coordinator!.start();
  }

  Future<void> _stop() async {
    services.sync?.removeListener(_syncChanged);
    await services.stopSync();
  }

  Future<void> synchronize() => services.sync?.synchronize() ?? Future.value();

  Future<void> connect() {
    if (_closed || busy) return _operation ?? Future.value();
    if (auth == null) {
      message =
          'Esta versión necesita configurar la conexión con Google Drive.';
      _changed();
      return Future.value();
    }
    busy = true;
    message = null;
    final epoch = ++_epoch;
    _changed();
    return _operation = _connect(epoch).whenComplete(() {
      busy = false;
      _operation = null;
      _changed();
    });
  }

  void _check(int epoch) {
    if (_closed || epoch != _epoch) throw const AuthCancelled();
  }

  Future<void> _connect(int epoch) async {
    AppServices? replacement;
    try {
      // Cancel and finish old I/O before the auth adapter can change identity.
      await _stop();
      _check(epoch);
      final selected = await auth!.signIn();
      _check(epoch);
      if (selected.id != account?.id) {
        replacement = await AppServices.open(_accountRoot(selected));
        _check(epoch);
        if (account == null) await _adoptLocal(selected, replacement, epoch);
        _check(epoch);
        await _saveSelection(selected);
        final previous = services;
        services = replacement;
        replacement = null;
        account = selected;
        await previous.close();
      }
      _check(epoch);
      await _saveSelection(selected);
      _check(epoch);
      _attach();
      if (!auth!.secureStorageAvailable) {
        message =
            'Conectado por esta sesión. Para recordar la cuenta necesitás habilitar el llavero del sistema.';
      }
    } on AuthCancelled {
      message = 'Conexión cancelada. Tus apuntes siguen guardados acá.';
    } catch (_) {
      message =
          'No se pudo conectar con Drive. Tus apuntes siguen guardados acá.';
    } finally {
      await replacement?.close();
    }
  }

  Future<void> _saveSelection(
    GoogleAccount value, {
    bool connected = true,
  }) async {
    final temporary = File('${_selection.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({...value.toJson(), 'connected': connected}),
      flush: true,
    );
    await temporary.rename(_selection.path);
  }

  Future<void> _adoptLocal(
    GoogleAccount selected,
    AppServices target,
    int epoch,
  ) async {
    final marker = File(p.join(root, 'local-adoption.json'));
    _check(epoch);
    // If the local partition is still selected, no account has ever begun
    // syncing this copy. Recopy its current state even after a completed marker.
    await (target.repository as SqliteNotebookRepository).resetForAdoption();
    await marker.writeAsString(
      jsonEncode({'accountId': selected.id, 'completed': false}),
      flush: true,
    );
    // Preserve the original local database as a backup. Only the first selected
    // account adopts it; a different account always starts in its own partition.
    await (target.repository as FolderRepository).mergeFolders(
      await (services.repository as FolderRepository).listFolders(
        includeDeleted: true,
      ),
    );
    final assets = Directory(p.join(services.root, 'local', 'assets'));
    if (await assets.exists()) {
      await for (final file in assets.list()) {
        _check(epoch);
        final id = p.basename(file.path);
        if (file is File && RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) {
          await target.assets.put(await services.assets.read(id));
        }
      }
    }
    final documents = (await services.repository.list())
        .map((e) => e.notebook.id)
        .toSet();
    for (final id in documents) {
      _check(epoch);
      for (final revision in await services.repository.history(id)) {
        await target.repository.acceptRemote(revision);
      }
    }
    await (target.repository as SqliteNotebookRepository).queueAllForUpload();
    await target.library.refresh();
    _check(epoch);
    await marker.writeAsString(
      jsonEncode({'accountId': selected.id, 'completed': true}),
      flush: true,
    );
  }

  Future<void> cancelConnection() async {
    _epoch++;
    await auth?.cancelSignIn();
  }

  Future<void> disconnect() {
    if (busy || _closed) return _operation ?? Future.value();
    busy = true;
    _changed();
    return _operation = _disconnect().whenComplete(() {
      busy = false;
      _operation = null;
      _changed();
    });
  }

  Future<void> _disconnect() async {
    await _stop();
    try {
      if (account != null) await _saveSelection(account!, connected: false);
      await auth?.signOut();
      message = auth?.secureStorageAvailable == false
          ? 'Drive quedó desconectado. No se pudo limpiar el llavero; no se reconectará automáticamente.'
          : null;
    } catch (_) {
      message = 'Drive quedó detenido. No se pudo cerrar la sesión de Google.';
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    await cancelConnection();
    await _operation;
    await _stop();
    await services.close();
    auth?.dispose();
    super.dispose();
  }
}
