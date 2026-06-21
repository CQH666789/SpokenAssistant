import type { VercelRequest, VercelResponse } from '@vercel/node';

interface RefreshSentencePayload {
  level?: string;
  excludeText?: string;
}

interface TrainingSentence {
  id: string;
  text: string;
  level: string;
  focus: string;
}

const LEVELS = ['A2', 'B1', 'B2'];
const FOCUS_VALUES = [
  'linking sounds',
  'sentence rhythm',
  'question intonation',
  'past tense endings',
  'word stress',
  'polite tone',
  'vowel clarity',
  'natural pauses',
  'multi-syllable words',
  'connected speech'
];

export default async function handler(request: VercelRequest, response: VercelResponse) {
  if (request.method !== 'POST') {
    response.setHeader('Allow', 'POST');
    return response.status(405).json({ error: 'Method not allowed' });
  }

  const payload = request.body as RefreshSentencePayload;
  const level = normalizeLevel(payload?.level);
  const excludeText = cleanText(payload?.excludeText);

  try {
    const sentence = await createSentence(level, excludeText);
    return response.status(200).json(sentence);
  } catch (error) {
    console.error('Sentence refresh failed', {
      level,
      error: error instanceof Error ? error.message : 'Unknown sentence refresh error'
    });
    return response.status(502).json({
      error: 'Sentence refresh failed',
      details: error instanceof Error ? error.message : 'Unknown sentence refresh error'
    });
  }
}

async function createSentence(level: string, excludeText: string): Promise<TrainingSentence> {
  const apiKey = process.env.BAILIAN_API_KEY || process.env.DASHSCOPE_API_KEY;
  if (!apiKey) {
    throw new Error('BAILIAN_API_KEY is not configured');
  }

  const baseUrl = process.env.BAILIAN_BASE_URL || 'https://dashscope.aliyuncs.com/compatible-mode/v1';
  const targetLevel = level === '全部' ? pickLevel() : level;
  let result = await requestSentence(baseUrl, apiKey, targetLevel, excludeText, true);
  if (!result.ok && result.status === 400) {
    result = await requestSentence(baseUrl, apiKey, targetLevel, excludeText, false);
  }

  if (!result.ok) {
    const errorText = await safeResponseText(result);
    throw new Error(`Sentence service returned ${result.status}: ${truncate(errorText, 240)}`);
  }

  const data = await result.json() as {
    choices?: Array<{
      message?: {
        content?: string
      }
    }>
  };
  return normalizeSentence(parseSentence(cleanText(data.choices?.[0]?.message?.content)), targetLevel);
}

async function requestSentence(
  baseUrl: string,
  apiKey: string,
  level: string,
  excludeText: string,
  useJsonMode: boolean
): Promise<Response> {
  const body: Record<string, unknown> = {
    model: process.env.BAILIAN_LANGUAGE_MODEL || 'qwen-plus',
    messages: [
      {
        role: 'system',
        content: 'You create short English speaking-practice sentences for a Chinese learning app. Return valid JSON only.'
      },
      {
        role: 'user',
        content: [
          `Generate one fresh ${level} English sentence for shadowing practice.`,
          'Requirements:',
          '- 8 to 16 words.',
          '- Natural everyday or workplace English.',
          '- Not a quote, not a tongue twister.',
          `- Avoid this sentence: "${excludeText}".`,
          `- Pick one focus from: ${FOCUS_VALUES.join(', ')}.`,
          'Return exactly this JSON shape: {"text":"...","level":"A2|B1|B2","focus":"..."}'
        ].join('\n')
      }
    ],
    temperature: 0.9,
    stream: false
  };

  if (useJsonMode) {
    body.response_format = {
      type: 'json_object'
    };
  }

  return fetchWithTimeout(`${baseUrl}/chat/completions`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(body)
  }, 30000);
}

function normalizeSentence(value: Partial<TrainingSentence>, requestedLevel: string): TrainingSentence {
  const text = cleanText(value.text);
  if (!text) {
    throw new Error('Sentence service returned empty text');
  }

  const level = LEVELS.includes(cleanText(value.level)) ? cleanText(value.level) : requestedLevel;
  const focus = FOCUS_VALUES.includes(cleanText(value.focus)) ? cleanText(value.focus) : 'sentence rhythm';
  return {
    id: `generated-${Date.now()}`,
    text,
    level,
    focus
  };
}

function parseSentence(content: string): Partial<TrainingSentence> {
  try {
    return JSON.parse(content) as Partial<TrainingSentence>;
  } catch (_) {
    const match = content.match(/\{[\s\S]*\}/);
    if (!match) {
      throw new Error('Sentence service did not return JSON');
    }
    return JSON.parse(match[0]) as Partial<TrainingSentence>;
  }
}

function normalizeLevel(value?: string): string {
  const level = cleanText(value);
  return LEVELS.includes(level) ? level : '全部';
}

function pickLevel(): string {
  return LEVELS[Math.floor(Math.random() * LEVELS.length)];
}

function cleanText(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

async function safeResponseText(response: Response): Promise<string> {
  try {
    return await response.text();
  } catch (_) {
    return '';
  }
}

function truncate(value: string, maxLength: number): string {
  return value.length > maxLength ? `${value.slice(0, maxLength)}...` : value;
}

async function fetchWithTimeout(url: string, init: RequestInit, timeoutMs: number): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, {
      ...init,
      signal: controller.signal
    });
  } finally {
    clearTimeout(timeout);
  }
}
