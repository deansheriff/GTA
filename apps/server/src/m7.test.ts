import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildApp } from './app.ts';
import { memoryStore } from './store.ts';
import { makeRun, score } from './challenges.ts';

process.env.NODE_ENV = 'test';
process.env.ADMIN_TOKEN = 'test-admin-token-0123456789abcdef';
const admin = { authorization: 'Bearer test-admin-token-0123456789abcdef' };

async function setup() {
  const store = await memoryStore();
  const app = await buildApp({ version: '0', geminiConfigured: false, store, sms: null, ai: null });
  const g = await store.createGuest('Player', {});
  return { app, store, id: g.player.id, h: { authorization: `Bearer ${g.token}` } };
}

test('server replay scoring: perfect play scores high, mashing and bots score low', () => {
  const spray = makeRun('spray', 'seed-1');
  const beats = (spray.key as { beats: number[] }).beats;
  assert.equal(score('spray', spray.key, beats), 100, 'tapping exactly on every beat');
  assert.ok(score('spray', spray.key, beats.map((b) => b + 0.2)) <= 60, 'late taps are only "good"');
  assert.equal(score('spray', spray.key, Array.from({ length: 200 }, (_, i) => i * 0.05)), 0, 'button-mashing is rejected');
  const iv = makeRun('interview', 'seed-2');
  const deltas = (iv.key as { deltas: number[][] }).deltas;
  const best = deltas.map((d) => ({ pick: d.indexOf(Math.max(...d)), t: 2.5 }));
  assert.equal(score('interview', iv.key, best), 100);
  assert.ok(score('interview', iv.key, best.map((b) => ({ ...b, t: 0.05 }))) < 10, 'answering faster than reading is a bot');
  const dodge = makeRun('dodge', 'seed-3');
  const seq = (dodge.key as { seq: string[] }).seq;
  assert.equal(score('dodge', dodge.key, seq.map((d) => ({ dodge: d, t: 0.5 }))), 100);
  assert.equal(score('dodge', dodge.key, seq.map(() => ({ dodge: 'left', t: 0.5 }))) < 100, true);
  assert.deepEqual(makeRun('dodge', 'same').key, makeRun('dodge', 'same').key, 'runs are reproducible from the seed');
});

test('challenges: the client never sees the answer key; prizes stay off by default', async () => {
  const { app, store, id, h } = await setup();
  const start = (await app.inject({ method: 'POST', url: '/api/challenges/interview/start', headers: h })).json();
  assert.ok(Array.isArray(start.rounds) && start.rounds.length === 5);
  assert.equal(JSON.stringify(start).includes('deltas'), false, 'the scoring key stays on the server');
  const key = (await store.db.query<{ key: { deltas: number[][] } }>('SELECT key FROM challenge_runs WHERE id = $1', [start.run])).rows[0]!.key;
  const log = key.deltas.map((d) => ({ pick: d.indexOf(Math.max(...d)), t: 3 }));
  const fin = (await app.inject({ method: 'POST', url: `/api/challenges/runs/${start.run}/finish`, headers: h, payload: { log } })).json();
  assert.equal(fin.score, 100);
  assert.equal(fin.passed, true);
  assert.equal(fin.ticket, null, 'no prize tickets while prizes are off');
  assert.equal((await app.inject({ method: 'POST', url: `/api/challenges/runs/${start.run}/finish`, headers: h, payload: { log } })).statusCode, 404, 'a run can be scored once');
  const board = (await app.inject({ url: '/api/challenges' })).json();
  assert.equal(board.prizes, 'off');
  assert.equal(board.leaderboards.interview[0].best, 100);

  // Prizes on (after legal sign-off), but only for verified 18+ players, once a day, within the pool.
  for (const [key, value] of [['prizes_enabled', true], ['prize_pool_naira', 1000]] as const) {
    await app.inject({ method: 'POST', url: '/api/admin/flags', headers: admin, payload: { key, value } });
  }
  await new Promise((r) => setTimeout(r, 10));
  const play = async () => {
    const s = (await app.inject({ method: 'POST', url: '/api/challenges/dodge/start', headers: h })).json();
    const k = (await store.db.query<{ key: { seq: string[] } }>('SELECT key FROM challenge_runs WHERE id = $1', [s.run])).rows[0]!.key;
    return (await app.inject({ method: 'POST', url: `/api/challenges/runs/${s.run}/finish`, headers: h, payload: { log: k.seq.map((d) => ({ dodge: d, t: 0.6 })) } })).json();
  };
  assert.equal((await play()).ticket, null, 'unverified players get no prizes');
  await store.db.query(`UPDATE players SET verified_at = now(), phone_hash = 'h1' WHERE id = $1`, [id]);
  assert.equal((await app.inject({ method: 'POST', url: '/api/me/age', headers: h, payload: { birthYear: new Date().getFullYear() - 16 } })).json().adult, false);
  assert.equal((await play()).ticket, null, 'under-18s get no prizes');
  await app.inject({ method: 'POST', url: '/api/me/age', headers: h, payload: { birthYear: 1995 } });
  assert.match(String((await play()).ticket), /^[0-9a-f]{16}$/, 'verified adult wins a ticket');
  assert.equal((await play()).ticket, null, 'one prize per phone per day');
  await app.close();
});

test('compliance: privacy and terms pages, data export, account deletion keeps election chain', async () => {
  const { app, store, id, h } = await setup();
  const privacy = await app.inject({ url: '/privacy' });
  assert.equal(privacy.statusCode, 200);
  assert.match(privacy.body, /<h1>Privacy policy<\/h1>/);
  assert.match((await app.inject({ url: '/terms' })).body, /Game money/);
  await app.inject({ method: 'PUT', url: '/api/profile', headers: h, payload: { bio: 'Hello Lagos' } });
  const exp = (await app.inject({ url: '/api/me/export', headers: h })).json();
  assert.equal(exp.account.id, id);
  assert.equal(exp.profile.bio, 'Hello Lagos');
  assert.equal(JSON.stringify(exp).includes('phone_hash'), false, 'the export never includes the phone hash');
  // A vote in the chain survives the voter's deletion, anonymised.
  const e = await store.db.query<{ id: string }>(`INSERT INTO elections (ward, office, week_start) VALUES ('yaba', 'ward-councillor', '2026-10-12') RETURNING id`);
  const c = await store.db.query<{ id: string }>(`INSERT INTO candidates (election_id, npc_name, slogan, policy, approved) VALUES ($1, 'NPC', 's', 'market-day', true) RETURNING id`, [e.rows[0]!.id]);
  await store.db.query(`INSERT INTO votes (election_id, candidate_id, voter, prev_hash, hash) VALUES ($1, $2, $3, 'genesis', 'abc')`, [e.rows[0]!.id, c.rows[0]!.id, id]);
  assert.equal((await app.inject({ method: 'DELETE', url: '/api/me', headers: h, payload: {} })).statusCode, 400, 'deletion needs explicit confirmation');
  assert.deepEqual((await app.inject({ method: 'DELETE', url: '/api/me', headers: h, payload: { confirm: 'DELETE' } })).json(), { ok: true, deleted: true });
  assert.equal((await app.inject({ url: '/api/me', headers: h })).statusCode, 401);
  const v = await store.db.query<{ voter: string | null }>('SELECT voter FROM votes');
  assert.equal(v.rows.length, 1);
  assert.equal(v.rows[0]!.voter, null);
  assert.equal((await app.inject({ method: 'POST', url: '/api/real/escrow', payload: {} })).statusCode, 403, 'the real-money lane is shut');
  await app.close();
});

test('telemetry: anonymous, whitelisted, rate-limited; admin summary', async () => {
  const { app } = await setup();
  const session = 'a1b2c3d4e5f6a7b8';
  const r = (await app.inject({ method: 'POST', url: '/api/telemetry', payload: {
    session, version: '0.9.0', platform: 'Android',
    events: [{ name: 'mission_complete', props: { id: 'P1', seconds: 300, email: 'x@y.z' } }, { name: 'steal_contacts', props: {} }],
    crashes: [{ message: 'Invalid call in C:\\Users\\Dean\\game\\main.gd', stack: 'at /home/dean/x' }],
  } })).json();
  assert.equal(r.stored, 2, 'unknown events are dropped');
  assert.equal((await app.inject({ method: 'POST', url: '/api/telemetry', payload: { session: 'not-hex', events: [] } })).statusCode, 400);
  const t = (await app.inject({ url: '/api/admin/telemetry', headers: admin })).json();
  assert.equal(t.events[0].name, 'mission_complete');
  assert.equal(String(t.crashes[0].message).includes('Dean'), false, 'home paths are scrubbed');
  await app.close();
});
