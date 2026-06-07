import type { VercelRequest, VercelResponse } from '@vercel/node';

interface EvaluationPayload {
  sentenceId?: string;
  targetText?: string;
  locale?: string;
  audioPath?: string;
  durationMs?: number;
}

export default function handler(request: VercelRequest, response: VercelResponse) {
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
  const firstWord = payload.targetText.split(/\s+/)[0] || 'Opening';

  return response.status(200).json({
    transcript: payload.targetText,
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
    referenceAudioUrl: ''
  });
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}
