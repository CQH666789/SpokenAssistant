import type { VercelRequest, VercelResponse } from '@vercel/node';

interface TrainingSentence {
  id: string;
  text: string;
  level: string;
  focus: string;
}

interface EvaluationResult {
  overallScore?: number;
  fluencyScore?: number;
  pronunciationScore?: number;
  intonationScore?: number;
  feedback?: string;
  corrections?: Array<{
    word?: string;
    issue?: string;
    suggestion?: string;
  }>;
}

interface TrainingHistoryItem {
  sentenceText?: string;
  level?: string;
  focus?: string;
  overallScore?: number;
  fluencyScore?: number;
  pronunciationScore?: number;
  intonationScore?: number;
  correctionWords?: string[];
  createdAt?: number;
}

interface CoachPayload {
  currentSentence?: TrainingSentence;
  currentResult?: EvaluationResult;
  recentHistory?: TrainingHistoryItem[];
  selectedLevel?: string;
  userGoal?: string;
}

interface CoachNextAction {
  summary: string;
  nextAction: string;
  reason: string;
  nextSentence: TrainingSentence;
  tips: string[];
  source: 'model' | 'mixed' | 'fallback';
  fallbackReason?: string;
}

const LEVELS = ['A2', 'B1', 'B2'];
const FOCUS_VALUES = [
  'linking sounds',
  'sentence rhythm',
  'question intonation',
  'past tense endings',
  'word stress',
  'polite tone',
  'vowel clarity',
  'natural pauses',
  'multi-syllable words',
  'connected speech'
];

export default async function handler(request: VercelRequest, response: VercelResponse) {
  if (request.method !== 'POST') {
    response.setHeader('Allow', 'POST');
    return response.status(405).json({ error: 'Method not allowed' });
  }

  const payload = request.body as CoachPayload;
  if (!payload?.currentSentence || !payload.currentResult) {
    return response.status(400).json({ error: 'currentSentence and currentResult are required' });
  }

  try {
    const action = await createCoachNextAction(payload);
    return response.status(200).json(action);
  } catch (error) {
    const fallbackReason = error instanceof Error ? error.message : 'Unknown coach error';
    console.error('Coach agent failed', {
      error: fallbackReason
    });
    return response.status(200).json(fallbackCoachNextAction(payload, fallbackReason));
  }
}

async function createCoachNextAction(payload: CoachPayload): Promise<CoachNextAction> {
  const apiKey = process.env.BAILIAN_API_KEY || process.env.DASHSCOPE_API_KEY;
  if (!apiKey) {
    return fallbackCoachNextAction(payload, 'BAILIAN_API_KEY is not configured');
  }

  const baseUrl = process.env.BAILIAN_BASE_URL || 'https://dashscope.aliyuncs.com/compatible-mode/v1';
  let result = await requestCoach(baseUrl, apiKey, payload, true);
  if (!result.ok && result.status === 400) {
    result = await requestCoach(baseUrl, apiKey, payload, false);
  }

  if (!result.ok) {
    const errorText = await safeResponseText(result);
    throw new Error(`Coach service returned ${result.status}: ${truncate(errorText, 240)}`);
  }

  const data = await result.json() as {
    choices?: Array<{
      message?: {
        content?: string
      }
    }>
  };
  const parsed = parseCoachAction(cleanText(data.choices?.[0]?.message?.content));
  return normalizeCoachAction(parsed, payload);
}

async function requestCoach(
  baseUrl: string,
  apiKey: string,
  payload: CoachPayload,
  useJsonMode: boolean
): Promise<Response> {
  const body: Record<string, unknown> = {
    model: process.env.BAILIAN_LANGUAGE_MODEL || 'qwen-plus',
    messages: [
      {
        role: 'system',
        content: [
          '你是一个英语口语教练 Agent。',
          '你需要根据本次练习结果和最近训练历史，判断学习者下一步最该练什么。',
          '输出必须具体、简短、可执行。',
          '只输出 JSON，不要 Markdown。',
          'nextSentence 必须是新的英文跟读句，8 到 16 个词，level 为 A2、B1 或 B2，focus 必须来自允许列表。',
          '必须完整返回 summary、nextAction、reason、nextSentence、tips。',
          'summary 和 reason 必须结合具体分数、focus 或历史记录，不要使用泛化模板。',
          'tips 返回 2 到 3 条，必须针对下一句或薄弱项。'
        ].join('\n')
      },
      {
        role: 'user',
        content: JSON.stringify({
          selectedLevel: normalizeLevel(payload.selectedLevel),
          userGoal: cleanText(payload.userGoal) || '提升英语口语自然度和清晰度',
          allowedFocusValues: FOCUS_VALUES,
          currentSentence: payload.currentSentence,
          currentResult: payload.currentResult,
          recentHistory: sanitizeHistory(payload.recentHistory || []),
          returnJsonShape: {
            summary: '中文，一句话总结当前薄弱点',
            nextAction: 'practice_sentence',
            reason: '中文，说明为什么下一步练这个',
            nextSentence: {
              text: '英文新句子',
              level: 'A2|B1|B2',
              focus: 'one allowed focus value'
            },
            tips: ['中文建议1', '中文建议2']
          }
        })
      }
    ],
    temperature: 0.5,
    stream: false
  };

  if (useJsonMode) {
    body.response_format = {
      type: 'json_object'
    };
  }

  return fetchWithTimeout(`${baseUrl}/chat/completions`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(body)
  }, 30000);
}

function parseCoachAction(content: string): Partial<CoachNextAction> {
  try {
    return JSON.parse(content) as Partial<CoachNextAction>;
  } catch (_) {
    const match = content.match(/\{[\s\S]*\}/);
    if (!match) {
      throw new Error('Coach service did not return JSON');
    }
    return JSON.parse(match[0]) as Partial<CoachNextAction>;
  }
}

function normalizeCoachAction(value: Partial<CoachNextAction>, payload: CoachPayload): CoachNextAction {
  const fallback = fallbackCoachNextAction(payload);
  const sentence = (value.nextSentence || {}) as Partial<TrainingSentence>;
  const hasModelSummary = Boolean(cleanText(value.summary));
  const hasModelReason = Boolean(cleanText(value.reason));
  const hasModelSentence = Boolean(cleanText(sentence.text));
  const hasModelTips = Array.isArray(value.tips) && value.tips.some((tip) => cleanText(tip));
  const source = hasModelSummary && hasModelReason && hasModelSentence && hasModelTips ? 'model' : 'mixed';
  const requestedLevel = normalizeLevel(payload.selectedLevel);
  const nextLevel = LEVELS.includes(cleanText(sentence.level))
    ? cleanText(sentence.level)
    : requestedLevel === '全部' ? fallback.nextSentence.level : requestedLevel;
  const nextFocus = FOCUS_VALUES.includes(cleanText(sentence.focus))
    ? cleanText(sentence.focus)
    : fallback.nextSentence.focus;

  return {
    summary: cleanText(value.summary) || fallback.summary,
    nextAction: cleanText(value.nextAction) || fallback.nextAction,
    reason: cleanText(value.reason) || fallback.reason,
    nextSentence: {
      id: `coach-${Date.now()}`,
      text: cleanText(sentence.text) || fallback.nextSentence.text,
      level: nextLevel,
      focus: nextFocus
    },
    tips: Array.isArray(value.tips)
      ? value.tips.map((tip) => cleanText(tip)).filter(Boolean).slice(0, 3)
      : fallback.tips,
    source,
    fallbackReason: source === 'mixed' ? 'Model response missed required coach fields; some fields used local fallback.' : undefined
  };
}

function fallbackCoachNextAction(payload: CoachPayload, fallbackReason = 'Coach model unavailable; local fallback used.'): CoachNextAction {
  const result = payload.currentResult || {};
  const sentence = payload.currentSentence || {
    text: 'Could you give me a quick update on the project timeline?',
    level: 'B1',
    focus: 'question intonation'
  };
  const weakestFocus = pickWeakestFocus(result, payload.recentHistory || [], sentence.focus);
  const level = normalizeLevel(payload.selectedLevel) === '全部'
    ? normalizeLevel(sentence.level)
    : normalizeLevel(payload.selectedLevel);

  return {
    summary: `本次综合 ${normalizeScore(result.overallScore)} 分，下一步建议继续强化 ${focusLabel(weakestFocus)}。`,
    nextAction: 'practice_sentence',
    reason: '系统根据本次分项得分和最近纠音记录，选择一个更适合继续跟读的练习点。',
    nextSentence: {
      id: `coach-fallback-${Date.now()}`,
      text: fallbackSentence(level, weakestFocus),
      level,
      focus: weakestFocus
    },
    tips: [
      '先慢速读一遍，把目标音读完整。',
      '第二遍恢复正常语速，注意句尾不要拖长。',
      '录音前可以先默读一次，确认重读词。'
    ],
    source: 'fallback',
    fallbackReason
  };
}

function pickWeakestFocus(result: EvaluationResult, history: TrainingHistoryItem[], fallbackFocus: string): string {
  const scores = [
    { focus: 'sentence rhythm', score: normalizeScore(result.fluencyScore) },
    { focus: 'word stress', score: normalizeScore(result.pronunciationScore) },
    { focus: 'question intonation', score: normalizeScore(result.intonationScore) }
  ].sort((a, b) => a.score - b.score);

  const recentLow = history.find((item) => normalizeScore(item.overallScore) < 85 && FOCUS_VALUES.includes(cleanText(item.focus)));
  return cleanText(recentLow?.focus) || scores[0].focus || normalizeFocus(fallbackFocus);
}

function fallbackSentence(level: string, focus: string): string {
  if (focus === 'past tense endings') {
    return 'I finished the report before the meeting started.';
  }
  if (focus === 'question intonation') {
    return 'Could you send me the notes after the call?';
  }
  if (focus === 'word stress') {
    return 'The customer feedback helped us improve the product.';
  }
  if (level === 'A2') {
    return 'I usually take a short walk after lunch.';
  }
  if (level === 'B2') {
    return 'Clear communication helps the whole team make better decisions.';
  }
  return 'I need to confirm the schedule before tomorrow morning.';
}

function sanitizeHistory(history: TrainingHistoryItem[]): TrainingHistoryItem[] {
  return history.slice(0, 12).map((item) => ({
    sentenceText: truncate(cleanText(item.sentenceText), 120),
    level: normalizeLevel(item.level),
    focus: normalizeFocus(item.focus),
    overallScore: normalizeScore(item.overallScore),
    fluencyScore: normalizeScore(item.fluencyScore),
    pronunciationScore: normalizeScore(item.pronunciationScore),
    intonationScore: normalizeScore(item.intonationScore),
    correctionWords: Array.isArray(item.correctionWords) ? item.correctionWords.slice(0, 4) : [],
    createdAt: typeof item.createdAt === 'number' ? item.createdAt : 0
  }));
}

function normalizeLevel(value: unknown): string {
  const level = cleanText(value);
  return LEVELS.includes(level) ? level : '全部';
}

function normalizeFocus(value: unknown): string {
  const focus = cleanText(value);
  return FOCUS_VALUES.includes(focus) ? focus : 'sentence rhythm';
}

function normalizeScore(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) ? Math.round(Math.min(Math.max(value, 0), 100)) : 0;
}

function focusLabel(focus: string): string {
  const labels: Record<string, string> = {
    'linking sounds': '连读',
    'sentence rhythm': '句子节奏',
    'question intonation': '疑问句语调',
    'past tense endings': '过去式词尾',
    'word stress': '单词重音',
    'polite tone': '礼貌语气',
    'vowel clarity': '元音清晰度',
    'natural pauses': '自然停顿',
    'multi-syllable words': '多音节词',
    'connected speech': '连贯表达'
  };
  return labels[focus] || focus;
}

function cleanText(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function truncate(value: string, maxLength: number): string {
  return value.length > maxLength ? `${value.slice(0, maxLength)}...` : value;
}

async function safeResponseText(response: Response): Promise<string> {
  try {
    return await response.text();
  } catch (_) {
    return '';
  }
}

async function fetchWithTimeout(url: string, init: RequestInit, timeoutMs: number): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, {
      ...init,
      signal: controller.signal
    });
  } finally {
    clearTimeout(timeout);
  }
}
