export interface TrainingSentence {
  id: string;
  text: string;
  level: string;
  focus: string;
}

export interface PronunciationCorrection {
  word: string;
  issue: string;
  suggestion: string;
}

export interface LanguageFeedback {
  grammarCorrection: string;
  betterExpression: string;
  explanation: string;
}

export interface EvaluationResult {
  transcript: string;
  overallScore: number;
  fluencyScore: number;
  pronunciationScore: number;
  intonationScore: number;
  feedback: string;
  corrections: PronunciationCorrection[];
  languageFeedback: LanguageFeedback;
  referenceAudioUrl: string;
}

export interface RecordingResult {
  path: string;
  durationMs: number;
}

export type TrainingStage =
  'idle' |
  'permissionDenied' |
  'recording' |
  'uploading' |
  'evaluating' |
  'complete' |
  'error';

export const TRAINING_SENTENCES: TrainingSentence[] = [
  {
    id: 'morning-coffee',
    text: 'I usually drink a cup of coffee before my morning meeting.',
    level: 'A2',
    focus: 'linking sounds'
  },
  {
    id: 'weather-plan',
    text: 'The weather is beautiful, so we should take a walk after lunch.',
    level: 'A2',
    focus: 'sentence rhythm'
  },
  {
    id: 'project-update',
    text: 'Could you give me a quick update on the project timeline?',
    level: 'B1',
    focus: 'question intonation'
  },
  {
    id: 'train-delay',
    text: 'Our train was delayed because of heavy rain near the station.',
    level: 'B1',
    focus: 'past tense endings'
  },
  {
    id: 'presentation',
    text: 'I am preparing a short presentation about customer feedback.',
    level: 'B1',
    focus: 'word stress'
  },
  {
    id: 'restaurant',
    text: 'Would you recommend this restaurant for a quiet dinner?',
    level: 'B1',
    focus: 'polite tone'
  },
  {
    id: 'remote-work',
    text: 'Working remotely gives me more flexibility during the week.',
    level: 'B2',
    focus: 'vowel clarity'
  },
  {
    id: 'learning-goal',
    text: 'My goal is to speak more naturally and respond with confidence.',
    level: 'B2',
    focus: 'natural pauses'
  },
  {
    id: 'design-review',
    text: 'The design review helped us identify several important improvements.',
    level: 'B2',
    focus: 'multi-syllable words'
  },
  {
    id: 'travel-story',
    text: 'I still remember the small hotel where we stayed during our trip.',
    level: 'B2',
    focus: 'connected speech'
  }
];
