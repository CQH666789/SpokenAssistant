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
      feedback: '整体节奏不错。请继续把重读词读清楚，并在最后一个短语前留出轻微停顿。',
      corrections: [
        {
          word: sentence.text.split(' ')[0],
          issue: '开头音可以更稳一些。',
          suggestion: '先把第一个辅音发清楚，再自然连到下一个词。'
        },
        {
          word: TrainingApi.focusLabel(sentence.focus),
          issue: '这个练习重点还需要再刻意练一次。',
          suggestion: '先听一遍示范音频，再用 80% 的速度重复这句话。'
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

  private static focusLabel(focus: string): string {
    switch (focus) {
      case 'linking sounds':
        return '连读';
      case 'sentence rhythm':
        return '句子节奏';
      case 'question intonation':
        return '疑问句语调';
      case 'past tense endings':
        return '过去式词尾';
      case 'word stress':
        return '单词重音';
      case 'polite tone':
        return '礼貌语气';
      case 'vowel clarity':
        return '元音清晰度';
      case 'natural pauses':
        return '自然停顿';
      case 'multi-syllable words':
        return '多音节词';
      case 'connected speech':
        return '连贯表达';
      default:
        return focus;
    }
  }
}
