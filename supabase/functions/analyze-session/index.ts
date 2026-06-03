/**
 * Edge Function: analyze-session
 *
 * Background analysis of a completed chat session.
 * 1. Fetches all messages for the session
 * 2. Extracts top 5-7 cards (grammar errors, unnatural expressions, vocab)
 * 3. For each card: dedup check → core enrich → INSERT into quiz_cards
 * 4. Full enrich (synonyms, confusables, etc.) for all new cards
 * 5. Updates session status to 'analyzed'
 *
 * Expects: { session_id: string }
 * Called by the Flutter app after session.status = 'ended'
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { callAiJson } from '../_shared/ai_provider.ts';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface Message {
  role: string;
  content: string;
}

interface ExtractedCard {
  original_text: string;
  error_category: 'grammar' | 'unnatural' | 'vocab';
  card_type: 'sentence' | 'word' | 'phrase';
  priority_score: number; // 1–10 (higher = more valuable)
}

interface CoreEnrichedCard {
  original_text: string;
  corrected_text: string | null;
  nuance_explanation: string;
  alternative_examples: string[];
  error_category: 'grammar' | 'unnatural' | 'vocab' | null;
  card_type: 'sentence' | 'word' | 'phrase';
}

interface FullEnrichResult {
  synonyms: Array<{ expr: string; note: string }>;
  confusable_with: Array<{ expr: string; difference: string }>;
  homonyms: Array<{ word: string; meaning: string }>;
  collocations: string[];
  register: 'formal' | 'neutral' | 'casual' | 'slang' | null;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const MAX_CARDS = 7;

async function dedupKey(text: string): Promise<string> {
  const normalised = text.toLowerCase().trim().replace(/\s+/g, ' ');
  const msgBuffer = new TextEncoder().encode(normalised);
  const hashBuffer = await crypto.subtle.digest('SHA-1', msgBuffer);
  return Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

// ---------------------------------------------------------------------------
// Step 1: Extract card candidates from conversation
// ---------------------------------------------------------------------------

async function extractCandidates(
  messages: Message[],
): Promise<ExtractedCard[]> {
  const conversation = messages
    .map((m) => `${m.role.toUpperCase()}: ${m.content}`)
    .join('\n\n');

  const prompt = `Analyse this English conversation and identify the most educationally valuable items to save as flashcards.

CONVERSATION:
${conversation}

Extract up to ${MAX_CARDS} items. Focus on:
1. Grammar errors the user made
2. Unnatural or awkward expressions
3. Useful vocabulary/phrases worth remembering

Return JSON array (sorted by priority, highest first):
[
  {
    "original_text": "<exact text from user's message>",
    "error_category": "<'grammar' | 'unnatural' | 'vocab'>",
    "card_type": "<'sentence' | 'word' | 'phrase'>",
    "priority_score": <1-10>
  }
]

Rules:
- Only include items from the USER's messages (not assistant corrections)
- Prioritise actual errors over interesting vocabulary
- For 'vocab': include useful expressions the user used correctly but should study deeply
- Return empty array [] if no significant items found`;

  return await callAiJson<ExtractedCard[]>(
    [{ role: 'user', content: prompt }],
    'You are an expert English teacher. Return only valid JSON arrays.',
    1024,
  );
}

// ---------------------------------------------------------------------------
// Step 2: Core enrich for a single extracted card
// ---------------------------------------------------------------------------

async function coreEnrich(
  card: ExtractedCard,
  contextSnippet: string,
): Promise<CoreEnrichedCard> {
  const prompt = `Provide educational enrichment for this English ${card.card_type}.

TEXT: "${card.original_text}"
CONTEXT: "${contextSnippet}"
ERROR TYPE: ${card.error_category}

Return JSON:
{
  "original_text": "${card.original_text}",
  "corrected_text": "<corrected version or null if correct>",
  "nuance_explanation": "<2-3 sentences>",
  "alternative_examples": ["<3 examples>"],
  "error_category": "${card.error_category}",
  "card_type": "${card.card_type}"
}`;

  return await callAiJson<CoreEnrichedCard>(
    [{ role: 'user', content: prompt }],
    'You are an expert English linguist. Return only valid JSON.',
    512,
  );
}

// ---------------------------------------------------------------------------
// Step 3: Full enrich (synonyms, confusables, etc.)
// ---------------------------------------------------------------------------

async function fullEnrich(
  originalText: string,
  cardType: string,
): Promise<FullEnrichResult> {
  const prompt = `Provide deep linguistic context for this English ${cardType}: "${originalText}"

Return JSON:
{
  "synonyms": [{"expr": "<similar expression>", "note": "<usage difference>"}],
  "confusable_with": [{"expr": "<often confused with>", "difference": "<key difference>"}],
  "homonyms": [{"word": "<same sound>", "meaning": "<different meaning>"}],
  "collocations": ["<word1 word2>", "<word3 word4>"],
  "register": "<'formal' | 'neutral' | 'casual' | 'slang' | null>"
}

Rules:
- synonyms: 2-3 most relevant similar expressions
- confusable_with: 1-2 expressions learners commonly mix up with this
- homonyms: only if genuinely relevant (can be empty array)
- collocations: 3-5 natural word combinations
- register: the formality level of the original text`;

  return await callAiJson<FullEnrichResult>(
    [{ role: 'user', content: prompt }],
    'You are an expert English linguist. Return only valid JSON.',
    512,
  );
}

// ---------------------------------------------------------------------------
// Main handler
// ---------------------------------------------------------------------------

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'authorization, content-type',
      },
    });
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  try {
    const { session_id } = await req.json();
    if (!session_id) {
      return new Response(JSON.stringify({ error: 'session_id required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // Fetch session
    const { data: session, error: sessionError } = await supabase
      .from('sessions')
      .select('id, user_id, status')
      .eq('id', session_id)
      .single();

    if (sessionError || !session) {
      return new Response(JSON.stringify({ error: 'Session not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // Fetch messages
    const { data: messages, error: msgError } = await supabase
      .from('messages')
      .select('role, content')
      .eq('session_id', session_id)
      .order('created_at', { ascending: true });

    if (msgError || !messages?.length) {
      await supabase
        .from('sessions')
        .update({ status: 'analyzed' })
        .eq('id', session_id);
      return new Response(JSON.stringify({ cards_created: 0 }), {
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // Mark as analyzing
    await supabase
      .from('sessions')
      .update({ status: 'analyzing' })
      .eq('id', session_id);

    // Step 1: Extract candidates
    let candidates = await extractCandidates(messages);
    candidates = candidates
      .sort((a, b) => b.priority_score - a.priority_score)
      .slice(0, MAX_CARDS);

    let cardsCreated = 0;
    const newCardIds: string[] = [];

    for (const candidate of candidates) {
      // Dedup check
      const key = await dedupKey(candidate.original_text);

      const { data: existing } = await supabase
        .from('quiz_cards')
        .select('id')
        .eq('user_id', session.user_id)
        .eq('dedup_key', key)
        .single();

      if (existing) {
        // Reinforce existing card
        await supabase
          .from('quiz_cards')
          .update({
            reinforce_count: supabase.rpc('increment', { x: 1 }),
            next_review_at: new Date().toISOString(),
          })
          .eq('id', existing.id);
        continue;
      }

      // Find context (the message containing this text)
      const contextMsg = messages.find((m) =>
        m.content.includes(candidate.original_text),
      );
      const contextSnippet = contextMsg?.content ?? candidate.original_text;

      // Step 2: Core enrich
      const coreResult = await coreEnrich(candidate, contextSnippet);

      // Insert card with core data
      const now = new Date().toISOString();
      const { data: inserted } = await supabase
        .from('quiz_cards')
        .insert({
          user_id: session.user_id,
          session_id: session_id,
          source_type: 'chat',
          card_type: coreResult.card_type,
          save_mode: 'auto',
          error_category: coreResult.error_category,
          original_text: coreResult.original_text,
          corrected_text: coreResult.corrected_text,
          nuance_explanation: coreResult.nuance_explanation,
          context_snippet: contextSnippet,
          alternative_examples: coreResult.alternative_examples,
          synonyms: [],
          confusable_with: [],
          homonyms: [],
          collocations: [],
          enrich_status: 'core',
          dedup_key: key,
          reinforce_count: 0,
          ease_factor: 2.5,
          interval_days: 0,
          repetitions: 0,
          next_review_at: now,
          created_at: now,
        })
        .select('id')
        .single();

      if (inserted?.id) {
        newCardIds.push(inserted.id);
        cardsCreated++;
      }
    }

    // Step 3: Full enrich for new cards (sequential to avoid rate limits)
    for (const cardId of newCardIds) {
      const { data: card } = await supabase
        .from('quiz_cards')
        .select('original_text, card_type')
        .eq('id', cardId)
        .single();

      if (!card) continue;

      try {
        const fullResult = await fullEnrich(card.original_text, card.card_type);
        await supabase
          .from('quiz_cards')
          .update({
            synonyms: fullResult.synonyms,
            confusable_with: fullResult.confusable_with,
            homonyms: fullResult.homonyms,
            collocations: fullResult.collocations,
            register: fullResult.register,
            enrich_status: 'full',
          })
          .eq('id', cardId);
      } catch {
        // Full enrich failed — card remains at 'core' status, which is acceptable
      }
    }

    // Mark session as analyzed
    await supabase
      .from('sessions')
      .update({ status: 'analyzed' })
      .eq('id', session_id);

    return new Response(
      JSON.stringify({ cards_created: cardsCreated, session_id }),
      {
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      },
    );
  } catch (e) {
    // Mark session as error on failure
    const { session_id } = await req.json().catch(() => ({}));
    if (session_id) {
      await supabase
        .from('sessions')
        .update({ status: 'error' })
        .eq('id', session_id);
    }

    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
