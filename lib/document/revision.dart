import 'notebook.dart';

class Revision {
  const Revision({
    required this.id,
    required this.deviceId,
    required this.parentId,
    required this.createdAt,
    required this.notebook,
  });
  final String id, deviceId;
  final String? parentId;
  final DateTime createdAt;
  final Notebook notebook;
  Revision withParent(String? parentId) => Revision(
    id: id,
    deviceId: deviceId,
    parentId: parentId,
    createdAt: createdAt,
    notebook: notebook,
  );
}

class DocumentEntry {
  const DocumentEntry({
    required this.notebook,
    required this.headId,
    required this.isConflict,
    required this.deviceId,
  });
  final Notebook notebook;
  final String headId, deviceId;
  final bool isConflict;
}
