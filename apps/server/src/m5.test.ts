import { test } from 'node:test';
import assert from 'node:assert/strict';
import WebSocket from 'ws';
import { buildApp } from './app.ts';
import { memoryStore } from './store.ts';
import { checkText, addStrike } from './moderation.ts';
import { cycle } from './civic.ts';
import { normalisePhone } from './auth.ts';

process.env.NODE_ENV = 'test';
process.env.OTP_DEV_ECHO = '1';
process.env.CHAT_MIN_AGE_HOURS = '0';
process.env.GIG_MIN_SECONDS = '0';
process.env.CANDIDATE_MIN_DAYS = '0';

const sent: { to: string; message: string }[] = [];
const sms = { name: 'test', async send(to: string, message: string) { sent.push({ to, message }); } };

async function setup() {
  const store = await memoryStore();
  const app = await buildApp({ version: '0', geminiConfigured: false, store, sms });
  const guest = async (name: string) => {
    const g = await store.createGuest(name, {});
    return { id: g.player.id, token: g.token, h: { authorization: `Bearer ${g.token}` } };
  };
  const verify = (id: string) => store.db.query('UPDATE players SET verified_at = now(), level = 12 WHERE id = $1', [id]);
  return { app, store, guest, verify };
}

test('moderation: personal data, scams, links, abuse and hate are blocked before anyone sees them', async () => {
  assert.equal(checkText('How far, Tunde?').ok, true);
  assert.deepEqual(checkText('call me 08031234567'), { ok: false, reason: 'personal_data' });
  assert.deepEqual(checkText('send to my opay abeg'), { ok: false, reason: 'off_platform_payment' });
  assert.deepEqual(checkText('acct 0123456789 GTB'), { ok: false, reason: 'off_platform_payment' });
  assert.deepEqual(checkText('selling game money cheap'), { ok: false, reason: 'off_platform_payment' });
  assert.deepEqual(checkText('see www.scam.xyz'), { ok: false, reason: 'links_need_verification' });
  assert.equal(checkText('see https://my.portfolio.ng', { verified: true }).ok, true);
  assert.deepEqual(checkText('you be mumu'), { ok: false, reason: 'abuse' });
  assert.equal(checkText('x'.repeat(300)).ok, false);
  assert.equal(normalisePhone('0803 123 4567'), '+2348031234567');
  assert.equal(normalisePhone('12'), null);
});

test('strike ladder: warning, 24 h mute, 7-day ban, permanent', async () => {
  const { app, store, guest } = await setup();
  const p = await guest('Wahala');
  assert.equal(await addStrike(store.db, p.id, 't', 'test'), 'warning');
  assert.equal(await addStrike(store.db, p.id, 't', 'test'), 'mute_24h');
  assert.equal(await addStrike(store.db, p.id, 't', 'test'), 'ban_7d');
  assert.equal((await app.inject({ url: '/api/me', headers: p.h })).statusCode, 403, 'banned players are refused');
  assert.equal(await addStrike(store.db, p.id, 't', 'test'), 'ban_permanent');
  await app.close();
});

test('phone OTP: verify an account, wrong codes count, the same phone signs in on a new device', async () => {
  const { app, guest } = await setup();
  const a = await guest('Ngozi');
  const start = await app.inject({ method: 'POST', url: '/api/auth/otp/start', headers: a.h, payload: { phone: '08031234567' } });
  assert.equal(start.statusCode, 200);
  const code = start.json().devCode as string;
  assert.match(sent.at(-1)!.message, new RegExp(code));
  assert.equal(sent.at(-1)!.to, '+2348031234567');
  const wrong = await app.inject({ method: 'POST', url: '/api/auth/otp/verify', headers: a.h, payload: { phone: '08031234567', code: code === '111111' ? '222222' : '111111' } });
  assert.equal(wrong.json().error, 'wrong_code');
  const ok = await app.inject({ method: 'POST', url: '/api/auth/otp/verify', headers: a.h, payload: { phone: '08031234567', code } });
  assert.deepEqual(ok.json(), { ok: true, verified: true, switched: false });
  const me = (await app.inject({ url: '/api/me', headers: a.h })).json();
  assert.equal(me.verified, true);
  assert.equal(me.phone, '••••67');
  // New phone: a fresh guest verifies the same number and gets Ngozi's account back.
  const b = await guest('NewPhone');
  const c2 = (await app.inject({ method: 'POST', url: '/api/auth/otp/start', headers: b.h, payload: { phone: '+2348031234567' } })).json().devCode;
  const sw = (await app.inject({ method: 'POST', url: '/api/auth/otp/verify', headers: b.h, payload: { phone: '+2348031234567', code: c2 } })).json();
  assert.equal(sw.switched, true);
  assert.equal(sw.id, a.id);
  assert.equal((await app.inject({ url: '/api/me', headers: { authorization: `Bearer ${sw.token}` } })).json().name, 'Ngozi');
  assert.equal((await app.inject({ url: '/api/me', headers: a.h })).statusCode, 401, 'the old token is retired');
  // Rate limit: three codes per phone per hour.
  const c = await guest('Spam');
  for (let i = 0; i < 3; i++) await app.inject({ method: 'POST', url: '/api/auth/otp/start', headers: c.h, payload: { phone: '08099999999' } });
  assert.equal((await app.inject({ method: 'POST', url: '/api/auth/otp/start', headers: c.h, payload: { phone: '08099999999' } })).statusCode, 429);
  await app.close();
});

function waitFor(ws: WebSocket, pred: (m: any) => boolean, ms = 3000): Promise<any> {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timeout')), ms);
    const on = (data: unknown) => {
      const m = JSON.parse(String(data));
      if (pred(m)) { clearTimeout(t); ws.off('message', on); resolve(m); }
    };
    ws.on('message', on);
  });
}

test('chat, DMs, blocks, reports and the moderation queue', async () => {
  process.env.ADMIN_TOKEN = 'test-admin-token-0123456789abcdef';
  const { app, guest } = await setup();
  await app.listen({ port: 0, host: '127.0.0.1' });
  const url = `ws://127.0.0.1:${(app.server.address() as { port: number }).port}/ws`;
  const a = await guest('Tunde');
  const b = await guest('KC');
  const wa = new WebSocket(url);
  const wb = new WebSocket(url);
  await Promise.all([new Promise((r) => wa.on('open', r)), new Promise((r) => wb.on('open', r))]);
  const welA = waitFor(wa, (m) => m.t === 'welcome');
  wa.send(JSON.stringify({ t: 'hello', token: a.token, name: 'Tunde', look: {}, x: 100, y: 100 }));
  await welA;
  const welB = waitFor(wb, (m) => m.t === 'welcome');
  const meet = waitFor(wa, (m) => m.t === 'snap' && m.meet?.some((p: any) => p.pid === b.id));
  wb.send(JSON.stringify({ t: 'hello', token: b.token, name: 'KC', look: {}, x: 150, y: 100 }));
  await welB;
  await meet;

  const got = waitFor(wb, (m) => m.t === 'chat');
  wa.send(JSON.stringify({ t: 'chat', text: 'Owambe for Lekki tonight!' }));
  const msg = await got;
  assert.equal(msg.text, 'Owambe for Lekki tonight!');
  assert.equal(msg.pid, a.id);

  const blocked = waitFor(wa, (m) => m.t === 'err');
  wa.send(JSON.stringify({ t: 'chat', text: 'call me on 08031234567' }));
  assert.equal((await blocked).code, 'blocked_personal_data');

  const dm = waitFor(wb, (m) => m.t === 'dm');
  wa.send(JSON.stringify({ t: 'dm', to: b.id, text: 'Where are you?' }));
  assert.equal((await dm).text, 'Where are you?');
  const hist = (await app.inject({ url: `/api/dms?with=${a.id}`, headers: b.h })).json();
  assert.equal(hist.messages.length, 1);

  // KC blocks Tunde: no more chat or DMs from him.
  assert.equal((await app.inject({ method: 'POST', url: '/api/blocks', headers: b.h, payload: { pid: a.id } })).statusCode, 200);
  let leaked = false;
  wb.on('message', (d) => { const m = JSON.parse(String(d)); if ((m.t === 'chat' || m.t === 'dm') && m.pid === a.id) leaked = true; });
  const ack = waitFor(wa, (m) => m.t === 'dm' && m.sent);
  wa.send(JSON.stringify({ t: 'dm', to: b.id, text: 'Hello?' }));
  wa.send(JSON.stringify({ t: 'chat', text: 'Anybody?' }));
  await ack;
  await new Promise((r) => setTimeout(r, 200));
  assert.equal(leaked, false, 'blocked players are not delivered');

  // Report the first message → moderator strikes from the queue.
  const rep = await app.inject({ method: 'POST', url: '/api/reports', headers: b.h, payload: { message: msg.id, reason: 'spam' } });
  assert.equal(rep.statusCode, 200);
  const admin = { authorization: 'Bearer test-admin-token-0123456789abcdef', 'x-moderator': 'Ada' };
  const queue = (await app.inject({ url: '/api/admin/reports', headers: admin })).json();
  assert.equal(queue.reports[0].context, 'Owambe for Lekki tonight!');
  const res = (await app.inject({ method: 'POST', url: `/api/admin/reports/${queue.reports[0].id}/resolve`, headers: admin, payload: { action: 'strike', note: 'test' } })).json();
  assert.equal(res.result, 'warning');
  const audit = (await app.inject({ url: '/api/admin/actions', headers: admin })).json();
  assert.equal(audit.actions[0].actor, 'Ada');
  assert.equal((await app.inject({ url: '/api/admin/stats', headers: { authorization: 'Bearer wrong' } })).statusCode, 401);
  wa.close();
  wb.close();
  await app.close();
});

test('gig board: wallet, NPC gigs, escrow, gameplay completion, refunds and ratings', async () => {
  const { app, guest, verify } = await setup();
  const poster = await guest('Aunty');
  const worker = await guest('Sule');
  // Guests can browse, but taking or posting gigs needs a verified phone.
  const board = (await app.inject({ url: '/api/gigs?skill=cooking' })).json();
  assert.ok(board.gigs.length >= 1 && board.gigs[0].npc, 'NPC gigs keep the board alive');
  assert.equal((await app.inject({ method: 'POST', url: `/api/gigs/${board.gigs[0].id}/take`, headers: worker.h })).statusCode, 403);
  await verify(poster.id);
  await verify(worker.id);
  await app.inject({ method: 'POST', url: '/api/wallet/move', headers: poster.h, payload: { amount: 20000 } });
  assert.equal((await app.inject({ url: '/api/wallet', headers: poster.h })).json().balance, 20000);
  // Post a gig: pay × slots + 2% fee is escrowed.
  const post = await app.inject({ method: 'POST', url: '/api/gigs', headers: poster.h, payload: { title: 'Cook for my canteen', description: 'Lunch rush, jollof and pepper soup.', skill: 'cooking', district: 'surulere', pay: 5000, slots: 2 } });
  assert.equal(post.statusCode, 200, post.body);
  assert.equal((await app.inject({ url: '/api/wallet', headers: poster.h })).json().balance, 20000 - 10000 - 200);
  const scam = await app.inject({ method: 'POST', url: '/api/gigs', headers: poster.h, payload: { title: 'Easy money', description: 'pay to my opay first', skill: 'hustle', district: 'yaba', pay: 1000 } });
  assert.equal(scam.json().error, 'description_off_platform_payment');
  const gid = post.json().id;
  const take = await app.inject({ method: 'POST', url: `/api/gigs/${gid}/take`, headers: worker.h });
  assert.equal(take.json().skill, 'cooking');
  assert.equal((await app.inject({ method: 'POST', url: `/api/gigs/${gid}/take`, headers: worker.h })).statusCode, 409);
  const fin = (await app.inject({ method: 'POST', url: `/api/gigs/${gid}/finish`, headers: worker.h, payload: { score: 82 } })).json();
  assert.deepEqual(fin, { ok: true, passed: true, paid: 5000 });
  assert.equal((await app.inject({ url: '/api/wallet', headers: worker.h })).json().balance, 5000);
  // Ratings after a completed gig.
  assert.equal((await app.inject({ method: 'POST', url: `/api/gigs/${gid}/rate`, headers: poster.h, payload: { pid: worker.id, stars: 5, text: 'Sharp guy' } })).statusCode, 200);
  assert.equal((await app.inject({ method: 'POST', url: `/api/gigs/${gid}/rate`, headers: worker.h, payload: { pid: poster.id, stars: 6 } })).statusCode, 400);
  // Close: the unfilled slot comes back.
  assert.equal((await app.inject({ method: 'POST', url: `/api/gigs/${gid}/close`, headers: poster.h })).json().refunded, 5000);
  // Withdraw to pocket with the 5% tax.
  const w = (await app.inject({ method: 'POST', url: '/api/wallet/move', headers: worker.h, payload: { amount: -5000 } })).json();
  assert.deepEqual(w, { ok: true, toSave: 4750, tax: 250 });
  const prof = (await app.inject({ url: `/api/profiles/${worker.id}` })).json();
  assert.equal(prof.gigBadges.cooking, 1);
  assert.equal(prof.rating, 5);
  await app.close();
});

test('profiles: visibility per section and opt-in search', async () => {
  const { app, guest } = await setup();
  const a = await guest('KC');
  const b = await guest('Stranger');
  const put = await app.inject({ method: 'PUT', url: '/api/profile', headers: a.h, payload: {
    bio: 'Content creator from Yaba.', district: 'yaba', languages: ['English', 'Pidgin', 'Klingon'],
    skills: [{ skill: 'video', level: 4 }, { skill: 'hacking', level: 5 }], visibility: { bio: 'public', skills: 'members', cv: 'me' },
    searchable: true, cv: { skills: { filming: 6, charisma: 4 }, missions: 22, ending: 'C' },
  } });
  assert.equal(put.json().level, 10);
  const anon = (await app.inject({ url: `/api/profiles/${a.id}` })).json();
  assert.equal(anon.bio, 'Content creator from Yaba.');
  assert.equal(anon.skills, null, 'members-only sections are hidden from anonymous viewers');
  assert.deepEqual(anon.languages, ['English', 'Pidgin']);
  const member = (await app.inject({ url: `/api/profiles/${a.id}`, headers: b.h })).json();
  assert.deepEqual(member.skills, [{ skill: 'video', level: 4 }]);
  assert.equal(member.cv, null, '"only me" stays private');
  assert.equal((await app.inject({ url: `/api/profiles/${a.id}`, headers: a.h })).json().cv.missions, 22);
  const found = (await app.inject({ url: '/api/profiles?skill=video' })).json();
  assert.equal(found.people.length, 1);
  await app.close();
});

test('ward elections: phases, one vote per verified player, hash-chain audit, count and policy', async () => {
  const { app, guest, verify } = await setup();
  assert.equal(cycle(new Date('2026-10-12T09:00:00Z')).phase, 'nomination'); // Monday 10:00 WAT
  assert.equal(cycle(new Date('2026-10-14T09:00:00Z')).phase, 'campaign'); // Wednesday
  assert.equal(cycle(new Date('2026-10-18T11:00:00Z')).phase, 'voting'); // Sunday 12:00 WAT
  assert.equal(cycle(new Date('2026-10-18T18:00:00Z')).phase, 'counted'); // Sunday 19:00 WAT

  const p = await guest('Teacher');
  await verify(p.id);
  process.env.CIVIC_FAKE_NOW = '2026-10-12T09:00:00Z';
  const el = (await app.inject({ url: '/api/elections/yaba' })).json();
  assert.equal(el.phase, 'nomination');
  assert.ok(el.candidates.length >= 2 && el.candidates.every((c: any) => c.npc), 'two fictional NPC candidates');
  assert.equal((await app.inject({ method: 'POST', url: `/api/elections/${el.id}/run`, headers: p.h, payload: { slogan: 'Light for real', policy: 'transformer-fund' } })).json().error, 'insufficient');
  await app.inject({ method: 'POST', url: '/api/wallet/move', headers: p.h, payload: { amount: 6000 } });
  const run = await app.inject({ method: 'POST', url: `/api/elections/${el.id}/run`, headers: p.h, payload: { slogan: 'Light for real', policy: 'transformer-fund' } });
  assert.equal(run.statusCode, 200, run.body);
  const myCand = run.json().candidate;

  process.env.CIVIC_FAKE_NOW = '2026-10-18T11:00:00Z';
  const voters = [];
  for (let i = 0; i < 12; i++) { const v = await guest(`Voter${i}`); await verify(v.id); voters.push(v); }
  const unverified = await guest('NoPhone');
  assert.equal((await app.inject({ method: 'POST', url: `/api/elections/${el.id}/vote`, headers: unverified.h, payload: { candidate: myCand } })).statusCode, 403);
  for (const v of voters) {
    const r = await app.inject({ method: 'POST', url: `/api/elections/${el.id}/vote`, headers: v.h, payload: { candidate: myCand } });
    assert.equal(r.statusCode, 200, r.body);
  }
  assert.equal((await app.inject({ method: 'POST', url: `/api/elections/${el.id}/vote`, headers: voters[0]!.h, payload: { candidate: myCand } })).statusCode, 409, 'one vote each');
  const audit = (await app.inject({ url: `/api/elections/${el.id}/audit` })).json();
  assert.equal(audit.votes, 12);
  assert.equal(audit.chainIntact, true);
  const view = (await app.inject({ url: '/api/elections/yaba', headers: voters[3]!.h })).json();
  assert.equal(view.myReceipt, audit.receipts[3]);

  process.env.CIVIC_FAKE_NOW = '2026-10-18T18:30:00Z';
  const counted = (await app.inject({ url: '/api/elections/yaba' })).json();
  assert.equal(counted.counted, true);
  assert.equal(counted.winner, myCand, 'players outvote the NPC blocs (capped at half)');
  const pol = (await app.inject({ url: '/api/policies' })).json();
  assert.equal(pol.policies.yaba.id, 'transformer-fund');
  delete process.env.CIVIC_FAKE_NOW;
  await app.close();
});

test('community polls: admin-created, one vote each, results after close', async () => {
  process.env.ADMIN_TOKEN = 'test-admin-token-0123456789abcdef';
  const { app, guest, verify } = await setup();
  const admin = { authorization: 'Bearer test-admin-token-0123456789abcdef' };
  const created = (await app.inject({ method: 'POST', url: '/api/admin/polls', headers: admin, payload: { question: 'Best jollof in Lagos?', options: ['Aunty Boss Kitchen', 'Royal Pavilion', 'Mama-put by the bridge'], showResults: 'live' } })).json();
  const v = await guest('Voter');
  await verify(v.id);
  assert.equal((await app.inject({ method: 'POST', url: `/api/polls/${created.id}/vote`, headers: v.h, payload: { choices: [0] } })).statusCode, 200);
  assert.equal((await app.inject({ method: 'POST', url: `/api/polls/${created.id}/vote`, headers: v.h, payload: { choices: [1] } })).statusCode, 409);
  const polls = (await app.inject({ url: '/api/polls' })).json();
  assert.deepEqual(polls.polls[0].results, [1, 0, 0]);
  // Players at level ≥ 10 can propose; proposals wait for approval.
  const prop = (await app.inject({ method: 'POST', url: '/api/polls', headers: v.h, payload: { question: 'More danfo routes?', options: ['Yes', 'No'] } })).json();
  assert.equal(prop.status, 'pending');
  await app.close();
});
