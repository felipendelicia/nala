import 'notebook.dart' show nonEmpty, validAssetId;

class NotebookRecording {
  NotebookRecording({
    required this.id,
    required this.title,
    required this.assetId,
    required this.durationMs,
    required this.createdAt,
  }) {
    nonEmpty(id);
    nonEmpty(title);
    validAssetId(assetId);
    if (durationMs < 0) {
      throw const FormatException('Duración de grabación inválida');
    }
  }

  final String id, title, assetId;
  final int durationMs;
  final DateTime createdAt;

  NotebookRecording copyWith({String? title}) => NotebookRecording(
    id: id,
    title: title ?? this.title,
    assetId: assetId,
    durationMs: durationMs,
    createdAt: createdAt,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'assetId': assetId,
    'durationMs': durationMs,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory NotebookRecording.fromJson(Map<String, dynamic> json) =>
      NotebookRecording(
        id: nonEmpty(json['id']),
        title: nonEmpty(json['title']),
        assetId: validAssetId(json['assetId']),
        durationMs: json['durationMs'] as int,
        createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      );
}
