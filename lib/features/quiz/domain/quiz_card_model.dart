import 'dart:convert';

/// Represents a quiz card loaded from the local SQLite database.
class QuizCard {
  const QuizCard({
    required this.id,
    required this.userId,
    this.sessionId,
    required this.sourceType,
    required this.cardType,
    required this.saveMode,
    this.errorCategory,
    required this.originalText,
    this.correctedText,
    this.nuanceExplanation,
    this.contextSnippet,
    required this.alternativeExamples,
    required this.synonyms,
    required this.confusableWith,
    required this.homonyms,
    required this.collocations,
    this.register,
    required this.enrichStatus,
    required this.dedupKey,
    required this.reinforceCount,
    required this.easeFactor,
    required this.intervalDays,
    required this.repetitions,
    required this.nextReviewAt,
    this.lastReviewedAt,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String? sessionId;
  final String sourceType;   // chat | journal | youtube
  final String cardType;     // sentence | word | phrase
  final String saveMode;     // auto | manual
  final String? errorCategory;

  final String originalText;
  final String? correctedText;
  final String? nuanceExplanation;
  final String? contextSnippet;

  // Rich background knowledge
  final List<String> alternativeExamples;
  final List<Map<String, String>> synonyms;
  final List<Map<String, String>> confusableWith;
  final List<Map<String, String>> homonyms;
  final List<String> collocations;
  final String? register;

  final String enrichStatus;  // pending | core | full | failed
  final String dedupKey;
  final int reinforceCount;

  // SM-2 fields
  final double easeFactor;
  final int intervalDays;
  final int repetitions;
  final DateTime nextReviewAt;
  final DateTime? lastReviewedAt;
  final DateTime createdAt;

  factory QuizCard.fromRow(Map<String, dynamic> row) {
    List<String> parseStringList(dynamic value) {
      if (value == null || value == '') return [];
      try {
        return List<String>.from(json.decode(value as String));
      } catch (_) {
        return [];
      }
    }

    List<Map<String, String>> parseMapList(dynamic value) {
      if (value == null || value == '') return [];
      try {
        final list = json.decode(value as String) as List;
        return list
            .map((e) => Map<String, String>.from(e as Map))
            .toList();
      } catch (_) {
        return [];
      }
    }

    return QuizCard(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      sessionId: row['session_id'] as String?,
      sourceType: row['source_type'] as String,
      cardType: row['card_type'] as String,
      saveMode: row['save_mode'] as String,
      errorCategory: row['error_category'] as String?,
      originalText: row['original_text'] as String,
      correctedText: row['corrected_text'] as String?,
      nuanceExplanation: row['nuance_explanation'] as String?,
      contextSnippet: row['context_snippet'] as String?,
      alternativeExamples: parseStringList(row['alternative_examples']),
      synonyms: parseMapList(row['synonyms']),
      confusableWith: parseMapList(row['confusable_with']),
      homonyms: parseMapList(row['homonyms']),
      collocations: parseStringList(row['collocations']),
      register: row['register'] as String?,
      enrichStatus: row['enrich_status'] as String,
      dedupKey: row['dedup_key'] as String,
      reinforceCount: (row['reinforce_count'] as int?) ?? 0,
      easeFactor: (row['ease_factor'] as num?)?.toDouble() ?? 2.5,
      intervalDays: (row['interval_days'] as int?) ?? 0,
      repetitions: (row['repetitions'] as int?) ?? 0,
      nextReviewAt: DateTime.parse(row['next_review_at'] as String),
      lastReviewedAt: row['last_reviewed_at'] != null
          ? DateTime.parse(row['last_reviewed_at'] as String)
          : null,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}
