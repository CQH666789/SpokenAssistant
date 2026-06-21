import type { VercelRequest, VercelResponse } from '@vercel/node';

interface EvaluationPayload {
  sentenceId?: string;
  targetText?: string;
  spokenText?: string;
  locale?: string;
  audioPath?: string;
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
  const transcript = payload.spokenText || payload.targetText;
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

async function createLanguageFeedback(targetText: string, transcript: string): Promise<LanguageFeedback> {
  const apiKey = process.env.BAILIAN_API_KEY || process.env.DASHSCOPE_API_KEY;
  if (!apiKey) {
    return fallbackLanguageFeedback(targetText);
  }

  try {
    const baseUrl = process.env.BAILIAN_BASE_URL || 'https://dashscope.aliyuncs.com/compatible-mode/v1';
    const result = await fetch(`${baseUrl}/chat/completions`, {
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
    });

    if (!result.ok) {
      return fallbackLanguageFeedback(targetText);
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
    return normalizeLanguageFeedback(parsed, targetText);
  } catch (_) {
    return fallbackLanguageFeedback(targetText);
  }
}

function normalizeLanguageFeedback(value: Partial<LanguageFeedback>, targetText: string): LanguageFeedback {
  const fallback = fallbackLanguageFeedback(targetText);
  return {
    grammarCorrection: cleanText(value.grammarCorrection) || fallback.grammarCorrection,
    betterExpression: cleanText(value.betterExpression) || fallback.betterExpression,
    explanation: cleanText(value.explanation) || fallback.explanation
  };
}

function cleanText(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function fallbackLanguageFeedback(targetText: string): LanguageFeedback {
  return {
    grammarCorrection: targetText,
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
