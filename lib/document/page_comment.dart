import 'notebook.dart' show finiteNumber, nonEmpty;

const _keepAudio = Object();

class PageComment {
  const PageComment({
    required this.id,
    required this.x,
    required this.y,
    required this.text,
    required this.createdAt,
    this.audioAssetId,
    this.audioDurationMs,
  });
  final String id, text;
  final double x, y;
  final DateTime createdAt;
  final String? audioAssetId;
  final int? audioDurationMs;
  PageComment copyWith({
    String? text,
    Object? audioAssetId = _keepAudio,
    Object? audioDurationMs = _keepAudio,
  }) => PageComment(
    id: id,
    x: x,
    y: y,
    text: text ?? this.text,
    createdAt: createdAt,
    audioAssetId: identical(audioAssetId, _keepAudio)
        ? this.audioAssetId
        : audioAssetId as String?,
    audioDurationMs: identical(audioDurationMs, _keepAudio)
        ? this.audioDurationMs
        : audioDurationMs as int?,
  );
  Map<String, Object> toJson() => {
    'id': id,
    'x': x,
    'y': y,
    'text': text,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'audioAssetId': ?audioAssetId,
    'audioDurationMs': ?audioDurationMs,
  };
  factory PageComment.fromJson(Map<String, dynamic> json) {
    final audio = json['audioAssetId'] as String?;
    final duration = json['audioDurationMs'];
    final text = json['text'] as String;
    if (audio != null &&
        (!RegExp(r'^[a-f0-9]{64}$').hasMatch(audio) ||
            duration is! int ||
            duration < 0)) {
      throw const FormatException('Audio de comentario inválido');
    }
    if (audio == null && duration != null) {
      throw const FormatException('Duración sin audio');
    }
    if (text.trim().isEmpty && audio == null) {
      throw const FormatException('Comentario vacío');
    }
    return PageComment(
      id: nonEmpty(json['id']),
      x: finiteNumber(json['x'], min: 0),
      y: finiteNumber(json['y'], min: 0),
      text: text,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      audioAssetId: audio,
      audioDurationMs: duration as int?,
    );
  }
}
