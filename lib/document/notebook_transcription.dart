import 'notebook.dart' show nonEmpty;

class NotebookTranscription {
  NotebookTranscription._({
    required this.id,
    required DateTime createdAt,
    required this.text,
    this.cleanedText,
    this.summary,
  }) : createdAt = createdAt.toUtc() {
    nonEmpty(id);
    if (text.trim().isEmpty) {
      throw const FormatException('Transcripción vacía');
    }
  }

  final String id, text;
  final String? cleanedText, summary;
  final DateTime createdAt;

  Map<String, Object> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'text': text,
    'cleanedText': ?cleanedText,
    'summary': ?summary,
  };

  factory NotebookTranscription.fromJson(Map<String, dynamic> json) =>
      NotebookTranscription._(
        id: nonEmpty(json['id']),
        createdAt: DateTime.parse(json['createdAt'] as String),
        text: json['text'] as String,
        cleanedText: json['cleanedText'] as String?,
        summary: json['summary'] as String?,
      );
}
