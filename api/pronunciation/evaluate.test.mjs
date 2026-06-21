import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';

const handler = await loadHandler();

test('rejects non-POST requests', async () => {
  const response = await invoke({ method: 'GET', body: {} });

  assert.equal(response.statusCode, 405);
  assert.equal(response.headers.Allow, 'POST');
  assert.equal(response.body.error, 'Method not allowed');
});

test('requires sentenceId and targetText', async () => {
  const response = await invoke({ method: 'POST', body: { sentenceId: 'sample' } });

  assert.equal(response.statusCode, 400);
  assert.equal(response.body.error, 'sentenceId and targetText are required');
});

test('returns pronunciation and language feedback for a valid request', async () => {
  const response = await invoke({
    method: 'POST',
    body: {
      sentenceId: 'morning-coffee',
      targetText: 'I usually drink a cup of coffee before my morning meeting.',
      durationMs: 2400
    }
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.body.transcript, 'I usually drink a cup of coffee before my morning meeting.');
  assert.equal(response.body.overallScore, 86);
  assert.ok(Array.isArray(response.body.corrections));
  assert.equal(response.body.corrections[0].word, 'I');
  assert.equal(response.body.languageFeedback.grammarCorrection, 'I usually drink a cup of coffee before my morning meeting.');
  assert.equal(response.body.languageFeedback.betterExpression, 'I usually grab a coffee before my morning meeting.');
  assert.ok(response.body.languageFeedback.explanation.includes('口语表达'));
});

test('uses spokenText when provided', async () => {
  const response = await invoke({
    method: 'POST',
    body: {
      sentenceId: 'morning-coffee',
      targetText: 'I usually drink a cup of coffee before my morning meeting.',
      spokenText: 'I usually drink coffee before my morning meeting.',
      durationMs: 2400
    }
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.body.transcript, 'I usually drink coffee before my morning meeting.');
  assert.equal(response.body.languageFeedback.grammarCorrection, 'I usually drink coffee before my morning meeting.');
});

test('reports ASR failure when audio transcription fails', async () => {
  const response = await invoke({
    method: 'POST',
    body: {
      sentenceId: 'morning-coffee',
      targetText: 'I usually drink a cup of coffee before my morning meeting.',
      audioBase64: 'AAAA',
      audioMimeType: 'audio/mp4',
      durationMs: 2400
    }
  });

  assert.equal(response.statusCode, 502);
  assert.equal(response.body.error, 'Speech transcription failed');
  assert.match(response.body.details, /BAILIAN_API_KEY/);
});

async function invoke(request) {
  const response = {
    headers: {},
    statusCode: 200,
    body: undefined,
    setHeader(name, value) {
      this.headers[name] = value;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    }
  };

  await handler(request, response);
  return response;
}

async function loadHandler() {
  const source = await readFile(new URL('./evaluate.ts', import.meta.url), 'utf8');
  const executable = source
    .replace(/^import type .*;\n/m, '')
    .replace(/interface\s+\w+\s+\{[\s\S]*?\}\n\n/g, '')
    .replace(/export default async function handler/, 'async function handler')
    .replace(/ as EvaluationPayload/g, '')
    .replace(/ as Partial<LanguageFeedback>/g, '')
    .replace(/: EvaluationPayload/g, '')
    .replace(/: Partial<LanguageFeedback>/g, '')
    .replace(/: Partial<PronunciationFeedback>/g, '')
    .replace(/: RequestInit/g, '')
    .replace(/: Response/g, '')
    .replace(/: Promise<Response>/g, '')
    .replace(/: Promise<string>/g, '')
    .replace(/: Promise<PronunciationFeedback>/g, '')
    .replace(/: PronunciationFeedback/g, '')
    .replace(/: PronunciationCorrection\[\]/g, '')
    .replace(/: PronunciationCorrection/g, '')
    .replace(/: Record<string, unknown>/g, '')
    .replace(/audioMimeType\?: string/g, 'audioMimeType')
    .replace(/locale\?: string/g, 'locale')
    .replace(/language\?: string/g, 'language')
    .replace(/ as \{\n\s+choices\?: Array<\{\n\s+message\?: \{\n\s+content\?: string\n\s+\}\n\s+\}>\n\s+\}/g, '')
    .replace(/ as \{\n\s+output\?: \{\n\s+audio\?: \{\n\s+url\?: string\n\s+\}\n\s+\}\n\s+\}/g, '')
    .replace(/: Record<string, string>/g, '')
    .replace(/: Promise<LanguageFeedback>/g, '')
    .replace(/: LanguageFeedback/g, '')
    .replace(/: VercelRequest/g, '')
    .replace(/: VercelResponse/g, '')
    .replace(/: number/g, '')
    .replace(/: string\[\]/g, '')
    .replace(/: string/g, '')
    .replace(/: unknown/g, '')
    .replace(/: any/g, '')
    .concat('\nhandler;');

  const script = new vm.Script(executable, { filename: 'evaluate.ts' });
  return script.runInNewContext({ process: { env: {} }, fetch });
}
