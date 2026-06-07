import type { EvaluationResult, RecordingResult, TrainingSentence, TrainingStage } from '../models/TrainingModels';
import { TRAINING_SENTENCES } from '../models/TrainingModels';

export class TrainingSessionStore {
  private index: number = 0;

  stage: TrainingStage = 'idle';
  sentence: TrainingSentence = TRAINING_SENTENCES[0];
  recording?: RecordingResult;
  result?: EvaluationResult;
  errorMessage: string = '';

  next(): void {
    this.index = (this.index + 1) % TRAINING_SENTENCES.length;
    this.sentence = TRAINING_SENTENCES[this.index];
    this.resetAttempt();
  }

  resetAttempt(): void {
    this.stage = 'idle';
    this.recording = undefined;
    this.result = undefined;
    this.errorMessage = '';
  }
}
