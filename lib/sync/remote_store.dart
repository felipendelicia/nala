import 'dart:io';
import 'dart:typed_data';
import '../document/revision.dart';
import '../document/folders.dart';

abstract interface class RemoteStore {
  Future<List<Revision>> listRevisions();
  Future<void> putRevision(Revision revision);
  Future<bool> hasAsset(String assetId);
  Future<void> putAsset(String assetId, Uint8List bytes);
  Future<Uint8List> readAsset(String assetId);
  Future<List<NoteFolder>> listFolders();
  Future<void> putFolder(NoteFolder folder);
  void close();
}

abstract interface class IncrementalRemoteStore {
  Future<void> pullRevisions(Future<void> Function(Revision revision) accept);
}

abstract interface class FolderBatchRemoteStore {
  Future<void> putFolders(List<NoteFolder> folders);
}

abstract interface class FileTransferRemoteStore {
  Future<void> putVerifiedAssetFile(String assetId, File file);

  /// The verified file is available until [accept] finishes.
  Future<void> readAssetFile(
    String assetId,
    Future<void> Function(File) accept,
  );
}

class RemoteSignInRequired implements Exception {
  const RemoteSignInRequired();
}

class RemoteServerChanged implements Exception {
  const RemoteServerChanged();
}

class RemoteRetryLater implements Exception {
  const RemoteRetryLater(this.delay);
  final Duration delay;
}
