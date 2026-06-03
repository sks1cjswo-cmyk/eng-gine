import 'package:flutter_test/flutter_test.dart';

import 'package:personal_english_os/features/quiz/domain/sm2_algorithm.dart';

void main() {
  group('Sm2Algorithm', () {
    // -------------------------------------------------------------------------
    // Initial state helpers
    // -------------------------------------------------------------------------

    const initialReps = 0;
    const initialEF = 2.5;
    const initialInterval = 0;

    // -------------------------------------------------------------------------
    // First repetition (reps == 0)
    // -------------------------------------------------------------------------

    group('first repetition', () {
      test('quality=5 (Easy) → interval=1, reps=1, EF increases', () {
        final result = Sm2Algorithm.calculate(
          currentRepetitions: initialReps,
          currentEaseFactor: initialEF,
          currentIntervalDays: initialInterval,
          quality: Sm2Algorithm.qualityEasy,
        );

        expect(result.repetitions, 1);
        expect(result.intervalDays, 1);
        expect(result.easeFactor, greaterThan(initialEF));
        expect(result.nextReviewAt.isAfter(DateTime.now()), isTrue);
      });

      test('quality=4 (Good) → interval=1, reps=1, EF slightly increases', () {
        final result = Sm2Algorithm.calculate(
          currentRepetitions: initialReps,
          currentEaseFactor: initialEF,
          currentIntervalDays: initialInterval,
          quality: Sm2Algorithm.qualityGood,
        );

        expect(result.repetitions, 1);
        expect(result.intervalDays, 1);
        expect(result.easeFactor, greaterThanOrEqualTo(2.5));
      });

      test('quality=2 (Hard) → reset: interval=1, reps=0, EF unchanged', () {
        final result = Sm2Algorithm.calculate(
          currentRepetitions: initialReps,
          currentEaseFactor: initialEF,
          currentIntervalDays: initialInterval,
          quality: Sm2Algorithm.qualityHard,
        );

        expect(result.repetitions, 0);
        expect(result.intervalDays, 1);
        expect(result.easeFactor, initialEF); // unchanged on fail
      });

      test('quality=0 (Again) → reset: interval=1, reps=0', () {
        final result = Sm2Algorithm.calculate(
          currentRepetitions: initialReps,
          currentEaseFactor: initialEF,
          currentIntervalDays: initialInterval,
          quality: Sm2Algorithm.qualityAgain,
        );

        expect(result.repetitions, 0);
        expect(result.intervalDays, 1);
      });
    });

    // -------------------------------------------------------------------------
    // Second repetition (reps == 1)
    // -------------------------------------------------------------------------

    group('second repetition', () {
      test('quality=Good after first pass → interval=6, reps=2', () {
        // Simulate: first pass
        final first = Sm2Algorithm.calculate(
          currentRepetitions: 0,
          currentEaseFactor: initialEF,
          currentIntervalDays: 0,
          quality: Sm2Algorithm.qualityGood,
        );

        // Second pass
        final second = Sm2Algorithm.calculate(
          currentRepetitions: first.repetitions,
          currentEaseFactor: first.easeFactor,
          currentIntervalDays: first.intervalDays,
          quality: Sm2Algorithm.qualityGood,
        );

        expect(second.repetitions, 2);
        expect(second.intervalDays, 6);
      });
    });

    // -------------------------------------------------------------------------
    // Third repetition (reps == 2) — uses EF multiplication
    // -------------------------------------------------------------------------

    group('third repetition', () {
      test('interval = previous_interval * EF', () {
        final result = Sm2Algorithm.calculate(
          currentRepetitions: 2,
          currentEaseFactor: 2.5,
          currentIntervalDays: 6,
          quality: Sm2Algorithm.qualityGood,
        );

        expect(result.repetitions, 3);
        expect(result.intervalDays, (6 * 2.5).round()); // 15
      });
    });

    // -------------------------------------------------------------------------
    // Ease Factor clamping
    // -------------------------------------------------------------------------

    group('ease factor clamping', () {
      test('EF never falls below 1.3 regardless of repeated failures', () {
        var reps = 3;
        var ef = 1.4;
        var interval = 15;

        for (var i = 0; i < 10; i++) {
          final result = Sm2Algorithm.calculate(
            currentRepetitions: reps,
            currentEaseFactor: ef,
            currentIntervalDays: interval,
            quality: Sm2Algorithm.qualityAgain, // always fail
          );
          ef = result.easeFactor;
          reps = result.repetitions;
          interval = result.intervalDays;
        }

        expect(ef, greaterThanOrEqualTo(1.3));
      });

      test('EF increases with Easy responses over multiple sessions', () {
        var reps = 1;
        var ef = 2.5;
        var interval = 6;

        for (var i = 0; i < 5; i++) {
          final result = Sm2Algorithm.calculate(
            currentRepetitions: reps,
            currentEaseFactor: ef,
            currentIntervalDays: interval,
            quality: Sm2Algorithm.qualityEasy,
          );
          expect(result.easeFactor, greaterThanOrEqualTo(ef));
          ef = result.easeFactor;
          reps = result.repetitions;
          interval = result.intervalDays;
        }
      });
    });

    // -------------------------------------------------------------------------
    // Next review date
    // -------------------------------------------------------------------------

    group('nextReviewAt', () {
      test('is in the future for any quality >= 0', () {
        for (final quality in [0, 2, 4, 5]) {
          final result = Sm2Algorithm.calculate(
            currentRepetitions: 1,
            currentEaseFactor: 2.5,
            currentIntervalDays: 1,
            quality: quality,
          );
          expect(
            result.nextReviewAt.isAfter(
              DateTime.now().subtract(const Duration(seconds: 5)),
            ),
            isTrue,
            reason: 'quality=$quality should produce future nextReviewAt',
          );
        }
      });

      test('Easy review schedules further than Good review', () {
        final good = Sm2Algorithm.calculate(
          currentRepetitions: 2,
          currentEaseFactor: 2.5,
          currentIntervalDays: 6,
          quality: Sm2Algorithm.qualityGood,
        );
        final easy = Sm2Algorithm.calculate(
          currentRepetitions: 2,
          currentEaseFactor: 2.5,
          currentIntervalDays: 6,
          quality: Sm2Algorithm.qualityEasy,
        );

        expect(
          easy.nextReviewAt.isAfter(good.nextReviewAt),
          isTrue,
        );
      });
    });

    // -------------------------------------------------------------------------
    // Sm2Result toString
    // -------------------------------------------------------------------------

    test('toString contains all fields', () {
      final result = Sm2Algorithm.calculate(
        currentRepetitions: 0,
        currentEaseFactor: 2.5,
        currentIntervalDays: 0,
        quality: 4,
      );

      final str = result.toString();
      expect(str, contains('reps='));
      expect(str, contains('ef='));
      expect(str, contains('interval='));
      expect(str, contains('next='));
    });
  });
}
