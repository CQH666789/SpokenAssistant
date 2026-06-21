import type { VercelRequest, VercelResponse } from '@vercel/node';

export default async function handler(request: VercelRequest, response: VercelResponse) {
  if (request.method !== 'GET') {
    response.setHeader('Allow', 'GET');
    return response.status(405).json({ error: 'Method not allowed' });
  }

  const source = getSource(request.query.source);
  if (!source) {
    return response.status(400).json({ error: 'source is required' });
  }

  if (!isAllowedAudioSource(source)) {
    return response.status(400).json({ error: 'Unsupported audio source' });
  }

  try {
    const upstream = await fetchWithTimeout(source, { method: 'GET' }, 25000);
    if (!upstream.ok) {
      return response.status(502).json({
        error: 'Reference audio fetch failed',
        status: upstream.status
      });
    }

    const contentType = upstream.headers.get('content-type') || 'audio/wav';
    const audioBuffer = Buffer.from(await upstream.arrayBuffer());

    response.setHeader('Content-Type', contentType);
    response.setHeader('Cache-Control', 'private, max-age=300');
    response.setHeader('Content-Length', String(audioBuffer.byteLength));
    return response.status(200).send(audioBuffer);
  } catch (error) {
    return response.status(504).json({
      error: 'Reference audio fetch timeout',
      details: error instanceof Error ? error.message : 'Unknown audio fetch error'
    });
  }
}

function getSource(value: string | string[] | undefined): string {
  return Array.isArray(value) ? value[0] || '' : value || '';
}

function isAllowedAudioSource(source: string): boolean {
  try {
    const parsed = new URL(source);
    return ['http:', 'https:'].includes(parsed.protocol) && parsed.hostname.endsWith('.aliyuncs.com');
  } catch {
    return false;
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
