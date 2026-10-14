import { test } from 'node:test';
import assert from 'node:assert/strict';
import WebSocket from 'ws';
import { buildApp } from './app.ts';

process.env.NODE_ENV = 'test';

test('health and version respond', async () => {
  const app = await buildApp({ version: '9.9.9', geminiConfigured: false });
  const health = await app.inject({ url: '/api/health' });
  assert.equal(health.statusCode, 200);
  assert.deepEqual(health.json(), { ok: true, db: true });
  const version = await app.inject({ url: '/api/version' });
  assert.deepEqual(version.json(), { name: 'Naija Street Life', version: '9.9.9', protocol: 1 });
  assert.match(String(version.headers['cache-control']), /max-age/);
  await app.close();
});

test('status reports whether Gemini is configured without exposing the key', async () => {
  const app = await buildApp({ version: '0', geminiConfigured: true });
  const res = await app.inject({ url: '/api/status' });
  assert.deepEqual(res.json(), { ai: { gemini: 'configured' }, players: 0 });
  await app.close();
});

/** Collect messages from a socket until `pred` matches one. */
function waitFor(ws: WebSocket, pred: (m: any) => boolean, ms = 3000): Promise<any> {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timeout')), ms);
    ws.on('message', (data) => {
      const m = JSON.parse(String(data));
      if (process.env.WS_DEBUG) console.log("recv", JSON.stringify(m).slice(0, 160));
      if (pred(m)) { clearTimeout(t); resolve(m); }
    });
  });
}

test('two players on the same street see each other move', async () => {
  const app = await buildApp({ version: '0', geminiConfigured: false });
  await app.listen({ port: 0, host: '127.0.0.1' });
  const addr = app.server.address() as { port: number };
  const url = `ws://127.0.0.1:${addr.port}/ws`;

  const a = new WebSocket(url);
  const b = new WebSocket(url);
  await Promise.all([new Promise((r) => a.on('open', r)), new Promise((r) => b.on('open', r))]);

  const aWelcome = waitFor(a, (m) => m.t === 'welcome');
  a.send(JSON.stringify({ t: 'hello', name: 'Tunde', look: { skin: '#4f3121' }, district: 'yaba', x: 600, y: 1000 }));
  const wa = await aWelcome;
  assert.equal(typeof wa.token, 'string', 'new guests receive a token once');

  const bWelcome = waitFor(b, (m) => m.t === 'welcome');
  const aMeetsB = waitFor(a, (m) => m.t === 'snap' && m.meet?.some((p: any) => p.name === 'Ngozi'));
  b.send(JSON.stringify({ t: 'hello', name: 'Ngozi', look: {}, x: 700, y: 1000 }));
  const wb = await bWelcome;
  assert.equal(wb.room, wa.room);
  await aMeetsB;

  const aSeesMove = waitFor(a, (m) => m.t === 'snap' && m.p?.some((r: number[]) => r[0] === wb.id && r[1] === 740));
  b.send(JSON.stringify({ t: 'move', x: 740, y: 1000, f: 2, m: 0, h: 0 }));
  await aSeesMove;

  // Reconnecting with the token keeps the same account (no new token issued).
  const c = new WebSocket(url);
  await new Promise((r) => c.on('open', r));
  const cWelcome = waitFor(c, (m) => m.t === 'welcome');
  c.send(JSON.stringify({ t: 'hello', token: wa.token, name: 'Tunde', look: {}, x: 600, y: 1000 }));
  const wc = await cWelcome;
  assert.equal(wc.token, undefined);

  for (const s of [a, b, c]) s.close();
  await app.close();
});

test('cloud saves: auth required, newer revision wins', async () => {
  const app = await buildApp({ version: '0', geminiConfigured: false });
  await app.listen({ port: 0, host: '127.0.0.1' });
  const port = (app.server.address() as { port: number }).port;
  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
  await new Promise((r) => ws.on('open', r));
  const welcome = waitFor(ws, (m) => m.t === 'welcome');
  ws.send(JSON.stringify({ t: 'hello', name: 'Saver', look: {}, x: 1, y: 1 }));
  const { token } = await welcome;
  ws.close();

  const auth = { authorization: `Bearer ${token}` };
  assert.equal((await app.inject({ url: '/api/save' })).statusCode, 401);
  assert.equal((await app.inject({ url: '/api/save', headers: auth })).statusCode, 404);
  const put = (revision: number, money: number) =>
    app.inject({ method: 'PUT', url: '/api/save', headers: auth, payload: { revision, data: { life: { money } } } });
  assert.equal((await put(2, 5000)).statusCode, 200);
  assert.equal((await put(1, 99999)).statusCode, 409, 'older revision is rejected');
  const got = await app.inject({ url: '/api/save', headers: auth });
  assert.deepEqual(got.json(), { revision: 2, data: { life: { money: 5000 } } });
  assert.equal((await app.inject({ method: 'PUT', url: '/api/save', headers: auth, payload: { revision: 'x', data: 1 } })).statusCode, 400);
  await app.close();
});
