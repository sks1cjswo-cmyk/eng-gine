/**
 * Shared AI provider abstraction for Edge Functions.
 *
 * Supported providers (set via AI_PROVIDER env var):
 *   - "claude"  → Anthropic Claude (default)  requires ANTHROPIC_API_KEY
 *   - "openai"  → OpenAI GPT                  requires OPENAI_API_KEY
 *   - "gemini"  → Google Gemini               requires GEMINI_API_KEY
 */

export type AiMessage = {
  role: 'user' | 'assistant' | 'system';
  content: string;
};

export type AiProvider = 'claude' | 'openai' | 'gemini';

const provider = (): AiProvider => {
  const p = Deno.env.get('AI_PROVIDER') ?? 'claude';
  return p as AiProvider;
};

// ---------------------------------------------------------------------------
// Claude (Anthropic)
// ---------------------------------------------------------------------------

async function callClaude(
  messages: AiMessage[],
  systemPrompt: string,
  stream: boolean,
  maxTokens = 1024,
): Promise<Response> {
  const apiKey = Deno.env.get('ANTHROPIC_API_KEY');
  if (!apiKey) throw new Error('ANTHROPIC_API_KEY not set');

  const userMessages = messages.filter((m) => m.role !== 'system');

  return await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'anthropic-beta': 'prompt-caching-2024-07-31',
    },
    body: JSON.stringify({
      model: Deno.env.get('CLAUDE_MODEL') ?? 'claude-sonnet-4-5',
      max_tokens: maxTokens,
      system: systemPrompt,
      messages: userMessages,
      stream,
    }),
  });
}

// ---------------------------------------------------------------------------
// OpenAI (GPT-4o / GPT-4o-mini)
// ---------------------------------------------------------------------------

async function callOpenAI(
  messages: AiMessage[],
  systemPrompt: string,
  stream: boolean,
  maxTokens = 1024,
): Promise<Response> {
  const apiKey = Deno.env.get('OPENAI_API_KEY');
  if (!apiKey) throw new Error('OPENAI_API_KEY not set');

  const allMessages = [
    { role: 'system', content: systemPrompt },
    ...messages.filter((m) => m.role !== 'system'),
  ];

  return await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: Deno.env.get('OPENAI_MODEL') ?? 'gpt-4o-mini',
      max_tokens: maxTokens,
      messages: allMessages,
      stream,
    }),
  });
}

// ---------------------------------------------------------------------------
// Gemini (Google)
// ---------------------------------------------------------------------------

async function callGemini(
  messages: AiMessage[],
  systemPrompt: string,
  stream: boolean,
  maxTokens = 1024,
): Promise<Response> {
  const apiKey = Deno.env.get('GEMINI_API_KEY');
  if (!apiKey) throw new Error('GEMINI_API_KEY not set');

  const model = Deno.env.get('GEMINI_MODEL') ?? 'gemini-2.0-flash';
  const contents = messages
    .filter((m) => m.role !== 'system')
    .map((m) => ({
      role: m.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: m.content }],
    }));

  const endpoint = stream
    ? `https://generativelanguage.googleapis.com/v1beta/models/${model}:streamGenerateContent?key=${apiKey}`
    : `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

  return await fetch(endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      system_instruction: { parts: [{ text: systemPrompt }] },
      contents,
      generationConfig: { maxOutputTokens: maxTokens },
    }),
  });
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Calls the configured AI provider.
 * Returns a raw Response (streaming or full, depending on `stream` flag).
 */
export async function callAi(
  messages: AiMessage[],
  systemPrompt: string,
  options: { stream?: boolean; maxTokens?: number } = {},
): Promise<Response> {
  const { stream = false, maxTokens = 1024 } = options;
  const p = provider();

  if (p === 'openai') return callOpenAI(messages, systemPrompt, stream, maxTokens);
  if (p === 'gemini') return callGemini(messages, systemPrompt, stream, maxTokens);
  return callClaude(messages, systemPrompt, stream, maxTokens);
}

/**
 * Non-streaming call that parses and returns JSON from the AI response.
 */
export async function callAiJson<T>(
  messages: AiMessage[],
  systemPrompt: string,
  maxTokens = 1024,
): Promise<T> {
  const response = await callAi(messages, systemPrompt, {
    stream: false,
    maxTokens,
  });

  if (!response.ok) {
    const err = await response.text();
    throw new Error(`AI API error ${response.status}: ${err}`);
  }

  const data = await response.json();
  const p = provider();

  let text: string;
  if (p === 'openai') {
    text = data.choices?.[0]?.message?.content ?? '';
  } else if (p === 'gemini') {
    text = data.candidates?.[0]?.content?.parts?.[0]?.text ?? '';
  } else {
    // Claude
    text = data.content?.[0]?.text ?? '';
  }

  const cleaned = text.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();
  try {
    return JSON.parse(cleaned) as T;
  } catch {
    throw new Error(`Failed to parse AI response as JSON: ${cleaned}`);
  }
}

/**
 * Extracts streaming delta text from an SSE line for the active provider.
 * Returns null if the line is not a content delta.
 * Returns '[DONE]' string when the stream is complete.
 */
export function extractStreamDelta(
  line: string,
): string | null {
  if (!line.startsWith('data: ')) return null;

  const data = line.slice(6).trim();
  if (data === '[DONE]') return '[DONE]';

  const p = provider();

  try {
    const parsed = JSON.parse(data);

    if (p === 'openai') {
      const delta = parsed.choices?.[0]?.delta?.content;
      return delta ?? null;
    } else if (p === 'gemini') {
      return parsed.candidates?.[0]?.content?.parts?.[0]?.text ?? null;
    } else {
      // Claude
      if (parsed.type === 'content_block_delta') {
        return parsed.delta?.text ?? null;
      }
      if (parsed.type === 'message_stop') return '[DONE]';
      return null;
    }
  } catch {
    return null;
  }
}
