/**
 * Edge Function: enrich-core
 *
 * Single-item enrichment for manual card saves (fast path).
 * Returns core fields: correction, nuance, examples.
 * Background full enrichment (synonyms, confusables, etc.) is handled
 * by the analyze-session function.
 *
 * Expects: { text: string, context_snippet: string, card_type: string }
 */

import { callAiJson } from '../_shared/ai_provider.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface EnrichCoreRequest {
  text: string;
  context_snippet: string;
  card_type?: 'sentence' | 'word' | 'phrase';
}

interface EnrichCoreResponse {
  original_text: string;
  corrected_text: string | null;
  nuance_explanation: string;
  alternative_examples: string[];
  error_category: 'grammar' | 'unnatural' | 'vocab' | null;
  card_type: 'sentence' | 'word' | 'phrase';
}

const SYSTEM_PROMPT = `You are an expert English linguist and teacher.
Your task is to provide rich, educational context for English words, phrases, or sentences.
Always respond with valid JSON only — no markdown, no extra text.`;

function buildPrompt(req: EnrichCoreRequest): string {
  return `Analyse the following English ${req.card_type ?? 'sentence'} and provide educational context.

TEXT: "${req.text}"
CONTEXT: "${req.context_snippet}"

Respond with JSON in this exact schema:
{
  "original_text": "<the original text>",
  "corrected_text": "<corrected version, or null if already correct>",
  "nuance_explanation": "<2-3 sentences explaining the nuance, usage, and why the original may be wrong/interesting>",
  "alternative_examples": ["<example 1>", "<example 2>", "<example 3>"],
  "error_category": "<'grammar' | 'unnatural' | 'vocab' | null>",
  "card_type": "<'sentence' | 'word' | 'phrase'>"
}

Rules:
- corrected_text is null ONLY if the original is perfectly natural and correct
- nuance_explanation must be clear, specific, and pedagogically useful
- alternative_examples must be distinct, natural sentences/uses
- error_category is null if the text is correct (user saved it for vocabulary, not correction)`;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const body = (await req.json()) as EnrichCoreRequest;

    if (!body.text) {
      return new Response(JSON.stringify({ error: 'text is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const result = await callAiJson<EnrichCoreResponse>(
      [{ role: 'user', content: buildPrompt(body) }],
      SYSTEM_PROMPT,
      512,
    );

    return new Response(JSON.stringify(result), {
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json',
      },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
