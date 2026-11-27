import 'dart:async';
import 'dart:io';
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

class _LocalAttachmentUnavailable implements Exception {}

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
  DateTime? _lastSuccessfulSync;
  DateTime? get lastSuccessfulSync => _lastSuccessfulSync;
  Future<void> get idle => _running ?? Future.value();
  void _emit(SyncStatus value) {
    if (_closed) return;
    status = value;
    _states.add(value);
    notifyListeners();
  }

  void notifyPending() {
    if (status.phase == SyncPhase.localOnly ||
        status.phase == SyncPhase.synced) {
      _emit(SyncStatus(SyncPhase.pending, pendingCount: status.pendingCount));
    }
  }

  Future<void> synchronize() {
    if (_closed) return Future.value();
    return _running ??= _synchronize().whenComplete(() => _running = null);
  }

  Future<void> _synchronize() async {
    final changes = _RemoteChanges();
    var stage = SyncStage.receiving;
    var pendingCount = status.pendingCount;
    void working(SyncStage nextStage) {
      stage = nextStage;
      _emit(
        SyncStatus(SyncPhase.syncing, pendingCount: pendingCount, stage: stage),
      );
    }

    working(SyncStage.receiving);
    try {
      final verified = <String>{};
      await _pull(verified, changes);
      if (_closed) return;
      _publishChanges(changes);
      working(SyncStage.sending);
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
      final pending = await repository.pending();
      pendingCount = pending.length;
      if (pendingCount != 0) working(SyncStage.sending);
      final availableOnServer = <String>{};
      final blockedDocuments = <String>{};
      for (final revision in pending) {
        if (_closed) return;
        final notebook = revision.notebook;
        if (blockedDocuments.contains(notebook.id)) continue;
        try {
          for (final id in notebookAssets(notebook)) {
            if (_closed) return;
            if (availableOnServer.contains(id)) continue;
            if (!await remote.hasAsset(id)) await _uploadAsset(id);
            availableOnServer.add(id);
          }
        } on _LocalAttachmentUnavailable {
          blockedDocuments.add(notebook.id);
          continue;
        }
        if (_closed) return;
        await remote.putRevision(revision);
        if (_closed) return;
        await repository.markUploaded(revision.id);
        pendingCount--;
      }
      working(SyncStage.receiving);
      await _pull(verified, changes);
      if (_closed) return;
      pendingCount = await _countPending();
      if (blockedDocuments.isNotEmpty) {
        _reportRetry(
          pendingCount,
          'Quedaron apuntes pendientes porque falta un adjunto local o está dañado. Nala seguirá sincronizando los demás cambios.',
        );
        return;
      }
      _failures = 0;
      if (pendingCount == 0) _lastSuccessfulSync = DateTime.now();
      _emit(
        SyncStatus(
          pendingCount == 0 ? SyncPhase.synced : SyncPhase.pending,
          pendingCount: pendingCount,
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
      try {
        pendingCount = await _countPending();
      } catch (_) {
        // A local repository failure must not hide the original sync error.
      }
      final issue = switch (e) {
        TimeoutException() => 'La conexión tardó demasiado.',
        SocketException() => 'No se pudo conectar con el servidor.',
        RemoteRetryLater() => 'El servidor no pudo completar la operación.',
        _ =>
          stage == SyncStage.receiving
              ? 'Se interrumpió la recepción de cambios.'
              : 'Se interrumpió el envío de cambios.',
      };
      _reportRetry(
        pendingCount,
        '$issue Nala volverá a intentar automáticamente.',
        retryAfter: e is RemoteRetryLater ? e.delay : null,
      );
    } finally {
      _publishChanges(changes);
    }
  }

  Future<int> _countPending() async => switch (repository) {
    final PendingRevisionCountRepository counted =>
      await counted.pendingCount(),
    _ => (await repository.pending()).length,
  };

  void _reportRetry(int pendingCount, String message, {Duration? retryAfter}) {
    _failures++;
    _emit(
      SyncStatus(
        SyncPhase.error,
        pendingCount: pendingCount,
        message: message,
        retryAfter:
            retryAfter ??
            Duration(seconds: (2 << (_failures - 1).clamp(0, 5)).clamp(2, 60)),
      ),
    );
  }

  void _publishChanges(_RemoteChanges changes) {
    if (_closed || (changes.notebookIds.isEmpty && !changes.foldersChanged)) {
      return;
    }
    _remoteChanges.add((
      notebookIds: Set.unmodifiable(changes.notebookIds),
      foldersChanged: changes.foldersChanged,
    ));
    changes.notebookIds.clear();
    changes.foldersChanged = false;
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
      final file = await _readLocalAttachment(() => files.verifiedFile(id));
      _checkOpen();
      await transfer.putVerifiedAssetFile(id, file);
    } else {
      await remote.putAsset(
        id,
        await _readLocalAttachment(() => local.read(id)),
      );
    }
  }

  Future<T> _readLocalAttachment<T>(Future<T> Function() read) async {
    try {
      return await read();
    } on FileSystemException {
      throw _LocalAttachmentUnavailable();
    } on FormatException {
      throw _LocalAttachmentUnavailable();
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
