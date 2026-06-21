import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import fs from '@ohos.file.fs';
import type { EvaluationResult, RecordingResult, TrainingSentence } from '../models/TrainingModels';

const API_BASE_URL = 'https://spoken-assistant.vercel.app';
const AUDIO_MIME_TYPE = 'audio/mp4';
const MAX_AUDIO_BYTES = 8 * 1024 * 1024;

export class TrainingApi {
  static async evaluate(sentence: TrainingSentence, recording: RecordingResult): Promise<EvaluationResult> {
    if (!API_BASE_URL) {
      return TrainingApi.mockEvaluate(sentence, recording);
    }

    const audioBase64 = TrainingApi.readAudioAsBase64(recording.path);
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
          audioMimeType: AUDIO_MIME_TYPE,
          audioBase64,
          durationMs: recording.durationMs
        }),
        connectTimeout: 30000,
        readTimeout: 90000
      });

      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`服务端返回 ${response.responseCode}: ${response.result as string}`);
      }

      const data = JSON.parse(response.result as string) as EvaluationResult;
      return data;
    } finally {
      request.destroy();
    }
  }

  private static readAudioAsBase64(path: string): string {
    const stat = fs.statSync(path);
    if (stat.size <= 0) {
      throw new Error('Recording file is empty');
    }
    if (stat.size > MAX_AUDIO_BYTES) {
      throw new Error('Recording file is too large');
    }

    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const buffer = new ArrayBuffer(stat.size);
      const bytesRead = fs.readSync(file.fd, buffer, { length: stat.size });
      const bytes = new Uint8Array(buffer, 0, bytesRead);
      const base64 = new util.Base64Helper();
      return base64.encodeToStringSync(bytes);
    } finally {
      fs.closeSync(file.fd);
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
      languageFeedback: {
        grammarCorrection: sentence.text,
        betterExpression: TrainingApi.betterExpression(sentence),
        explanation: '这句话语法正确。可以尝试更自然的表达，让语气更像日常口语。'
      },
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

  private static betterExpression(sentence: TrainingSentence): string {
    switch (sentence.id) {
      case 'morning-coffee':
        return 'I usually grab a coffee before my morning meeting.';
      case 'weather-plan':
        return 'It is lovely outside, so we should go for a walk after lunch.';
      case 'project-update':
        return 'Could you give me a quick update on where the project timeline stands?';
      case 'train-delay':
        return 'Our train was delayed because of heavy rain near the station.';
      case 'presentation':
        return 'I am putting together a short presentation on customer feedback.';
      case 'restaurant':
        return 'Would you recommend this place for a quiet dinner?';
      case 'remote-work':
        return 'Working remotely gives me more flexibility throughout the week.';
      case 'learning-goal':
        return 'I want to speak more naturally and respond with confidence.';
      case 'design-review':
        return 'The design review helped us spot several important improvements.';
      case 'travel-story':
        return 'I still remember the little hotel we stayed at during our trip.';
      default:
        return sentence.text;
    }
  }
}
