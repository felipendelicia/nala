import '../document/notebook.dart' show finiteNumber, nonEmpty;

class StudyCard {
  StudyCard({
    required this.id,
    required this.front,
    required this.back,
    required this.dueAt,
    this.intervalDays = 0,
    this.repetitions = 0,
    this.ease = 2.5,
  }) {
    nonEmpty(id);
    nonEmpty(front);
    nonEmpty(back);
    finiteNumber(ease, positive: true);
    if (intervalDays < 0 || repetitions < 0) {
      throw const FormatException('Programación de tarjeta inválida');
    }
  }

  final String id, front, back;
  final DateTime dueAt;
  final int intervalDays, repetitions;
  final double ease;

  StudyCard copyWith({
    String? id,
    String? front,
    String? back,
    DateTime? dueAt,
    int? intervalDays,
    int? repetitions,
    double? ease,
  }) => StudyCard(
    id: id ?? this.id,
    front: front ?? this.front,
    back: back ?? this.back,
    dueAt: dueAt ?? this.dueAt,
    intervalDays: intervalDays ?? this.intervalDays,
    repetitions: repetitions ?? this.repetitions,
    ease: ease ?? this.ease,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'front': front,
    'back': back,
    'dueAt': dueAt.toUtc().toIso8601String(),
    if (intervalDays != 0) 'intervalDays': intervalDays,
    if (repetitions != 0) 'repetitions': repetitions,
    if (ease != 2.5) 'ease': ease,
  };

  factory StudyCard.fromJson(Map<String, dynamic> json) => StudyCard(
    id: nonEmpty(json['id']),
    front: nonEmpty(json['front']),
    back: nonEmpty(json['back']),
    dueAt: DateTime.parse(json['dueAt'] as String).toUtc(),
    intervalDays: json['intervalDays'] as int? ?? 0,
    repetitions: json['repetitions'] as int? ?? 0,
    ease: finiteNumber(json['ease'] ?? 2.5, positive: true),
  );
}
