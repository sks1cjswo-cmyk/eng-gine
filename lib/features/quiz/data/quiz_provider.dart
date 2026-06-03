import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/powersync_database.dart' as ps_db;
import '../domain/quiz_card_model.dart';
import '../domain/sm2_algorithm.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

class QuizRepository {
  /// Watches cards due for review (next_review_at <= now).
  Stream<List<QuizCard>> watchDueCards(String userId) {
    final now = DateTime.now().toUtc().toIso8601String();
    return ps_db.db
        .watch(
          '''SELECT * FROM quiz_cards
             WHERE user_id = ?
               AND enrich_status != 'pending'
               AND next_review_at <= ?
             ORDER BY next_review_at ASC
             LIMIT 50''',
          parameters: [userId, now],
        )
        .map((rows) => rows.map(QuizCard.fromRow).toList());
  }

  /// Total due count (for badge).
  Stream<int> watchDueCount(String userId) {
    final now = DateTime.now().toUtc().toIso8601String();
    return ps_db.db
        .watch(
          '''SELECT COUNT(*) as cnt FROM quiz_cards
             WHERE user_id = ?
               AND enrich_status != 'pending'
               AND next_review_at <= ?''',
          parameters: [userId, now],
        )
        .map((rows) => (rows.first['cnt'] as int?) ?? 0);
  }

  /// Updates a card after a quiz response using SM-2.
  Future<void> gradeCard({
    required String cardId,
    required int quality,
    required QuizCard card,
  }) async {
    final result = Sm2Algorithm.calculate(
      currentRepetitions: card.repetitions,
      currentEaseFactor: card.easeFactor,
      currentIntervalDays: card.intervalDays,
      quality: quality,
    );

    final now = DateTime.now().toUtc().toIso8601String();
    await ps_db.db.execute(
      '''UPDATE quiz_cards
         SET ease_factor = ?,
             interval_days = ?,
             repetitions = ?,
             next_review_at = ?,
             last_reviewed_at = ?
         WHERE id = ?''',
      [
        result.easeFactor,
        result.intervalDays,
        result.repetitions,
        result.nextReviewAt.toIso8601String(),
        now,
        cardId,
      ],
    );
  }

  /// Streams all cards (for browsing / stats).
  Stream<List<QuizCard>> watchAllCards(String userId) {
    return ps_db.db
        .watch(
          '''SELECT * FROM quiz_cards
             WHERE user_id = ?
             ORDER BY created_at DESC''',
          parameters: [userId],
        )
        .map((rows) => rows.map(QuizCard.fromRow).toList());
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final quizRepositoryProvider =
    Provider<QuizRepository>((_) => QuizRepository());

final quizDueCardsProvider = StreamProvider<List<QuizCard>>((ref) {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return const Stream.empty();
  return ref.watch(quizRepositoryProvider).watchDueCards(userId);
});

final quizDueCountProvider = StreamProvider<int>((ref) {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return Stream.value(0);
  return ref.watch(quizRepositoryProvider).watchDueCount(userId);
});

// ---------------------------------------------------------------------------
// Quiz session controller
// ---------------------------------------------------------------------------

class QuizSessionState {
  const QuizSessionState({
    required this.cards,
    required this.currentIndex,
    required this.isAnswerRevealed,
    required this.gradedCount,
  });

  final List<QuizCard> cards;
  final int currentIndex;
  final bool isAnswerRevealed;
  final int gradedCount;

  QuizCard? get currentCard =>
      currentIndex < cards.length ? cards[currentIndex] : null;

  bool get isDone => currentIndex >= cards.length;

  QuizSessionState copyWith({
    List<QuizCard>? cards,
    int? currentIndex,
    bool? isAnswerRevealed,
    int? gradedCount,
  }) =>
      QuizSessionState(
        cards: cards ?? this.cards,
        currentIndex: currentIndex ?? this.currentIndex,
        isAnswerRevealed: isAnswerRevealed ?? this.isAnswerRevealed,
        gradedCount: gradedCount ?? this.gradedCount,
      );
}

class QuizSessionNotifier extends Notifier<QuizSessionState?> {
  @override
  QuizSessionState? build() => null;

  QuizRepository get _repo => ref.read(quizRepositoryProvider);

  /// Starts a quiz session with the given due cards.
  void startSession(List<QuizCard> cards) {
    if (cards.isEmpty) return;
    state = QuizSessionState(
      cards: cards,
      currentIndex: 0,
      isAnswerRevealed: false,
      gradedCount: 0,
    );
  }

  /// Reveals the answer for the current card.
  void revealAnswer() {
    state = state?.copyWith(isAnswerRevealed: true);
  }

  /// Grades the current card and advances to the next.
  Future<void> gradeCard(int quality) async {
    final current = state;
    if (current == null) return;
    final card = current.currentCard;
    if (card == null) return;

    await _repo.gradeCard(
      cardId: card.id,
      quality: quality,
      card: card,
    );

    state = current.copyWith(
      currentIndex: current.currentIndex + 1,
      isAnswerRevealed: false,
      gradedCount: current.gradedCount + 1,
    );
  }
}

final quizSessionProvider =
    NotifierProvider<QuizSessionNotifier, QuizSessionState?>(
  QuizSessionNotifier.new,
);
