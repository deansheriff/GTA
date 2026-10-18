import { test } from 'node:test';
import assert from 'node:assert/strict';
import WebSocket from 'ws';
import { buildApp } from './app.ts';
import { memoryStore } from './store.ts';
import { LANDMARKS, ROUTES } from './game_data.ts';
import { weekKey } from './street_online.ts';

process.env.NODE_ENV = 'test';

function waitFor(ws: WebSocket, pred: (m: any) => boolean, ms = 8000): Promise<any> {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timeout')), ms);
    const on = (d: unknown) => {
      const m = JSON.parse(String(d));
      if (pred(m)) { clearTimeout(t); ws.off('message', on); resolve(m); }
    };
    ws.on('message', on);
  });
}
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function world() {
  const store = await memoryStore();
  const app = await buildApp({ version: '0', geminiConfigured: false, store, sms: null, ai: null });
  await app.listen({ port: 0, host: '127.0.0.1' });
  const url = `ws://127.0.0.1:${(app.server.address() as { port: number }).port}/ws`;
  const sockets: WebSocket[] = [];
  const join = async (name: string, x: number, y: number, district = 'yaba') => {
    const g = await store.createGuest(name, {});
    const ws = new WebSocket(url);
    sockets.push(ws);
    await new Promise((r) => ws.on('open', r));
    const w = waitFor(ws, (m) => m.t === 'welcome');
    ws.send(JSON.stringify({ t: 'hello', token: g.token, name, look: {}, x, y, district }));
    await w;
    const p = { ws, pid: g.player.id, h: { authorization: `Bearer ${g.token}` }, x, y };
    return p;
  };
  const move = async (p: { ws: WebSocket; x: number; y: number }, x: number, y: number, m: 0 | 1 = 1, extra: Record<string, unknown> = {}) => {
    p.x = x; p.y = y;
    p.ws.send(JSON.stringify({ t: 'move', x, y, f: 0, m, h: 0, ...extra }));
    await sleep(40);
  };
  /** Drive toward (x, y) at a legal speed. */
  const drive = async (p: { ws: WebSocket; x: number; y: number }, x: number, y: number, others: { ws: WebSocket; x: number; y: number }[] = [], step = 200) => {
    while (Math.hypot(x - p.x, y - p.y) > 1) {
      const d = Math.hypot(x - p.x, y - p.y);
      const k = Math.min(1, step / d);
      const nx = p.x + (x - p.x) * k;
      const ny = p.y + (y - p.y) * k;
      await move(p, nx, ny, 1);
      for (const o of others) await move(o, nx + 40, ny, 1);
      await sleep(step >= 200 ? 320 : 160);
    }
  };
  const close = async () => {
    for (const s of sockets) s.close();
    await app.close();
  };
  return { app, store, join, move, drive, close };
}

test('danfo race: server positions decide the order, and warping is a disqualification', { timeout: 60_000 }, async () => {
  const w = await world();
  const lm = LANDMARKS['yaba-police']!;
  const startX = lm.x - 1700;
  const a = await w.join('Tunde', startX, lm.y);
  const b = await w.join('Rival', startX + 60, lm.y);
  await w.move(a, startX + 5, lm.y, 1);
  await w.move(b, startX + 65, lm.y, 1);
  const inv = waitFor(b.ws, (m) => m.t === 'race_invite');
  a.ws.send(JSON.stringify({ t: 'race_open', to: 'yaba-police', duel: b.pid }));
  const invite = await inv;
  assert.equal(invite.duel, true);
  const goA = waitFor(a.ws, (m) => m.t === 'race_go');
  b.ws.send(JSON.stringify({ t: 'race_join', id: invite.id }));
  await goA;
  await sleep(3100);
  const end = waitFor(a.ws, (m) => m.t === 'race_end', 30_000);
  // The rival warps (teleport) and is disqualified; Tunde drives there properly.
  await w.move(b, lm.x, lm.y, 1, { w: 1 });
  await w.drive(a, lm.x, lm.y);
  const res = await end;
  assert.equal(res.results[0].pid, a.pid, 'the honest driver wins');
  assert.equal(res.results[0].place, 1);
  assert.equal(res.results.find((r: any) => r.pid === b.pid).place, 0, 'the warper gets no place');
  await w.close();
});

test('co-op job: driving together pays both; the server checks you really rode together', { timeout: 60_000 }, async () => {
  const w = await world();
  const d = await w.join('Driver', 3000, 3000);
  const p = await w.join('Filmer', 3040, 3000);
  await w.move(d, 3005, 3000, 1);
  const inv = waitFor(p.ws, (m) => m.t === 'coop_invite');
  d.ws.send(JSON.stringify({ t: 'coop_invite', pid: p.pid, role: 'film' }));
  const invite = await inv;
  const start = waitFor(d.ws, (m) => m.t === 'coop_start');
  p.ws.send(JSON.stringify({ t: 'coop_accept', id: invite.id }));
  const s = await start;
  p.ws.send(JSON.stringify({ t: 'coop_task', id: invite.id, score: 80 }));
  const end = waitFor(d.ws, (m) => m.t === 'coop_end', 50_000);
  // Warp both near the destination (allowed once per few seconds), then drive the last stretch together.
  await sleep(3100);
  await w.move(d, s.to.x - 2000, s.to.y, 1, { w: 1 });
  await w.move(p, s.to.x - 1960, s.to.y, 1, { w: 1 });
  await w.drive(d, s.to.x, s.to.y, [p], 110);
  const e = await end;
  assert.equal(e.outcome, 'arrived');
  assert.ok(e.together >= 0.7);
  assert.ok(e.paid.driver > 0 && e.paid.partner > 0, 'both are paid');
  const wallet = (await w.app.inject({ url: '/api/wallet', headers: p.h })).json();
  assert.equal(wallet.balance, e.paid.partner);
  await w.close();
});

test('ranked boxing: a bout updates ratings and this week\'s wins', { timeout: 30_000 }, async () => {
  const w = await world();
  const a = await w.join('Boxer A', 4000, 4000);
  const b = await w.join('Boxer B', 4100, 4000);
  const inv = waitFor(b.ws, (m) => m.t === 'box_invite');
  a.ws.send(JSON.stringify({ t: 'box_challenge', pid: b.pid }));
  const invite = await inv;
  assert.equal(invite.rating, 1000);
  const fa = waitFor(a.ws, (m) => m.t === 'clash_fight');
  const fb = waitFor(b.ws, (m) => m.t === 'clash_fight');
  b.ws.send(JSON.stringify({ t: 'box_accept', id: invite.id }));
  const [xa, xb] = await Promise.all([fa, fb]);
  assert.equal(xa.ranked, true);
  const end = waitFor(a.ws, (m) => m.t === 'clash_end');
  a.ws.send(JSON.stringify({ t: 'clash_result', id: xa.id, log: xa.seq.map((m: string) => ({ move: m, t: 0.5 })) }));
  b.ws.send(JSON.stringify({ t: 'clash_result', id: xb.id, log: [] }));
  const e = await end;
  assert.equal(e.winner, a.pid);
  assert.ok(e.ratings[a.pid] > 1000 && e.ratings[b.pid] < 1000);
  const board = (await w.app.inject({ url: '/api/boxing', headers: a.h })).json();
  assert.equal(board.top[0].name, 'Boxer A');
  assert.equal(board.thisWeek[0].wins, 1);
  assert.equal(board.me.wins, 1);
  await w.close();
});

test('crews: create, join, and hold a route by finishing runs at its destination', async () => {
  const w = await world();
  const route = ROUTES[0]!;
  const dest = LANDMARKS[route.to]!;
  const boss = await w.join('Boss', dest.x, dest.y);
  await w.app.inject({ method: 'POST', url: '/api/wallet/move', headers: boss.h, payload: { amount: 6000 } });
  const made = await w.app.inject({ method: 'POST', url: '/api/crews', headers: boss.h, payload: { name: 'Oshodi Kings', tag: 'osk', colour: '#c8432f' } });
  assert.equal(made.statusCode, 200, made.body);
  assert.equal(made.json().tag, 'OSK');
  const poor = await w.join('Broke', 100, 100);
  assert.equal((await w.app.inject({ method: 'POST', url: '/api/crews', headers: poor.h, payload: { name: 'No Money', tag: 'NM' } })).statusCode, 402);
  assert.equal((await w.app.inject({ method: 'POST', url: `/api/crews/${made.json().id}/join`, headers: poor.h })).statusCode, 200);
  // Not at the destination (or not driving): no points.
  assert.equal((await w.app.inject({ method: 'POST', url: '/api/crews/route-run', headers: poor.h, payload: { route: route.id } })).statusCode, 409);
  await w.move(boss, dest.x + 10, dest.y, 1);
  const run = await w.app.inject({ method: 'POST', url: '/api/crews/route-run', headers: boss.h, payload: { route: route.id } });
  assert.equal(run.statusCode, 200, run.body);
  assert.equal(run.json().yours, true);
  assert.equal((await w.app.inject({ method: 'POST', url: '/api/crews/route-run', headers: boss.h, payload: { route: route.id } })).statusCode, 429, 'one run every two minutes');
  const routes = (await w.app.inject({ url: '/api/routes', headers: boss.h })).json();
  assert.equal(routes.week, weekKey());
  assert.deepEqual(routes.held, [route.id]);
  assert.equal((await w.app.inject({ url: '/api/crews/mine', headers: poor.h })).json().crew.members.length, 2);
  await w.close();
});

test('trading: buy cheap in Mushin, sell dear in Lekki; prices move with trades', async () => {
  const w = await world();
  const t = await w.join('Trader', 1000, 1000, 'mushin');
  await w.app.inject({ method: 'POST', url: '/api/wallet/move', headers: t.h, payload: { amount: 50000 } });
  const before = (await w.app.inject({ url: '/api/trade', headers: t.h })).json();
  assert.equal(before.district, 'mushin');
  const buy = (await w.app.inject({ method: 'POST', url: '/api/trade', headers: t.h, payload: { good: 'tomatoes', qty: 5, side: 'buy' } })).json();
  assert.equal(buy.qty, 5);
  assert.ok(buy.price > before.prices.tomatoes, 'buying pushes the price up');
  assert.equal((await w.app.inject({ method: 'POST', url: '/api/trade', headers: t.h, payload: { good: 'tomatoes', qty: 9, side: 'sell' } })).statusCode, 409, "can't sell what you don't have");
  // Travel to Lekki (a new connection lands in the Lekki room) and sell.
  t.ws.close();
  const t2 = await (async () => {
    const ws = new WebSocket(`ws://127.0.0.1:${(w.app.server.address() as { port: number }).port}/ws`);
    await new Promise((r) => ws.on('open', r));
    const wel = waitFor(ws, (m) => m.t === 'welcome');
    ws.send(JSON.stringify({ t: 'hello', token: t.h.authorization.slice(7), name: 'Trader', look: {}, x: 9000, y: 7000, district: 'lekki' }));
    await wel;
    return ws;
  })();
  const sell = (await w.app.inject({ method: 'POST', url: '/api/trade', headers: t.h, payload: { good: 'tomatoes', qty: 5, side: 'sell' } })).json();
  assert.equal(sell.district, 'lekki');
  assert.ok(sell.profit > 0, `profit from the price gap (${sell.profit})`);
  t2.close();
  await w.close();
});

test('gist feed: template posts only, rate-limited, newest first', async () => {
  const w = await world();
  const a = await w.join('Gister', 500, 500, 'oshodi');
  const ok = await w.app.inject({ method: 'POST', url: '/api/gist', headers: a.h, payload: { kind: 'fight_win' } });
  assert.equal(ok.statusCode, 200);
  assert.equal(ok.json().text, 'Gister won a street fight in oshodi!');
  assert.equal((await w.app.inject({ method: 'POST', url: '/api/gist', headers: a.h, payload: { kind: 'anything i like' } })).statusCode, 400);
  assert.equal((await w.app.inject({ method: 'POST', url: '/api/gist', headers: a.h, payload: { kind: 'award', detail: 'x' } })).statusCode, 429, 'one post every 20 s');
  const feed = (await w.app.inject({ url: '/api/gist?district=oshodi', headers: a.h })).json();
  assert.equal(feed.posts.length, 1);
  await w.close();
});
