import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/notebook_repository.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/document/asset_store.dart';

class MemoryRepository implements NotebookRepository {
  final Map<String, Revision> revisions = {};
  final Set<String> queued = {};
  @override
  Future<void> commit(Revision revision) async {
    revisions[revision.id] = revision;
    queued.add(revision.id);
  }

  @override
  Future<List<DocumentEntry>> list() async {
    final parents = revisions.values.map((r) => r.parentId).toSet();
    final heads = revisions.values
        .where((r) => !parents.contains(r.id))
        .toList();
    return heads
        .map(
          (r) => DocumentEntry(
            notebook: r.notebook,
            headId: r.id,
            deviceId: r.deviceId,
            isConflict:
                heads.where((h) => h.notebook.id == r.notebook.id).length > 1,
          ),
        )
        .toList();
  }

  @override
  Future<Notebook?> load(String documentId, {String? headId}) async =>
      headId != null
      ? revisions[headId]?.notebook
      : (await list())
            .where((e) => e.notebook.id == documentId)
            .firstOrNull
            ?.notebook;
  @override
  Future<List<Revision>> history(String id) async =>
      revisions.values.where((r) => r.notebook.id == id).toList();
  @override
  Future<List<Revision>> pending() async =>
      queued.map((id) => revisions[id]!).toList();
  @override
  Future<void> markUploaded(String id) async {
    queued.remove(id);
  }

  @override
  Future<void> acceptRemote(Revision revision) async {
    revisions[revision.id] = revision;
  }

  @override
  Future<void> close() async {}
}

class MemoryAssets implements AssetStore {
  final Map<String, Uint8List> assets = {};
  @override
  Future<String> put(Uint8List bytes) async {
    final id = sha256.convert(bytes).toString();
    assets[id] = bytes;
    return id;
  }

  @override
  Future<Uint8List> read(String id) async => assets[id]!;
  @override
  Future<bool> contains(String id) async => assets.containsKey(id);
}
