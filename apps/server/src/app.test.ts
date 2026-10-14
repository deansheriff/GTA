import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildApp } from './app.ts';

process.env.NODE_ENV = 'test';

test('health and version respond', async () => {
  const app = buildApp({ version: '9.9.9', geminiConfigured: false });
  const health = await app.inject({ url: '/health' });
  assert.equal(health.statusCode, 200);
  const version = await app.inject({ url: '/api/version' });
  assert.deepEqual(version.json(), { name: 'Naija Street Life', version: '9.9.9' });
  assert.match(String(version.headers['cache-control']), /max-age/);
});

test('status reports whether Gemini is configured without exposing the key', async () => {
  const app = buildApp({ version: '0', geminiConfigured: true });
  const res = await app.inject({ url: '/api/status' });
  assert.deepEqual(res.json(), { ai: { gemini: 'configured' } });
});
