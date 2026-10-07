import 'package:apuntes/study/study_card.dart';
import 'package:apuntes/study/study_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 7, 12);
  StudyCard card({int interval = 0, int repetitions = 0}) => StudyCard(
    id: 'card',
    front: 'Pregunta',
    back: 'Respuesta',
    dueAt: now,
    intervalDays: interval,
    repetitions: repetitions,
  );

  test(
    'Again returns a due card soon and resets its successful repetitions',
    () {
      final scheduler = StudyScheduler(now: () => now);
      final result = scheduler.review(
        card(interval: 20, repetitions: 4),
        StudyRating.again,
      );
      expect(result.dueAt, now.add(const Duration(minutes: 10)));
      expect(result.repetitions, 0);
      expect(result.intervalDays, 0);
      expect(result.front, 'Pregunta');
      expect(result.back, 'Respuesta');
    },
  );

  test('Hard, Good and Easy offer increasing first review intervals', () {
    final scheduler = StudyScheduler(now: () => now);
    final hard = scheduler.review(card(), StudyRating.hard);
    final good = scheduler.review(card(), StudyRating.good);
    final easy = scheduler.review(card(), StudyRating.easy);
    expect(hard.dueAt, now.add(const Duration(days: 1)));
    expect(good.dueAt, now.add(const Duration(days: 2)));
    expect(easy.dueAt, now.add(const Duration(days: 4)));
    expect(good.repetitions, 1);
  });

  test('successful review intervals grow and difficulty remains bounded', () {
    final scheduler = StudyScheduler(now: () => now);
    var reviewed = card();
    final intervals = <int>[];
    for (var i = 0; i < 4; i++) {
      reviewed = scheduler.review(reviewed, StudyRating.good);
      intervals.add(reviewed.intervalDays);
    }
    expect(intervals, [2, 6, 15, 38]);
    for (var i = 0; i < 20; i++) {
      reviewed = scheduler.review(reviewed, StudyRating.hard);
    }
    expect(reviewed.ease, greaterThanOrEqualTo(1.3));
  });

  test('due cards include today and exclude future reviews in due order', () {
    final scheduler = StudyScheduler(now: () => now);
    final past = StudyCard(
      id: 'past',
      front: 'A',
      back: 'B',
      dueAt: now.subtract(const Duration(days: 1)),
    );
    final future = StudyCard(
      id: 'future',
      front: 'A',
      back: 'B',
      dueAt: now.add(const Duration(seconds: 1)),
    );
    expect(scheduler.due([future, card(), past]).map((c) => c.id), [
      'past',
      'card',
    ]);
  });
}
