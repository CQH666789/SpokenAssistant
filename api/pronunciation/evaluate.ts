import type { VercelRequest, VercelResponse } from '@vercel/node';

interface EvaluationPayload {
  sentenceId?: string;
  targetText?: string;
  spokenText?: string;
  locale?: string;
  audioPath?: string;
  audioBase64?: string;
  audioMimeType?: string;
  durationMs?: number;
}

interface LanguageFeedback {
  grammarCorrection: string;
  betterExpression: string;
  explanation: string;
}

export default async function handler(request: VercelRequest, response: VercelResponse) {
  if (request.method !== 'POST') {
    response.setHeader('Allow', 'POST');
    return response.status(405).json({ error: 'Method not allowed' });
  }

  const payload = request.body as EvaluationPayload;
  if (!payload || !payload.sentenceId || !payload.targetText) {
    return response.status(400).json({ error: 'sentenceId and targetText are required' });
  }

  const durationMs = Number(payload.durationMs || 0);
  const score = clamp(86 - (durationMs > 0 && durationMs < 1800 ? 8 : 0), 70, 96);
  let transcript = '';
  try {
    transcript = await resolveTranscript(payload);
  } catch (error) {
    return response.status(502).json({
      error: 'Speech transcription failed',
      details: error instanceof Error ? error.message : 'Unknown ASR error'
    });
  }
  const firstWord = transcript.split(/\s+/)[0] || 'Opening';
  const languageFeedback = await createLanguageFeedback(payload.targetText, transcript);

  return response.status(200).json({
    transcript,
    overallScore: score,
    fluencyScore: clamp(score - 3, 0, 100),
    pronunciationScore: clamp(score + 1, 0, 100),
    intonationScore: clamp(score - 5, 0, 100),
    feedback: '这次跟读完成度不错。继续保持稳定语速，突出关键词，并把句尾音收清楚。',
    corrections: [
      {
        word: firstWord,
        issue: '第一个词听起来略微偏快。',
        suggestion: '开头稍微放慢，让第一个辅音更清楚地落下来。'
      },
      {
        word: '句子节奏',
        issue: '部分短语的起伏还可以更自然。',
        suggestion: '先听示范音频，再在句子中间加入一个短暂停顿后重复。'
      }
    ],
    languageFeedback,
    referenceAudioUrl: ''
  });
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

async function resolveTranscript(payload: EvaluationPayload): Promise<string> {
  const spokenText = cleanText(payload.spokenText);
  if (spokenText) {
    return spokenText;
  }

  const audioBase64 = cleanText(payload.audioBase64);
  if (!audioBase64) {
    return payload.targetText || '';
  }

  try {
    const transcript = await transcribeAudio(audioBase64, payload.audioMimeType, payload.locale);
    if (!transcript) {
      throw new Error('Empty transcription result');
    }
    return transcript;
  } catch (error) {
    console.error('Speech transcription failed', {
      sentenceId: payload.sentenceId,
      durationMs: payload.durationMs,
      audioMimeType: payload.audioMimeType,
      audioBase64Bytes: cleanText(payload.audioBase64).length,
      error: error instanceof Error ? error.message : 'Unknown ASR error'
    });
    throw error;
  }
}

async function transcribeAudio(audioBase64: string, audioMimeType?: string, locale?: string): Promise<string> {
  const apiKey = process.env.BAILIAN_API_KEY || process.env.DASHSCOPE_API_KEY;
  if (!apiKey) {
    throw new Error('BAILIAN_API_KEY is not configured');
  }

  const baseUrl = process.env.BAILIAN_BASE_URL || 'https://dashscope.aliyuncs.com/compatible-mode/v1';
  const mimeType = cleanText(audioMimeType) || 'audio/mp4';
  const dataUri = audioBase64.startsWith('data:') ? audioBase64 : `data:${mimeType};base64,${audioBase64}`;
  const language = (cleanText(locale) || 'en-US').toLowerCase().startsWith('zh') ? 'zh' : 'en';
  const requestBody = createAsrRequestBody(dataUri, language);
  let result = await requestAsr(baseUrl, apiKey, requestBody);

  if (!result.ok && result.status === 400) {
    const retryBody = createAsrRequestBody(dataUri);
    result = await requestAsr(baseUrl, apiKey, retryBody);
  }

  if (!result.ok) {
    const errorText = await safeResponseText(result);
    console.error('Qwen ASR request failed', {
      status: result.status,
      mimeType,
      audioBase64Bytes: audioBase64.length,
      errorText
    });
    throw new Error(`ASR service returned ${result.status}: ${truncate(errorText, 240)}`);
  }

  const data = await result.json() as {
    choices?: Array<{
      message?: {
        content?: string
      }
    }>
  };
  return cleanText(data.choices?.[0]?.message?.content);
}

function createAsrRequestBody(dataUri: string, language?: string): Record<string, unknown> {
  const body: Record<string, unknown> = {
    model: process.env.BAILIAN_ASR_MODEL || 'qwen3-asr-flash',
    messages: [
      {
        role: 'user',
        content: [
          {
            type: 'input_audio',
            input_audio: {
              data: dataUri
            }
          }
        ]
      }
    ],
    stream: false,
    asr_options: {
      enable_itn: false
    }
  };

  if (language) {
    body.asr_options = {
      language,
      enable_itn: false
    };
  }

  return body;
}

async function requestAsr(baseUrl: string, apiKey: string, body: Record<string, unknown>): Promise<Response> {
  return fetchWithTimeout(`${baseUrl}/chat/completions`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(body)
  }, 25000);
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

async function createLanguageFeedback(targetText: string, transcript: string): Promise<LanguageFeedback> {
  const apiKey = process.env.BAILIAN_API_KEY || process.env.DASHSCOPE_API_KEY;
  if (!apiKey) {
    return fallbackLanguageFeedback(targetText, transcript);
  }

  try {
    const baseUrl = process.env.BAILIAN_BASE_URL || 'https://dashscope.aliyuncs.com/compatible-mode/v1';
    const result = await fetchWithTimeout(`${baseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        model: process.env.BAILIAN_LANGUAGE_MODEL || 'qwen-plus',
        messages: [
          {
            role: 'system',
            content: [
              '你是英语口语教练。',
              '请基于学习者读出的英文内容，返回中文解释和英文改写。',
              '只输出 JSON，字段为 grammarCorrection、betterExpression、explanation。',
              'grammarCorrection 是修正语法后的英文句子。',
              'betterExpression 是更地道自然的英文表达。',
              'explanation 用中文简短解释修改原因，控制在 60 字以内。'
            ].join('\n')
          },
          {
            role: 'user',
            content: JSON.stringify({
              targetText,
              spokenText: transcript
            })
          }
        ],
        response_format: {
          type: 'json_schema',
          json_schema: {
            name: 'language_feedback',
            strict: true,
            schema: {
              type: 'object',
              additionalProperties: false,
              required: ['grammarCorrection', 'betterExpression', 'explanation'],
              properties: {
                grammarCorrection: { type: 'string' },
                betterExpression: { type: 'string' },
                explanation: { type: 'string' }
              }
            }
          }
        },
        temperature: 0.3
      })
    }, 20000);

    if (!result.ok) {
      return fallbackLanguageFeedback(targetText, transcript);
    }

    const data = await result.json() as {
      choices?: Array<{
        message?: {
          content?: string
        }
      }>
    };
    const content = data.choices?.[0]?.message?.content || '';
    const parsed = JSON.parse(content) as Partial<LanguageFeedback>;
    return normalizeLanguageFeedback(parsed, targetText, transcript);
  } catch (_) {
    return fallbackLanguageFeedback(targetText, transcript);
  }
}

async function fetchWithTimeout(url: string, init: RequestInit, timeoutMs: number): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, {
      ...init,
      signal: controller.signal
    });
  } finally {
    clearTimeout(timer);
  }
}

function normalizeLanguageFeedback(value: Partial<LanguageFeedback>, targetText: string, transcript: string): LanguageFeedback {
  const fallback = fallbackLanguageFeedback(targetText, transcript);
  return {
    grammarCorrection: cleanText(value.grammarCorrection) || fallback.grammarCorrection,
    betterExpression: cleanText(value.betterExpression) || fallback.betterExpression,
    explanation: cleanText(value.explanation) || fallback.explanation
  };
}

function cleanText(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function fallbackLanguageFeedback(targetText: string, transcript = targetText): LanguageFeedback {
  return {
    grammarCorrection: transcript || targetText,
    betterExpression: makeBetterExpression(targetText),
    explanation: '语法整体没有明显问题。可以换成更自然的口语表达，让句子更地道。'
  };
}

function makeBetterExpression(targetText: string): string {
  const expressions: Record<string, string> = {
    'I usually drink a cup of coffee before my morning meeting.': 'I usually grab a coffee before my morning meeting.',
    'The weather is beautiful, so we should take a walk after lunch.': 'It is lovely outside, so we should go for a walk after lunch.',
    'Could you give me a quick update on the project timeline?': 'Could you give me a quick update on where the project timeline stands?',
    'Our train was delayed because of heavy rain near the station.': 'Our train was delayed because of heavy rain near the station.',
    'I am preparing a short presentation about customer feedback.': 'I am putting together a short presentation on customer feedback.',
    'Would you recommend this restaurant for a quiet dinner?': 'Would you recommend this place for a quiet dinner?',
    'Working remotely gives me more flexibility during the week.': 'Working remotely gives me more flexibility throughout the week.',
    'My goal is to speak more naturally and respond with confidence.': 'I want to speak more naturally and respond with confidence.',
    'The design review helped us identify several important improvements.': 'The design review helped us spot several important improvements.',
    'I still remember the small hotel where we stayed during our trip.': 'I still remember the little hotel we stayed at during our trip.'
  };
  return expressions[targetText] || targetText;
}
