import type { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import type { EvaluationResult, TrainingHistoryItem, TrainingSentence } from '../models/TrainingModels';

const STORE_NAME = 'spoken_training_history';
const HISTORY_KEY = 'recent_history';
const MAX_HISTORY_COUNT = 20;

export class TrainingHistoryService {
  static async load(context: Context): Promise<TrainingHistoryItem[]> {
    const store = await preferences.getPreferences(context, STORE_NAME);
    const raw = store.getSync(HISTORY_KEY, '[]') as string;
    try {
      const parsed = JSON.parse(raw) as TrainingHistoryItem[];
      return Array.isArray(parsed) ? parsed.slice(0, MAX_HISTORY_COUNT) : [];
    } catch (_) {
      return [];
    }
  }

  static async append(context: Context, sentence: TrainingSentence, result: EvaluationResult): Promise<TrainingHistoryItem[]> {
    const history = await TrainingHistoryService.load(context);
    const item: TrainingHistoryItem = {
      sentenceText: sentence.text,
      level: sentence.level,
      focus: sentence.focus,
      overallScore: result.overallScore,
      fluencyScore: result.fluencyScore,
      pronunciationScore: result.pronunciationScore,
      intonationScore: result.intonationScore,
      correctionWords: result.corrections.map((correction) => correction.word).slice(0, 4),
      createdAt: Date.now()
    };

    const nextHistory = [item, ...history].slice(0, MAX_HISTORY_COUNT);
    const store = await preferences.getPreferences(context, STORE_NAME);
    store.putSync(HISTORY_KEY, JSON.stringify(nextHistory));
    await store.flush();
    return nextHistory;
  }
}
