import 'package:powersync/powersync.dart';

/// PowerSync client-side SQLite schema.
/// Mirrors the Supabase Postgres schema (only columns used on the client).
/// PowerSync automatically creates the `id` TEXT column — do not declare it.
const schema = Schema([
  // ------------------------------------------------------------------
  // sessions
  // ------------------------------------------------------------------
  Table('sessions', [
    Column.text('user_id'),
    Column.text('source_type'),   // chat | journal | youtube
    Column.text('title'),
    Column.text('status'),        // active | ended | analyzing | analyzed | error
    Column.text('created_at'),
    Column.text('ended_at'),
  ], indexes: [
    Index('sessions_user_created', [
      IndexedColumn('user_id'),
      IndexedColumn.descending('created_at'),
    ]),
  ]),

  // ------------------------------------------------------------------
  // messages
  // ------------------------------------------------------------------
  Table('messages', [
    Column.text('session_id'),
    Column.text('user_id'),
    Column.text('role'),          // user | assistant
    Column.text('content'),
    Column.text('created_at'),
  ], indexes: [
    Index('messages_session', [
      IndexedColumn('session_id'),
      IndexedColumn('created_at'),
    ]),
  ]),

  // ------------------------------------------------------------------
  // quiz_cards
  // ------------------------------------------------------------------
  Table('quiz_cards', [
    Column.text('user_id'),
    Column.text('session_id'),
    Column.text('source_type'),        // chat | journal | youtube
    Column.text('card_type'),          // sentence | word | phrase
    Column.text('save_mode'),          // auto | manual
    Column.text('error_category'),     // grammar | unnatural | vocab | null

    Column.text('original_text'),
    Column.text('corrected_text'),
    Column.text('nuance_explanation'),
    Column.text('context_snippet'),

    // Rich background knowledge stored as JSON strings
    Column.text('alternative_examples'),   // JSON: string[]
    Column.text('synonyms'),               // JSON: [{expr, note}]
    Column.text('confusable_with'),        // JSON: [{expr, difference}]
    Column.text('homonyms'),               // JSON: [{word, meaning}]
    Column.text('collocations'),           // JSON: string[]
    Column.text('register'),              // formal | neutral | casual | slang

    Column.text('enrich_status'),          // pending | core | full | failed
    Column.text('dedup_key'),
    Column.integer('reinforce_count'),

    // SM-2 fields
    Column.real('ease_factor'),
    Column.integer('interval_days'),
    Column.integer('repetitions'),
    Column.text('next_review_at'),
    Column.text('last_reviewed_at'),
    Column.text('created_at'),
  ], indexes: [
    Index('quiz_cards_review', [
      IndexedColumn('user_id'),
      IndexedColumn('next_review_at'),
    ]),
    Index('quiz_cards_dedup', [
      IndexedColumn('user_id'),
      IndexedColumn('dedup_key'),
    ]),
  ]),

  // ------------------------------------------------------------------
  // articles (Phase 2 — synced but not actively used in Phase 1)
  // ------------------------------------------------------------------
  Table('articles', [
    Column.text('user_id'),
    Column.text('feed_subscription_id'),
    Column.text('source_url'),
    Column.text('title'),
    Column.text('author'),
    Column.text('clean_text'),
    Column.text('read_status'),   // unread | reading | completed
    Column.text('fetched_at'),
    Column.text('published_at'),
  ]),

  // ------------------------------------------------------------------
  // feed_subscriptions (Phase 2)
  // ------------------------------------------------------------------
  Table('feed_subscriptions', [
    Column.text('user_id'),
    Column.text('feed_url'),
    Column.text('title'),
    Column.text('last_polled_at'),
    Column.text('created_at'),
  ]),
]);
