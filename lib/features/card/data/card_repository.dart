import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/powersync_database.dart' as ps_db;

const _uuid = Uuid();

// ---------------------------------------------------------------------------
// Enrich response model
// ---------------------------------------------------------------------------

class EnrichCoreResult {
  const EnrichCoreResult({
    required this.originalText,
    this.correctedText,
    required this.nuanceExplanation,
    required this.alternativeExamples,
    this.errorCategory,
    this.cardType = 'sentence',
  });

  final String originalText;
  final String? correctedText;
  final String nuanceExplanation;
  final List<String> alternativeExamples;
  final String? errorCategory;
  final String cardType;

  factory EnrichCoreResult.fromJson(Map<String, dynamic> json) =>
      EnrichCoreResult(
        originalText: json['original_text'] as String,
        correctedText: json['corrected_text'] as String?,
        nuanceExplanation: json['nuance_explanation'] as String,
        alternativeExamples:
            List<String>.from(json['alternative_examples'] as List? ?? []),
        errorCategory: json['error_category'] as String?,
        cardType: json['card_type'] as String? ?? 'sentence',
      );
}

// ---------------------------------------------------------------------------
// Card Repository
// ---------------------------------------------------------------------------

class CardRepository {

  /// Generates a normalised dedup key from the original text.
  static String dedupKey(String text) {
    final normalised = text.toLowerCase().trim().replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
    return sha1.convert(utf8.encode(normalised)).toString();
  }

  /// Checks if a card already exists for this user+text combination.
  /// Returns the existing card id if found, null otherwise.
  Future<String?> findExisting(String userId, String text) async {
    final key = dedupKey(text);
    final rows = await ps_db.db.getAll(
      'SELECT id FROM quiz_cards WHERE user_id = ? AND dedup_key = ?',
      [userId, key],
    );
    return rows.isEmpty ? null : rows.first['id'] as String;
  }

  /// Reinforces an existing card (increments reinforce_count, bumps review priority).
  Future<void> reinforceCard(String cardId) async {
    await ps_db.db.execute(
      '''UPDATE quiz_cards
         SET reinforce_count = reinforce_count + 1,
             next_review_at = datetime('now')
         WHERE id = ?''',
      [cardId],
    );
  }

  /// Saves a new card with core enrich data.
  /// Returns the new card id.
  Future<String> saveCard({
    required String userId,
    required String sessionId,
    required String sourceType,
    required String saveMode,
    required String contextSnippet,
    required EnrichCoreResult enrichResult,
  }) async {
    final id = _uuid.v4();
    final key = dedupKey(enrichResult.originalText);
    final now = DateTime.now().toUtc().toIso8601String();

    await ps_db.db.execute(
      '''INSERT INTO quiz_cards (
           id, user_id, session_id, source_type, card_type, save_mode, error_category,
           original_text, corrected_text, nuance_explanation, context_snippet,
           alternative_examples, synonyms, confusable_with, homonyms, collocations,
           register, enrich_status, dedup_key, reinforce_count,
           ease_factor, interval_days, repetitions, next_review_at, created_at
         ) VALUES (
           ?, ?, ?, ?, ?, ?, ?,
           ?, ?, ?, ?,
           ?, ?, ?, ?, ?,
           ?, ?, ?, ?,
           2.5, 0, 0, ?, ?
         )''',
      [
        id, userId, sessionId, sourceType, enrichResult.cardType, saveMode,
        enrichResult.errorCategory,
        enrichResult.originalText, enrichResult.correctedText,
        enrichResult.nuanceExplanation, contextSnippet,
        json.encode(enrichResult.alternativeExamples),
        '[]', '[]', '[]', '[]',
        null, 'core', key, 0,
        now, now,
      ],
    );

    return id;
  }

  /// Updates a card with full enrich data (background enrichment).
  Future<void> updateFullEnrich({
    required String cardId,
    required List<Map<String, String>> synonyms,
    required List<Map<String, String>> confusableWith,
    required List<Map<String, String>> homonyms,
    required List<String> collocations,
    String? register,
  }) async {
    await ps_db.db.execute(
      '''UPDATE quiz_cards
         SET synonyms = ?,
             confusable_with = ?,
             homonyms = ?,
             collocations = ?,
             register = ?,
             enrich_status = 'full'
         WHERE id = ?''',
      [
        json.encode(synonyms),
        json.encode(confusableWith),
        json.encode(homonyms),
        json.encode(collocations),
        register,
        cardId,
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Enrich service — calls Edge Functions
// ---------------------------------------------------------------------------

class EnrichService {
  final _client = Supabase.instance.client;

  /// Calls the `enrich-core` Edge Function for a single text.
  /// Used for manual saves (instant feedback).
  Future<EnrichCoreResult> enrichCore({
    required String text,
    required String contextSnippet,
    String cardType = 'sentence',
  }) async {
    final response = await _client.functions.invoke(
      'enrich-core',
      body: json.encode({
        'text': text,
        'context_snippet': contextSnippet,
        'card_type': cardType,
      }),
    );
    return EnrichCoreResult.fromJson(
      json.decode(response.data as String) as Map<String, dynamic>,
    );
  }
}

// ---------------------------------------------------------------------------
// Card service — orchestrates save flow (dedup + enrich)
// ---------------------------------------------------------------------------

class CardService {
  CardService(this._repo, this._enrichService);

  final CardRepository _repo;
  final EnrichService _enrichService;

  /// Saves a card manually (user-triggered).
  /// Returns the card id, or null if reinforced.
  Future<({String? cardId, bool reinforced})> saveManual({
    required String userId,
    required String sessionId,
    required String sourceType,
    required String text,
    required String contextSnippet,
    required String cardType,
  }) async {
    // Dedup check
    final existingId = await _repo.findExisting(userId, text);
    if (existingId != null) {
      await _repo.reinforceCard(existingId);
      return (cardId: existingId, reinforced: true);
    }

    // Core enrich (fast, for popup preview — already done by caller)
    final enrichResult = await _enrichService.enrichCore(
      text: text,
      contextSnippet: contextSnippet,
      cardType: cardType,
    );

    final cardId = await _repo.saveCard(
      userId: userId,
      sessionId: sessionId,
      sourceType: sourceType,
      saveMode: 'manual',
      contextSnippet: contextSnippet,
      enrichResult: enrichResult,
    );

    return (cardId: cardId, reinforced: false);
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final cardRepositoryProvider =
    Provider<CardRepository>((_) => CardRepository());

final enrichServiceProvider =
    Provider<EnrichService>((_) => EnrichService());

final cardServiceProvider = Provider<CardService>((ref) {
  return CardService(
    ref.watch(cardRepositoryProvider),
    ref.watch(enrichServiceProvider),
  );
});
