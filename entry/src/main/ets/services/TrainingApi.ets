import { http } from '@kit.NetworkKit';
import type { EvaluationResult, RecordingResult, TrainingSentence } from '../models/TrainingModels';

const API_BASE_URL = '';

export class TrainingApi {
  static async evaluate(sentence: TrainingSentence, recording: RecordingResult): Promise<EvaluationResult> {
    if (!API_BASE_URL) {
      return TrainingApi.mockEvaluate(sentence, recording);
    }

    const request = http.createHttp();
    try {
      const response = await request.request(`${API_BASE_URL}/api/pronunciation/evaluate`, {
        method: http.RequestMethod.POST,
        expectDataType: http.HttpDataType.STRING,
        header: {
          'Content-Type': 'application/json'
        },
        extraData: JSON.stringify({
          sentenceId: sentence.id,
          targetText: sentence.text,
          locale: 'en-US',
          audioPath: recording.path,
          durationMs: recording.durationMs
        }),
        connectTimeout: 15000,
        readTimeout: 30000
      });

      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`Server returned ${response.responseCode}`);
      }

      const data = JSON.parse(response.result as string) as EvaluationResult;
      return data;
    } finally {
      request.destroy();
    }
  }

  private static async mockEvaluate(sentence: TrainingSentence, recording: RecordingResult): Promise<EvaluationResult> {
    await TrainingApi.sleep(900);

    const durationPenalty = recording.durationMs < 1800 ? 8 : 0;
    const focusBonus = sentence.focus.includes('intonation') ? 3 : 0;
    const base = Math.max(76, 88 - durationPenalty + focusBonus);

    return {
      transcript: sentence.text,
      overallScore: base,
      fluencyScore: Math.max(70, base - 3),
      pronunciationScore: Math.max(72, base + 1),
      intonationScore: Math.max(68, base - 5),
      feedback: 'Good pacing overall. Keep the stressed words clear and leave a small pause before the final phrase.',
      corrections: [
        {
          word: sentence.text.split(' ')[0],
          issue: 'The opening sound could be firmer.',
          suggestion: 'Start with a cleaner consonant and avoid rushing into the next word.'
        },
        {
          word: sentence.focus,
          issue: 'This focus area needs one more deliberate pass.',
          suggestion: 'Replay the model voice, then repeat the sentence at 80% speed.'
        }
      ],
      referenceAudioUrl: ''
    };
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }
}
