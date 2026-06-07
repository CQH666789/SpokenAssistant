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
    feedback: 'Good attempt. Keep your pace steady, stress the key words, and finish the sentence with a clear final sound.',
    corrections: [
      {
        word: firstWord,
        issue: 'The first word may sound rushed.',
        suggestion: 'Start slightly slower and let the first consonant land clearly.'
      },
      {
        word: 'sentence rhythm',
        issue: 'Some phrases need a more natural rise and fall.',
        suggestion: 'Listen to the model voice, then repeat the sentence with one short pause in the middle.'
      }
    ],
    referenceAudioUrl: ''
  });
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}
