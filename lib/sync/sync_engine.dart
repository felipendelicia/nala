import 'dart:async';
import 'package:flutter/foundation.dart';
import '../document/asset_store.dart';
import '../document/folders.dart';
import '../document/notebook.dart';
import '../document/notebook_codec.dart';
import '../document/notebook_repository.dart';
import '../document/revision.dart';
import 'remote_store.dart';
import 'sync_state.dart';

Set<String> notebookAssets(Notebook notebook) => {
  if (notebook.coverAssetId != null) notebook.coverAssetId!,
  for (final recording in notebook.recordings) recording.assetId,
  for (final page in notebook.pages) ...[
    if (page.background.assetId != null) page.background.assetId!,
    for (final comment in page.comments)
      if (comment.audioAssetId != null) comment.audioAssetId!,
    for (final object in page.objects) ...[
      if (object.assetId != null) object.assetId!,
      if (object.originalAssetId != null) object.originalAssetId!,
    ],
  ],
};

class SyncEngine extends ChangeNotifier {
  SyncEngine({
    required this.repository,
    required this.assets,
    required this.remote,
  });
  final NotebookRepository repository;
  final AssetStore assets;
  final RemoteStore remote;
  final _states = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get states => _states.stream;
  SyncStatus status = const SyncStatus(SyncPhase.localOnly);
  Future<void>? _running;
  bool _closed = false;
  int _failures = 0;
  Future<void> get idle => _running ?? Future.value();
  void _emit(SyncStatus value) {
    if (_closed) return;
    status = value;
    _states.add(value);
    notifyListeners();
  }

  void notifyPending() {
    if (status.phase != SyncPhase.syncing &&
        status.phase != SyncPhase.needsSignIn) {
      _emit(SyncStatus(SyncPhase.pending, pendingCount: status.pendingCount));
    }
  }

  Future<void> synchronize() {
    if (_closed) return Future.value();
    return _running ??= _synchronize().whenComplete(() => _running = null);
  }

  Future<void> _synchronize() async {
    _emit(const SyncStatus(SyncPhase.syncing));
    try {
      final verified = <String>{};
      await _pull(verified);
      if (_closed) return;
      if (repository is FolderRepository) {
        for (final folder in await (repository as FolderRepository).listFolders(
          includeDeleted: true,
        )) {
          if (_closed) return;
          await remote.putFolder(folder);
        }
      }
      for (final revision in await repository.pending()) {
        if (_closed) return;
        for (final id in notebookAssets(revision.notebook)) {
          if (_closed) return;
          if (!await remote.hasAsset(id)) {
            await remote.putAsset(id, await assets.read(id));
          }
        }
        if (_closed) return;
        await remote.putRevision(revision);
        if (_closed) return;
        await repository.markUploaded(revision.id);
      }
      await _pull(verified);
      if (_closed) return;
      final pending = await repository.pending();
      _failures = 0;
      _emit(
        SyncStatus(
          pending.isEmpty ? SyncPhase.synced : SyncPhase.pending,
          pendingCount: pending.length,
        ),
      );
    } on RemoteSignInRequired {
      _emit(
        const SyncStatus(
          SyncPhase.needsSignIn,
          message:
              'Volvé a conectar tu cuenta. Tus apuntes siguen guardados acá.',
        ),
      );
    } catch (e) {
      if (_closed) return;
      _failures++;
      final delay = e is RemoteRetryLater
          ? e.delay
          : Duration(seconds: (2 << (_failures - 1).clamp(0, 5)).clamp(2, 60));
      _emit(
        SyncStatus(
          SyncPhase.error,
          message:
              'No se pudo completar la sincronización. Se reintentará automáticamente.',
          retryAfter: delay,
        ),
      );
    }
  }

  Future<void> _pull(Set<String> verified) async {
    final remoteFolders = await remote.listFolders();
    if (_closed) return;
    if (repository is FolderRepository) {
      await (repository as FolderRepository).mergeFolders(remoteFolders);
    }
    final known = <String, Map<String, Revision>>{};
    for (final revision in await remote.listRevisions()) {
      if (_closed) return;
      final history = known[revision.notebook.id] ??= {
        for (final r in await repository.history(revision.notebook.id)) r.id: r,
      };
      final old = history[revision.id];
      if (old != null && !await compute(_sameRevision, (old, revision))) {
        throw const FormatException('Una revisión remota cambió de contenido.');
      }
      for (final id in notebookAssets(revision.notebook)) {
        if (_closed) return;
        if (verified.contains(id)) continue;
        var valid = false;
        if (await assets.contains(id)) {
          try {
            await assets.read(id);
            valid = true;
          } on FormatException {
            /* Repair from remote. */
          }
        }
        if (!valid) {
          final downloaded = await remote.readAsset(id);
          if (_closed) return;
          if (await assets.put(downloaded) != id) {
            throw const FormatException(
              'El recurso descargado no coincide con su hash.',
            );
          }
        }
        verified.add(id);
      }
      if (_closed) return;
      if (old == null) {
        await repository.acceptRemote(revision);
        history[revision.id] = revision;
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    remote.close();
    unawaited(_states.close());
    super.dispose();
  }
}

bool _sameRevision((Revision, Revision) pair) =>
    NotebookCodec.encodeRevision(pair.$1) ==
    NotebookCodec.encodeRevision(pair.$2);
