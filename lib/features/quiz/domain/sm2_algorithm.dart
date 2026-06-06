import 'dart:math' as math;

/// SM-2 Spaced Repetition algorithm implementation.
///
/// Original algorithm: P.A. Wozniak, 1987.
/// Reference: https://www.supermemo.com/en/blog/application-of-a-computer-to-improve-the-results-obtained-in-working-with-the-supermemo-method
class Sm2Algorithm {
  Sm2Algorithm._();

  /// Quality ratings (Anki-style, mapped to SM-2 quality 0–5).
  static const int qualityAgain = 0; // complete blackout
  static const int qualityHard = 2;  // incorrect; easy hint remembered
  static const int qualityGood = 4;  // correct; with hesitation
  static const int qualityEasy = 5;  // perfect response

  // Easy answer applies an additional interval bonus (standard SM-2 extension).
  static const double _easyBonus = 1.3;

  /// Calculates the next review state given the current state and quality.
  ///
  /// Returns [Sm2Result] with updated fields to persist.
  static Sm2Result calculate({
    required int currentRepetitions,
    required double currentEaseFactor,
    required int currentIntervalDays,
    required int quality, // 0–5
  }) {
    assert(quality >= 0 && quality <= 5, 'Quality must be 0–5');

    int newRepetitions;
    int newIntervalDays;
    double newEaseFactor;

    if (quality < 3) {
      // Failed — reset
      newRepetitions = 0;
      newIntervalDays = 1;
      newEaseFactor = currentEaseFactor; // EF unchanged on fail per SM-2
    } else {
      // Passed
      newRepetitions = currentRepetitions + 1;

      if (newRepetitions == 1) {
        newIntervalDays = 1;
      } else if (newRepetitions == 2) {
        newIntervalDays = 6;
      } else {
        newIntervalDays = (currentIntervalDays * currentEaseFactor).round();
      }

      // Update ease factor: EF' = EF + (0.1 - (5-q)*(0.08 + (5-q)*0.02))
      final efDelta =
          0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02);
      newEaseFactor = currentEaseFactor + efDelta;

      // Easy bonus: schedule further than Good for the same card state.
      if (quality == qualityEasy) {
        newIntervalDays = (newIntervalDays * _easyBonus).round();
      }
    }

    // Clamp ease factor to [1.3, 2.5 + some ceiling] — min 1.3
    newEaseFactor = math.max(1.3, newEaseFactor);

    final nextReview = DateTime.now().toUtc().add(
          Duration(days: newIntervalDays),
        );

    return Sm2Result(
      repetitions: newRepetitions,
      easeFactor: newEaseFactor,
      intervalDays: newIntervalDays,
      nextReviewAt: nextReview,
    );
  }
}

/// Immutable result of an SM-2 calculation.
class Sm2Result {
  const Sm2Result({
    required this.repetitions,
    required this.easeFactor,
    required this.intervalDays,
    required this.nextReviewAt,
  });

  final int repetitions;
  final double easeFactor;
  final int intervalDays;
  final DateTime nextReviewAt;

  @override
  String toString() => 'Sm2Result('
      'reps=$repetitions, ef=${easeFactor.toStringAsFixed(2)}, '
      'interval=${intervalDays}d, next=${nextReviewAt.toIso8601String()})';
}
