import 'dart:async';
import 'package:flutter/foundation.dart';
import '../document/asset_store.dart';
import '../document/document_worker.dart';
import '../document/folders.dart';
import '../document/notebook.dart';
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

typedef RemoteChanges = ({Set<String> notebookIds, bool foldersChanged});

class _RemoteChanges {
  final notebookIds = <String>{};
  bool foldersChanged = false;
}

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
  final _remoteChanges = StreamController<RemoteChanges>.broadcast();
  Stream<RemoteChanges> get remoteChanges => _remoteChanges.stream;
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
    final changes = _RemoteChanges();
    try {
      final verified = <String>{};
      await _pull(verified, changes);
      if (_closed) return;
      if (repository is FolderRepository) {
        final folders = await (repository as FolderRepository).listFolders(
          includeDeleted: true,
        );
        if (_closed) return;
        if (remote case final FolderBatchRemoteStore batch) {
          if (folders.isNotEmpty) await batch.putFolders(folders);
        } else {
          for (final folder in folders) {
            if (_closed) return;
            await remote.putFolder(folder);
          }
        }
      }
      for (final revision in await repository.pending()) {
        if (_closed) return;
        for (final id in notebookAssets(revision.notebook)) {
          if (_closed) return;
          if (!await remote.hasAsset(id)) {
            await _uploadAsset(id);
          }
        }
        if (_closed) return;
        await remote.putRevision(revision);
        if (_closed) return;
        await repository.markUploaded(revision.id);
      }
      await _pull(verified, changes);
      if (_closed) return;
      final pending = await repository.pending();
      _failures = 0;
      _emit(
        SyncStatus(
          pending.isEmpty ? SyncPhase.synced : SyncPhase.pending,
          pendingCount: pending.length,
        ),
      );
    } on RemoteServerChanged {
      _emit(
        const SyncStatus(
          SyncPhase.needsSignIn,
          message:
              'La identidad del servidor cambió. Confirmá el destino para volver a sincronizar.',
        ),
      );
    } on RemoteSignInRequired {
      _emit(
        const SyncStatus(
          SyncPhase.needsSignIn,
          message:
              'Volvé a conectar el servidor. Tus apuntes siguen guardados acá.',
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
    } finally {
      if (!_closed &&
          (changes.notebookIds.isNotEmpty || changes.foldersChanged)) {
        _remoteChanges.add((
          notebookIds: Set.unmodifiable(changes.notebookIds),
          foldersChanged: changes.foldersChanged,
        ));
      }
    }
  }

  Future<void> _pull(Set<String> verified, _RemoteChanges changes) async {
    final remoteFolders = await remote.listFolders();
    if (_closed) return;
    if (repository case final FolderRepository folders) {
      if (await folders.mergeFolders(remoteFolders)) {
        changes.foldersChanged = true;
      }
    }
    final catalog = repository;
    final known = <String, Map<String, Revision>>{};
    Future<Revision?> findLocalRevision(
      String documentId,
      String revisionId,
    ) async {
      if (catalog case final RevisionLookupRepository lookup) {
        return lookup.lookupRevision(documentId, revisionId);
      }
      final history = known[documentId] ??= {
        for (final r in await catalog.history(documentId)) r.id: r,
      };
      return history[revisionId];
    }

    Future<void> accept(Revision revision) async {
      _checkOpen();
      final old = await findLocalRevision(revision.notebook.id, revision.id);
      if (old != null && !await const DocumentWorker().equal(old, revision)) {
        throw const FormatException('Una revisión remota cambió de contenido.');
      }
      for (final id in notebookAssets(revision.notebook)) {
        _checkOpen();
        if (verified.contains(id)) continue;
        await _ensureAsset(id);
        verified.add(id);
      }
      _checkOpen();
      if (old == null) {
        await repository.acceptRemote(revision);
        changes.notebookIds.add(revision.notebook.id);
        known[revision.notebook.id]?[revision.id] = revision;
      }
    }

    if (remote case final IncrementalRemoteStore incremental) {
      await incremental.pullRevisions(accept);
    } else {
      for (final revision in await remote.listRevisions()) {
        await accept(revision);
      }
    }
  }

  Future<void> _uploadAsset(String id) async {
    final local = assets;
    final server = remote;
    if ((local, server) case (
      final FileAssetStore files,
      final FileTransferRemoteStore transfer,
    )) {
      final file = await files.verifiedFile(id);
      _checkOpen();
      await transfer.putVerifiedAssetFile(id, file);
    } else {
      await remote.putAsset(id, await assets.read(id));
    }
  }

  Future<void> _ensureAsset(String id) async {
    final local = assets;
    final server = remote;
    if (await local.contains(id)) {
      try {
        if (local is FileAssetStore) {
          await local.verifiedFile(id);
        } else {
          await local.read(id);
        }
        return;
      } on FormatException {
        // Replace a corrupt file with the verified server copy.
      }
    }
    _checkOpen();
    if ((local, server) case (
      final FileAssetStore files,
      final FileTransferRemoteStore transfer,
    )) {
      await transfer.readAssetFile(id, (file) async {
        _checkOpen();
        await files.putVerifiedFile(id, file);
      });
      return;
    }
    final downloaded = await server.readAsset(id);
    _checkOpen();
    if (await local.put(downloaded) != id) {
      throw const FormatException(
        'El recurso descargado no coincide con su hash.',
      );
    }
  }

  void _checkOpen() {
    if (_closed) throw StateError('Se cerró la sincronización.');
  }

  @override
  void dispose() {
    _closed = true;
    remote.close();
    unawaited(_states.close());
    unawaited(_remoteChanges.close());
    super.dispose();
  }
}
