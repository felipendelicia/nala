import 'dart:math' as math;

import 'study_card.dart';

enum StudyRating { again, hard, good, easy }

/// A local, deterministic spaced-repetition schedule. Successful reviews grow
/// the interval; a forgotten answer comes back in the current study session.
class StudyScheduler {
  StudyScheduler({DateTime Function()? now}) : now = now ?? DateTime.now;
  final DateTime Function() now;

  List<StudyCard> due(Iterable<StudyCard> cards) {
    final instant = now().toUtc();
    return cards.where((card) => !card.dueAt.isAfter(instant)).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
  }

  StudyCard review(StudyCard card, StudyRating rating) {
    final instant = now().toUtc();
    if (rating == StudyRating.again) {
      return card.copyWith(
        dueAt: instant.add(const Duration(minutes: 10)),
        intervalDays: 0,
        repetitions: 0,
        ease: math.max(1.3, card.ease - .2),
      );
    }
    final int days;
    final double ease;
    switch (rating) {
      case StudyRating.again:
        throw StateError('Valoración ya procesada');
      case StudyRating.hard:
        days = card.intervalDays == 0
            ? 1
            : math.max(card.intervalDays + 1, (card.intervalDays * 1.2).ceil());
        ease = math.max(1.3, card.ease - .15);
      case StudyRating.good:
        days = card.intervalDays == 0
            ? 2
            : card.repetitions == 1
            ? 6
            : math.max(
                card.intervalDays + 1,
                (card.intervalDays * card.ease).round(),
              );
        ease = card.ease;
      case StudyRating.easy:
        days = card.intervalDays == 0
            ? 4
            : math.max(
                card.intervalDays + 1,
                (card.intervalDays * card.ease * 1.3).ceil(),
              );
        ease = math.min(3.5, card.ease + .15);
    }
    // Keep dates representable even after years of repeated reviews.
    final interval = math.min(days, 36500);
    return card.copyWith(
      dueAt: instant.add(Duration(days: interval)),
      intervalDays: interval,
      repetitions: card.repetitions + 1,
      ease: ease,
    );
  }
}
