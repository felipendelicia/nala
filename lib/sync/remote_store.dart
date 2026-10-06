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

class RemoteSignInRequired implements Exception {
  const RemoteSignInRequired();
}

class RemoteRetryLater implements Exception {
  const RemoteRetryLater(this.delay);
  final Duration delay;
}
