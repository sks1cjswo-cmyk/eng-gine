/**
 * Edge Function: chat
 *
 * Streams AI chat responses via SSE (Server-Sent Events).
 * Expects: { session_id: string, messages: [{role, content}] }
 * Returns: SSE stream of `data: {"delta":"<token>"}` chunks, ending with `data: [DONE]`
 *
 * Provider is selected by AI_PROVIDER env var: "claude" | "openai" | "gemini"
 */

import { callAi, extractStreamDelta } from '../_shared/ai_provider.ts';

const SYSTEM_PROMPT = `You are a friendly and knowledgeable English conversation partner.
Your role is to have natural conversations in English, helping the user practice.
- Respond naturally and engagingly
- Use clear, well-structured English
- When you notice a clear grammatical error or very unnatural expression in the user's message,
  briefly and gently correct it in your reply (e.g. "Just to note: 'I have went' → 'I have gone'")
- Keep corrections concise — do not over-correct; focus on significant errors only
- Adapt your vocabulary complexity to the user's level`;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { messages } = await req.json();

    if (!messages || !Array.isArray(messages)) {
      return new Response(JSON.stringify({ error: 'messages required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const aiResponse = await callAi(messages, SYSTEM_PROMPT, {
      stream: true,
      maxTokens: 2048,
    });

    if (!aiResponse.ok) {
      const err = await aiResponse.text();
      return new Response(JSON.stringify({ error: err }), {
        status: 502,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const reader = aiResponse.body!.getReader();
    const decoder = new TextDecoder();

    const stream = new ReadableStream({
      async start(controller) {
        let buffer = '';
        const enqueue = (text: string) =>
          controller.enqueue(new TextEncoder().encode(text));

        try {
          while (true) {
            const { done, value } = await reader.read();
            if (done) break;

            buffer += decoder.decode(value, { stream: true });
            const lines = buffer.split('\n');
            buffer = lines.pop() ?? '';

            for (const line of lines) {
              const delta = extractStreamDelta(line);
              if (delta === null) continue;
              if (delta === '[DONE]') {
                enqueue('data: [DONE]\n\n');
              } else {
                enqueue(`data: ${JSON.stringify({ delta })}\n\n`);
              }
            }
          }
          // Flush remaining buffer
          if (buffer) {
            const delta = extractStreamDelta(buffer);
            if (delta && delta !== '[DONE]') {
              enqueue(`data: ${JSON.stringify({ delta })}\n\n`);
            }
          }
          enqueue('data: [DONE]\n\n');
        } finally {
          controller.close();
        }
      },
    });

    return new Response(stream, {
      headers: {
        ...corsHeaders,
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
      },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
