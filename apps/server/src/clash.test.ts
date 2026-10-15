import { test } from 'node:test';
import assert from 'node:assert/strict';
import WebSocket from 'ws';
import { buildApp } from './app.ts';
import { memoryStore } from './store.ts';
import { makeFight, scoreFight } from './clash.ts';

process.env.NODE_ENV = 'test';

function waitFor(ws: WebSocket, pred: (m: any) => boolean, ms = 4000): Promise<any> {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timeout')), ms);
    const on = (d: unknown) => {
      const m = JSON.parse(String(d));
      if (pred(m)) { clearTimeout(t); ws.off('message', on); resolve(m); }
    };
    ws.on('message', on);
  });
}

async function twoPlayers(xB: number) {
  const store = await memoryStore();
  const app = await buildApp({ version: '0', geminiConfigured: false, store, sms: null, ai: null });
  await app.listen({ port: 0, host: '127.0.0.1' });
  const url = `ws://127.0.0.1:${(app.server.address() as { port: number }).port}/ws`;
  const ga = await store.createGuest('Tunde', {});
  const gb = await store.createGuest('Rival', {});
  const a = new WebSocket(url);
  const b = new WebSocket(url);
  await Promise.all([new Promise((r) => a.on('open', r)), new Promise((r) => b.on('open', r))]);
  const wa = waitFor(a, (m) => m.t === 'welcome');
  a.send(JSON.stringify({ t: 'hello', token: ga.token, name: 'Tunde', look: {}, x: 5000, y: 5000 }));
  await wa;
  const wb = waitFor(b, (m) => m.t === 'welcome');
  b.send(JSON.stringify({ t: 'hello', token: gb.token, name: 'Rival', look: {}, x: xB, y: 5000 }));
  await wb;
  return { app, a, b, pa: ga.player.id, pb: gb.player.id };
}

test('fight scoring rewards the right move inside its window', () => {
  const f = makeFight('abc');
  assert.equal(f.seq.length, 10);
  assert.equal(scoreFight(f.seq, f.seq.map((m) => ({ move: m, t: 0.5 }))), 100);
  assert.equal(scoreFight(f.seq, f.seq.map(() => ({ move: 'jab', t: 0.01 }))), 0, 'inhumanly fast taps score nothing');
  assert.equal(scoreFight(f.seq, 'nonsense'), 0);
});

test('world bounds cover the whole island, so players far across Lagos keep real positions', async () => {
  const { app, a, b } = await twoPlayers(11000);
  const near = waitFor(a, (m) => m.t === 'snap' && m.meet?.length, 1500).catch(() => null);
  assert.equal(await near, null, 'a player 6 km away is out of range, not clamped next to you');
  for (const s of [a, b]) s.close();
  await app.close();
});

test('apologising cannot stop an online player who chooses to fight', async () => {
  const { app, a, b, pa, pb } = await twoPlayers(5100);
  const ca = waitFor(a, (m) => m.t === 'clash');
  const cb = waitFor(b, (m) => m.t === 'clash');
  a.send(JSON.stringify({ t: 'bump', pid: pb }));
  const [ma, mb] = await Promise.all([ca, cb]);
  assert.equal(ma.id, mb.id);
  assert.equal(ma.name, 'Rival');
  const fa = waitFor(a, (m) => m.t === 'clash_fight');
  const fb = waitFor(b, (m) => m.t === 'clash_fight');
  a.send(JSON.stringify({ t: 'clash_choice', id: ma.id, choice: 'peace' })); // Tunde apologises…
  b.send(JSON.stringify({ t: 'clash_choice', id: ma.id, choice: 'fight' })); // …the rival fights anyway
  const [xa, xb] = await Promise.all([fa, fb]);
  assert.equal(xa.you, 'peace');
  assert.equal(xa.them, 'fight');
  assert.deepEqual(xa.seq, xb.seq, 'both fighters face the same sequence');
  const ea = waitFor(a, (m) => m.t === 'clash_end');
  // The peaceful player defends well; the aggressor mashes one button.
  a.send(JSON.stringify({ t: 'clash_result', id: ma.id, log: xa.seq.map((m: string) => ({ move: m, t: 0.6 })) }));
  b.send(JSON.stringify({ t: 'clash_result', id: ma.id, log: xa.seq.map(() => ({ move: 'jab', t: 0.6 })) }));
  const end = await ea;
  assert.equal(end.outcome, 'fight');
  assert.equal(end.winner, pa, 'the defender can still win');
  assert.equal(end.scores[pa], 100);
  // The same pair can't be dragged into another clash straight away.
  const err = waitFor(b, (m) => m.t === 'err');
  b.send(JSON.stringify({ t: 'bump', pid: pa }));
  assert.equal((await err).code, 'clash_cooldown');
  for (const s of [a, b]) s.close();
  await app.close();
});

test('both apologise → peace; players too far apart cannot clash', async () => {
  const { app, a, b, pb } = await twoPlayers(5120);
  const ca = waitFor(a, (m) => m.t === 'clash');
  a.send(JSON.stringify({ t: 'bump', pid: pb }));
  const m = await ca;
  const end = waitFor(b, (x) => x.t === 'clash_end');
  a.send(JSON.stringify({ t: 'clash_choice', id: m.id, choice: 'peace' }));
  b.send(JSON.stringify({ t: 'clash_choice', id: m.id, choice: 'peace' }));
  assert.equal((await end).outcome, 'peace');
  for (const s of [a, b]) s.close();
  await app.close();
  const far = await twoPlayers(5900);
  const err = waitFor(far.a, (x) => x.t === 'err');
  far.a.send(JSON.stringify({ t: 'bump', pid: far.pb }));
  assert.equal((await err).code, 'clash_too_far');
  for (const s of [far.a, far.b]) s.close();
  await far.app.close();
});

async function moveTo(ws: WebSocket, x: number, y: number, m: 0 | 1) {
  ws.send(JSON.stringify({ t: 'move', x, y, f: 0, m, h: 0 }));
  await new Promise((r) => setTimeout(r, 60));
}

test('a player on foot can drag a stopped driver out: the fight starts at once', async () => {
  const { app, a, b, pa, pb } = await twoPlayers(5100);
  await moveTo(b, 5110, 5000, 1); // the rival parks their bus
  await moveTo(a, 5020, 5000, 0); // Tunde walks up to it
  // Too soon: the bus only just stopped.
  const early = waitFor(a, (m) => m.t === 'err');
  a.send(JSON.stringify({ t: 'drag', pid: pb }));
  assert.equal((await early).code, 'drag_moving');
  await new Promise((r) => setTimeout(r, 1600));
  const fa = waitFor(a, (m) => m.t === 'clash_fight');
  const fb = waitFor(b, (m) => m.t === 'clash_fight');
  a.send(JSON.stringify({ t: 'drag', pid: pb }));
  const [xa, xb] = await Promise.all([fa, fb]);
  assert.equal(xb.dragged, true);
  assert.equal(xb.by, pa, 'the victim knows who dragged them out');
  assert.equal(xb.you, 'peace');
  assert.equal(xa.you, 'fight');
  assert.deepEqual(xa.seq, xb.seq);
  const end = waitFor(b, (m) => m.t === 'clash_end');
  a.send(JSON.stringify({ t: 'clash_result', id: xa.id, log: [] }));
  b.send(JSON.stringify({ t: 'clash_result', id: xa.id, log: xb.seq.map((m: string) => ({ move: m, t: 0.5 })) }));
  assert.equal((await end).winner, pb, 'the dragged-out driver can still win');
  for (const s of [a, b]) s.close();
  await app.close();
});

test('only a stopped driver can be dragged out, and only by someone on foot', async () => {
  const { app, a, b, pb } = await twoPlayers(5100);
  await new Promise((r) => setTimeout(r, 1600));
  const notDriving = waitFor(a, (m) => m.t === 'err');
  a.send(JSON.stringify({ t: 'drag', pid: pb }));
  assert.equal((await notDriving).code, 'drag_not_driving');
  await moveTo(b, 5100, 5000, 1);
  await moveTo(a, 5000, 5000, 1);
  const inCar = waitFor(a, (m) => m.t === 'err');
  a.send(JSON.stringify({ t: 'drag', pid: pb }));
  assert.equal((await inCar).code, 'drag_get_out_first');
  for (const s of [a, b]) s.close();
  await app.close();
});
