import 'dart:async';
import 'dart:typed_data';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/document/folders.dart';
import 'package:apuntes/sync/remote_store.dart';

// Only the network boundary is simulated. Clients use real SQLite and files.
class FakeRemoteStore implements RemoteStore {
  final revisions = <String, Revision>{};
  final assets = <String, Uint8List>{};
  final folders = <String, NoteFolder>{};
  bool offline = false, loseAcknowledgement = false;
  Completer<void>? listingGate;
  int listingCalls = 0;
  @override
  Future<List<Revision>> listRevisions() async {
    listingCalls++;
    await listingGate?.future;
    if (offline) throw StateError('Sin conexión');
    return revisions.values.toList();
  }

  @override
  Future<void> putRevision(Revision revision) async {
    if (offline) throw StateError('Sin conexión');
    revisions[revision.id] = revision;
    if (loseAcknowledgement) {
      loseAcknowledgement = false;
      throw TimeoutException('Respuesta perdida');
    }
  }

  @override
  Future<bool> hasAsset(String id) async => assets.containsKey(id);
  @override
  Future<void> putAsset(String id, Uint8List bytes) async {
    assets[id] = bytes;
  }

  @override
  Future<Uint8List> readAsset(String id) async => assets[id]!;
  @override
  Future<List<NoteFolder>> listFolders() async => folders.values.toList();
  @override
  Future<void> putFolder(NoteFolder folder) async {
    folders[folder.id] = folder;
  }

  @override
  void close() {}
}
