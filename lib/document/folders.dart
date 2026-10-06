const _keepParent = Object();

class NoteFolder {
  NoteFolder({
    required this.id,
    required this.name,
    this.parentId,
    DateTime? updatedAt,
    this.deleted = false,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc();
  final String id, name;
  final String? parentId;
  final DateTime updatedAt;
  final bool deleted;
  NoteFolder copyWith({
    String? name,
    Object? parentId = _keepParent,
    DateTime? updatedAt,
    bool? deleted,
  }) => NoteFolder(
    id: id,
    name: name ?? this.name,
    parentId: identical(parentId, _keepParent)
        ? this.parentId
        : parentId as String?,
    updatedAt: updatedAt ?? this.updatedAt,
    deleted: deleted ?? this.deleted,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'parentId': parentId,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'deleted': deleted,
  };
  factory NoteFolder.fromJson(Map<String, dynamic> json) => NoteFolder(
    id: json['id'] as String,
    name: json['name'] as String,
    parentId: json['parentId'] as String?,
    updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    deleted: json['deleted'] as bool? ?? false,
  );
}

abstract interface class FolderRepository {
  Future<List<NoteFolder>> listFolders({bool includeDeleted = false});
  Future<void> saveFolder(NoteFolder folder);
  Future<void> deleteFolder(String id);
}
