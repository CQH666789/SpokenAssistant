import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';

const handler = await loadHandler();

test('rejects non-POST requests', () => {
  const response = invoke({ method: 'GET', body: {} });

  assert.equal(response.statusCode, 405);
  assert.equal(response.headers.Allow, 'POST');
  assert.equal(response.body.error, 'Method not allowed');
});

test('requires sentenceId and targetText', () => {
  const response = invoke({ method: 'POST', body: { sentenceId: 'sample' } });

  assert.equal(response.statusCode, 400);
  assert.equal(response.body.error, 'sentenceId and targetText are required');
});

test('returns pronunciation feedback for a valid request', () => {
  const response = invoke({
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
});

function invoke(request) {
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

  handler(request, response);
  return response;
}

async function loadHandler() {
  const source = await readFile(new URL('./evaluate.ts', import.meta.url), 'utf8');
  const executable = source
    .replace(/^import type .*;\n/m, '')
    .replace(/interface\s+\w+\s+\{[\s\S]*?\}\n\n/g, '')
    .replace(/export default function handler/, 'function handler')
    .replace(/ as EvaluationPayload/g, '')
    .replace(/: number/g, '')
    .replace(/: VercelRequest/g, '')
    .replace(/: VercelResponse/g, '')
    .concat('\nhandler;');

  const script = new vm.Script(executable, { filename: 'evaluate.ts' });
  return script.runInNewContext({});
}
