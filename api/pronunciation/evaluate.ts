import type { VercelRequest, VercelResponse } from '@vercel/node';

interface EvaluationPayload {
  sentenceId?: string;
  targetText?: string;
  spokenText?: string;
  locale?: string;
  audioPath?: string;
  audioBase64?: string;
  audioMimeType?: string;
  durationMs?: number;
}

interface LanguageFeedback {
  grammarCorrection: string;
  betterExpression: string;
  explanation: string;
}

interface PronunciationCorrection {
  word: string;
  issue: string;
  suggestion: string;
}

interface PronunciationFeedback {
  overallScore: number;
  fluencyScore: number;
  pronunciationScore: number;
  intonationScore: number;
  feedback: string;
  corrections: PronunciationCorrection[];
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
  let transcript = '';
  try {
    transcript = await resolveTranscript(payload);
  } catch (error) {
    return response.status(502).json({
      error: 'Speech transcription failed',
      details: error instanceof Error ? error.message : 'Unknown ASR error'
    });
  }
  const pronunciationFeedback = await createPronunciationFeedback(payload.targetText, transcript, durationMs);
  const [languageFeedback, referenceAudioUrl] = await Promise.all([
    createLanguageFeedback(payload.targetText, transcript),
    createReferenceAudio(payload.targetText, request)
  ]);

  return response.status(200).json({
    transcript,
    overallScore: pronunciationFeedback.overallScore,
    fluencyScore: pronunciationFeedback.fluencyScore,
    pronunciationScore: pronunciationFeedback.pronunciationScore,
    intonationScore: pronunciationFeedback.intonationScore,
    feedback: pronunciationFeedback.feedback,
    corrections: pronunciationFeedback.corrections,
    languageFeedback,
    referenceAudioUrl
  });
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

async function resolveTranscript(payload: EvaluationPayload): Promise<string> {
  const spokenText = cleanText(payload.spokenText);
  if (spokenText) {
    return spokenText;
  }

  const audioBase64 = cleanText(payload.audioBase64);
  if (!audioBase64) {
    return payload.targetText || '';
  }

  try {
    const transcript = await transcribeAudio(audioBase64, payload.audioMimeType, payload.locale);
    if (!transcript) {
      throw new Error('Empty transcription result');
    }
    return transcript;
  } catch (error) {
    console.error('Speech transcription failed', {
      sentenceId: payload.sentenceId,
      durationMs: payload.durationMs,
      audioMimeType: payload.audioMimeType,
      audioBase64Bytes: cleanText(payload.audioBase64).length,
      error: error instanceof Error ? error.message : 'Unknown ASR error'
    });
    throw error;
  }
}

async function transcribeAudio(audioBase64: string, audioMimeType?: string, locale?: string): Promise<string> {
  const apiKey = process.env.BAILIAN_API_KEY || process.env.DASHSCOPE_API_KEY;
  if (!apiKey) {
    throw new Error('BAILIAN_API_KEY is not configured');
  }

  const baseUrl = process.env.BAILIAN_BASE_URL || 'https://dashscope.aliyuncs.com/compatible-mode/v1';
  const mimeType = cleanText(audioMimeType) || 'audio/mp4';
  const dataUri = audioBase64.startsWith('data:') ? audioBase64 : `data:${mimeType};base64,${audioBase64}`;
  const language = (cleanText(locale) || 'en-US').toLowerCase().startsWith('zh') ? 'zh' : 'en';
  const requestBody = createAsrRequestBody(dataUri, language);
  let result = await requestAsr(baseUrl, apiKey, requestBody);

  if (!result.ok && result.status === 400) {
    const retryBody = createAsrRequestBody(dataUri);
    result = await requestAsr(baseUrl, apiKey, retryBody);
  }

  if (!result.ok) {
    const errorText = await safeResponseText(result);
    console.error('Qwen ASR request failed', {
      status: result.status,
      mimeType,
      audioBase64Bytes: audioBase64.length,
      errorText
    });
    throw new Error(`ASR service returned ${result.status}: ${truncate(errorText, 240)}`);
  }

  const data = await result.json() as {
    choices?: Array<{
      message?: {
        content?: string
      }
    }>
  };
  return cleanText(data.choices?.[0]?.message?.content);
}

function createAsrRequestBody(dataUri: string, language?: string): Record<string, unknown> {
  const body: Record<string, unknown> = {
    model: process.env.BAILIAN_ASR_MODEL || 'qwen3-asr-flash',
    messages: [
      {
        role: 'user',
        content: [
          {
            type: 'input_audio',
            input_audio: {
              data: dataUri
            }
          }
        ]
      }
    ],
    stream: false,
    asr_options: {
      enable_itn: false
    }
  };

  if (language) {
    body.asr_options = {
      language,
      enable_itn: false
    };
  }

  return body;
}

async function requestAsr(baseUrl: string, apiKey: string, body: Record<string, unknown>): Promise<Response> {
  return fetchWithTimeout(`${baseUrl}/chat/completions`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(body)
  }, 25000);
}

async function safeResponseText(response: Response): Promise<string> {
  try {
    return await response.text();
  } catch (_) {
    return '';
  }
}

function truncate(value: string, maxLength: number): string {
  return value.length > maxLength ? `${value.slice(0, maxLength)}...` : value;
}

async function createReferenceAudio(text: string, request: VercelRequest): Promise<string> {
  const apiKey = process.env.BAILIAN_API_KEY || process.env.DASHSCOPE_API_KEY;
  if (!apiKey) {
    return '';
  }

  try {
    const baseUrl = process.env.BAILIAN_DASHSCOPE_BASE_URL || 'https://dashscope.aliyuncs.com/api/v1';
    const result = await fetchWithTimeout(`${baseUrl}/services/aigc/multimodal-generation/generation`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        model: process.env.BAILIAN_TTS_MODEL || 'qwen3-tts-flash',
        input: {
          text,
          voice: process.env.BAILIAN_TTS_VOICE || 'Cherry',
          language_type: 'English'
        }
      })
    }, 25000);

    if (!result.ok) {
      const errorText = await safeResponseText(result);
      console.error('Qwen TTS request failed', {
        status: result.status,
        errorText
      });
      return '';
    }

    const data = await result.json() as {
      output?: {
        audio?: {
          url?: string
        }
      }
    };
    return buildReferenceAudioUrl(cleanText(data.output?.audio?.url), request);
  } catch (error) {
    console.error('Reference audio generation failed', {
      error: error instanceof Error ? error.message : 'Unknown TTS error'
    });
    return '';
  }
}

function buildReferenceAudioUrl(audioUrl: string, request: VercelRequest): string {
  if (!audioUrl) {
    return '';
  }

  const hostHeader = request.headers?.host;
  const host = Array.isArray(hostHeader) ? hostHeader[0] : hostHeader;
  if (!host) {
    return audioUrl;
  }

  const protocolHeader = request.headers?.['x-forwarded-proto'];
  const protocol = Array.isArray(protocolHeader) ? protocolHeader[0] : protocolHeader;
  return `${protocol || 'https'}://${host}/api/reference-audio?source=${encodeURIComponent(audioUrl)}`;
}

async function createPronunciationFeedback(
  targetText: string,
  transcript: string,
  durationMs: number
): Promise<PronunciationFeedback> {
  const apiKey = process.env.BAILIAN_API_KEY || process.env.DASHSCOPE_API_KEY;
  const fallback = fallbackPronunciationFeedback(targetText, transcript, durationMs);
  if (!apiKey) {
    return fallback;
  }

  try {
    const baseUrl = process.env.BAILIAN_BASE_URL || 'https://dashscope.aliyuncs.com/compatible-mode/v1';
    const result = await fetchWithTimeout(`${baseUrl}/chat/completions`, {
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
              '你是英语跟读发音教练。',
              '请比较练习原句 targetText 和 ASR 转写 spokenText。',
              '根据漏词、错词、语速和句子类型给出中文发音反馈。',
              '只输出 JSON，字段为 overallScore、fluencyScore、pronunciationScore、intonationScore、feedback、corrections。',
              '分数为 0-100 的整数。',
              'feedback 用中文，必须结合本句具体内容，不要使用泛化模板。',
              'corrections 返回 2 条以内，每条包含 word、issue、suggestion，中文解释。'
            ].join('\n')
          },
          {
            role: 'user',
            content: JSON.stringify({
              targetText,
              spokenText: transcript,
              durationMs
            })
          }
        ],
        response_format: {
          type: 'json_schema',
          json_schema: {
            name: 'pronunciation_feedback',
            strict: true,
            schema: {
              type: 'object',
              additionalProperties: false,
              required: [
                'overallScore',
                'fluencyScore',
                'pronunciationScore',
                'intonationScore',
                'feedback',
                'corrections'
              ],
              properties: {
                overallScore: { type: 'integer' },
                fluencyScore: { type: 'integer' },
                pronunciationScore: { type: 'integer' },
                intonationScore: { type: 'integer' },
                feedback: { type: 'string' },
                corrections: {
                  type: 'array',
                  maxItems: 2,
                  items: {
                    type: 'object',
                    additionalProperties: false,
                    required: ['word', 'issue', 'suggestion'],
                    properties: {
                      word: { type: 'string' },
                      issue: { type: 'string' },
                      suggestion: { type: 'string' }
                    }
                  }
                }
              }
            }
          }
        },
        temperature: 0.2
      })
    }, 20000);

    if (!result.ok) {
      return fallback;
    }

    const data = await result.json() as {
      choices?: Array<{
        message?: {
          content?: string
        }
      }>
    };
    const content = data.choices?.[0]?.message?.content || '';
    return normalizePronunciationFeedback(JSON.parse(content), fallback);
  } catch (_) {
    return fallback;
  }
}

async function createLanguageFeedback(targetText: string, transcript: string): Promise<LanguageFeedback> {
  const apiKey = process.env.BAILIAN_API_KEY || process.env.DASHSCOPE_API_KEY;
  if (!apiKey) {
    return fallbackLanguageFeedback(targetText, transcript);
  }

  try {
    const baseUrl = process.env.BAILIAN_BASE_URL || 'https://dashscope.aliyuncs.com/compatible-mode/v1';
    const result = await fetchWithTimeout(`${baseUrl}/chat/completions`, {
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
    }, 20000);

    if (!result.ok) {
      return fallbackLanguageFeedback(targetText, transcript);
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
    return normalizeLanguageFeedback(parsed, targetText, transcript);
  } catch (_) {
    return fallbackLanguageFeedback(targetText, transcript);
  }
}

async function fetchWithTimeout(url: string, init: RequestInit, timeoutMs: number): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, {
      ...init,
      signal: controller.signal
    });
  } finally {
    clearTimeout(timer);
  }
}

function normalizeLanguageFeedback(value: Partial<LanguageFeedback>, targetText: string, transcript: string): LanguageFeedback {
  const fallback = fallbackLanguageFeedback(targetText, transcript);
  return {
    grammarCorrection: cleanText(value.grammarCorrection) || fallback.grammarCorrection,
    betterExpression: cleanText(value.betterExpression) || fallback.betterExpression,
    explanation: cleanText(value.explanation) || fallback.explanation
  };
}

function cleanText(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function normalizePronunciationFeedback(value: Partial<PronunciationFeedback>, fallback: PronunciationFeedback): PronunciationFeedback {
  const hasModelCorrections = Array.isArray(value.corrections);
  const corrections = hasModelCorrections
    ? value.corrections
      .map((item) => ({
        word: cleanText(item?.word),
        issue: cleanText(item?.issue),
        suggestion: cleanText(item?.suggestion)
      }))
      .filter((item) => item.word && item.issue && item.suggestion)
      .slice(0, 2)
    : fallback.corrections;

  return {
    overallScore: normalizeScore(value.overallScore, fallback.overallScore),
    fluencyScore: normalizeScore(value.fluencyScore, fallback.fluencyScore),
    pronunciationScore: normalizeScore(value.pronunciationScore, fallback.pronunciationScore),
    intonationScore: normalizeScore(value.intonationScore, fallback.intonationScore),
    feedback: cleanText(value.feedback) || fallback.feedback,
    corrections: hasModelCorrections ? corrections : fallback.corrections
  };
}

function normalizeScore(value: unknown, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value)
    ? Math.round(clamp(value, 0, 100))
    : fallback;
}

function fallbackLanguageFeedback(targetText: string, transcript = targetText): LanguageFeedback {
  return {
    grammarCorrection: transcript || targetText,
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

function fallbackPronunciationFeedback(targetText: string, transcript: string, durationMs: number): PronunciationFeedback {
  const targetDisplayWords = extractDisplayWords(targetText);
  const targetWords = tokenizeWords(targetText);
  const spokenWords = tokenizeWords(transcript);
  const missingWords = targetWords.filter((word) => !spokenWords.includes(word));
  const extraWords = spokenWords.filter((word) => !targetWords.includes(word));
  const similarity = targetWords.length === 0
    ? 1
    : (targetWords.length - Math.min(missingWords.length, targetWords.length)) / targetWords.length;
  const durationPenalty = durationMs > 0 && durationMs < Math.max(1600, targetWords.length * 260) ? 8 : 0;
  const extraPenalty = Math.min(extraWords.length * 2, 8);
  const base = clamp(Math.round(70 + similarity * 24 - durationPenalty - extraPenalty), 55, 96);
  const isQuestion = targetText.trim().endsWith('?');

  const corrections: PronunciationCorrection[] = [];
  if (missingWords.length > 0) {
    corrections.push({
      word: missingWords.slice(0, 3).join(' '),
      issue: '这些词在转写里没有稳定出现，可能读得太轻或被连读吞掉。',
      suggestion: `重读 ${missingWords[0]}，再把相邻短语拆慢读一遍。`
    });
  }
  if (extraWords.length > 0 && corrections.length < 2) {
    corrections.push({
      word: extraWords.slice(0, 3).join(' '),
      issue: '转写里出现了原句外的词，可能有含混音或停顿位置不自然。',
      suggestion: '先按原句分组跟读，确认每个短语只读一次。'
    });
  }
  if (corrections.length < 2) {
    corrections.push(fallbackCorrection(isQuestion ? 'question intonation' : targetDisplayWords[0] || 'opening', targetText));
  }

  return {
    overallScore: base,
    fluencyScore: clamp(base - durationPenalty + 2, 0, 100),
    pronunciationScore: clamp(base - Math.min(missingWords.length * 2, 10) + 3, 0, 100),
    intonationScore: clamp(base - (isQuestion ? 4 : 2), 0, 100),
    feedback: buildFallbackFeedback(targetText, missingWords, extraWords, durationMs),
    corrections
  };
}

function fallbackCorrection(word: string, targetText: string): PronunciationCorrection {
  if (targetText.trim().endsWith('?')) {
    return {
      word,
      issue: '疑问句末尾的上扬语调需要更明显。',
      suggestion: '读到句尾时稍微抬高音高，但不要拖长最后一个词。'
    };
  }

  return {
    word,
    issue: '这个位置可以读得更清楚、更稳定。',
    suggestion: '先慢速读清楚重音，再恢复正常语速。'
  };
}

function buildFallbackFeedback(targetText: string, missingWords: string[], extraWords: string[], durationMs: number): string {
  if (missingWords.length > 0) {
    return `这句的主要问题是 ${missingWords.slice(0, 3).join('、')} 没有被清楚识别。先放慢相关短语，再恢复自然语速。`;
  }
  if (extraWords.length > 0) {
    return `这次读出了额外的 ${extraWords.slice(0, 3).join('、')}，说明部分音节可能含混。建议按短语停顿重新读。`;
  }
  if (durationMs > 0 && durationMs < 1800) {
    return '这次整体内容接近原句，但语速偏快。放慢开头短语，让关键词更清楚。';
  }
  return targetText.trim().endsWith('?')
    ? '这次内容比较完整。注意疑问句句尾语调，让问题听起来更自然。'
    : '这次内容比较完整。继续保持节奏，并把关键词的重音读得更明确。';
}

function tokenizeWords(value: string): string[] {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9'\s]/g, ' ')
    .split(/\s+/)
    .filter(Boolean);
}

function extractDisplayWords(value: string): string[] {
  return value
    .replace(/[^A-Za-z0-9'\s]/g, ' ')
    .split(/\s+/)
    .filter(Boolean);
}
