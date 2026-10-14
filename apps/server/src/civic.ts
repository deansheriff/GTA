import { createHash } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import type { Db } from './db.ts';
import { accountByToken, requireAccount } from './account.ts';
import { checkText } from './moderation.ts';
import { DISTRICTS } from './market.ts';

/**
 * F4 polls and ward elections (proposal F4). Weekly cycle in Lagos time (WAT, UTC+1):
 *   Mon–Tue nomination · Wed–Sat campaign · Sun 10:00–18:00 voting · Sun 18:00 count · Mon new term.
 * One vote per verified phone per election, recorded in an append-only hash chain (receipts).
 * NPC voting blocs are simulated in aggregate and capped at 50% of the total.
 * Winners pick from a fixed policy menu with bounded effects that the game applies in that ward.
 * All candidates are players or fictional NPCs: no real public figures, no real political ads.
 */
export const POLICIES: Record<string, { name: string; effect: string }> = {
  'market-day': { name: 'Market Day Discount', effect: 'Food costs 15% less in the ward' },
  'transformer-fund': { name: 'Transformer Fund', effect: 'Fewer NEPA cuts in the ward' },
  'fare-cap': { name: 'Danfo Fare Cap', effect: 'Danfo fares capped; passengers are more patient' },
  'clean-gutters': { name: 'Clean Gutters', effect: 'Less flooding; hygiene drops slower' },
};
const OFFICES = ['ward-councillor'];
const NPC_CANDIDATES = [
  { name: 'Alhaja Kemi Badmus', slogan: 'Market first, wahala last', policy: 'market-day' },
  { name: 'Engr. Tobi Lawal', slogan: 'Light is a right', policy: 'transformer-fund' },
  { name: 'Mrs. Ada Nwosu', slogan: 'Clean streets, clear minds', policy: 'clean-gutters' },
  { name: 'Baba Sule Danjuma', slogan: 'Fair fares for all', policy: 'fare-cap' },
];

const now = () => (process.env.CIVIC_FAKE_NOW ? new Date(process.env.CIVIC_FAKE_NOW) : new Date());

/** Phase of the weekly cycle and the Monday (WAT) that starts the week. */
export function cycle(at: Date = now()): { phase: 'nomination' | 'campaign' | 'voting' | 'counted'; weekStart: string } {
  const wat = new Date(at.getTime() + 60 * 60 * 1000);
  const dow = wat.getUTCDay(); // 0 Sunday
  const hour = wat.getUTCHours();
  const monday = new Date(Date.UTC(wat.getUTCFullYear(), wat.getUTCMonth(), wat.getUTCDate() - ((dow + 6) % 7)));
  let phase: 'nomination' | 'campaign' | 'voting' | 'counted' = 'campaign';
  if (dow === 1 || dow === 2) phase = 'nomination';
  else if (dow === 0 && hour >= 10 && hour < 18) phase = 'voting';
  else if (dow === 0 && hour >= 18) phase = 'counted';
  return { phase, weekStart: monday.toISOString().slice(0, 10) };
}

async function ensureElection(db: Db, ward: string, office: string): Promise<{ id: number; status: string; flagged: boolean }> {
  const { weekStart } = cycle();
  await db.query('INSERT INTO elections (ward, office, week_start) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING', [ward, office, weekStart]);
  const e = await db.query<{ id: string; status: string; flagged: boolean }>('SELECT id, status, flagged FROM elections WHERE ward = $1 AND office = $2 AND week_start = $3', [ward, office, weekStart]);
  const id = Number(e.rows[0]!.id);
  const npcs = await db.query('SELECT 1 FROM candidates WHERE election_id = $1 AND player_id IS NULL', [id]);
  if (npcs.rows.length === 0) {
    // Two fictional NPC candidates per ward, rotating weekly, so quiet wards still have a ballot.
    const seed = [...`${ward}${weekStart}`].reduce((s, c) => s + c.charCodeAt(0), 0);
    for (const k of [0, 1]) {
      const c = NPC_CANDIDATES[(seed + k) % NPC_CANDIDATES.length]!;
      await db.query('INSERT INTO candidates (election_id, npc_name, slogan, policy, approved) VALUES ($1, $2, $3, $4, true)', [id, c.name, c.slogan, c.policy]);
    }
  }
  return { id, status: e.rows[0]!.status, flagged: e.rows[0]!.flagged };
}

/** Tally: player votes + simulated NPC blocs (≤ 50% weight). Sets the winner and their policy. */
export async function count(db: Db, electionId: number): Promise<{ winner: number; tally: Record<string, number> }> {
  const cands = await db.query<{ id: string; npc_name: string | null; policy: string }>('SELECT id, npc_name, policy FROM candidates WHERE election_id = $1 AND approved ORDER BY id', [electionId]);
  const votes = await db.query<{ candidate_id: string; n: string }>('SELECT candidate_id, count(*) AS n FROM votes WHERE election_id = $1 GROUP BY candidate_id', [electionId]);
  const tally: Record<string, number> = {};
  for (const c of cands.rows) tally[c.id] = 0;
  let players = 0;
  for (const v of votes.rows) { tally[v.candidate_id] = (tally[v.candidate_id] ?? 0) + Number(v.n); players += Number(v.n); }
  // NPC blocs: traders, drivers, students… lean toward the policy that helps them. Their total is
  // capped so players always decide at least half the result (and all of it when NPCs tie).
  const npcTotal = Math.min(Math.max(players, 10), 200);
  const lean: Record<string, number> = { 'market-day': 0.32, 'fare-cap': 0.28, 'transformer-fund': 0.25, 'clean-gutters': 0.15 };
  const shares = cands.rows.map((c) => lean[c.policy] ?? 0.2);
  const sum = shares.reduce((a, b) => a + b, 0) || 1;
  const npcVotes: Record<string, number> = {};
  cands.rows.forEach((c, i) => {
    const n = Math.round((npcTotal * shares[i]!) / sum);
    npcVotes[c.id] = n;
    tally[c.id] = (tally[c.id] ?? 0) + n;
  });
  let winner = Number(cands.rows[0]?.id ?? 0);
  for (const c of cands.rows) if ((tally[c.id] ?? 0) > (tally[String(winner)] ?? -1)) winner = Number(c.id);
  const policy = cands.rows.find((c) => Number(c.id) === winner)?.policy ?? null;
  await db.query(`UPDATE elections SET status = 'counted', winner = $2, policy = $3, npc_votes = $4 WHERE id = $1`, [electionId, winner, policy, JSON.stringify(npcVotes)]);
  const e = await db.query<{ ward: string }>('SELECT ward FROM elections WHERE id = $1', [electionId]);
  if (policy) {
    await db.query(`DELETE FROM policies WHERE ward = $1`, [e.rows[0]!.ward]);
    await db.query(`INSERT INTO policies (ward, policy, election_id, until_ts) VALUES ($1, $2, $3, now() + interval '7 days')`, [e.rows[0]!.ward, policy, electionId]);
  }
  return { winner, tally };
}

export function registerCivic(app: FastifyInstance, db: Db): void {
  app.get('/api/policies', async (_req, reply) => {
    reply.header('cache-control', 'public, max-age=300');
    const r = await db.query<{ ward: string; policy: string }>('SELECT ward, policy FROM policies WHERE until_ts > now()');
    return { policies: Object.fromEntries(r.rows.map((p) => [p.ward, { id: p.policy, ...POLICIES[p.policy] }])), menu: POLICIES };
  });

  app.get('/api/elections/:ward', async (req, reply) => {
    reply.header('cache-control', 'no-store');
    const ward = (req.params as { ward: string }).ward;
    if (!DISTRICTS.includes(ward)) return reply.code(404).send({ error: 'no_ward' });
    const office = OFFICES[0]!;
    const e = await ensureElection(db, ward, office);
    const { phase } = cycle();
    if (phase === 'counted' && e.status !== 'counted' && !e.flagged) await count(db, e.id);
    const cands = await db.query<{ id: string; npc_name: string | null; name: string | null; slogan: string; policy: string; pid: string | null }>(
      'SELECT c.id, c.npc_name, p.name, c.slogan, c.policy, c.player_id AS pid FROM candidates c LEFT JOIN players p ON p.id = c.player_id WHERE c.election_id = $1 AND c.approved ORDER BY c.id',
      [e.id],
    );
    const h = String(req.headers.authorization ?? '');
    let myVote: string | null = null;
    const viewer = h.startsWith('Bearer ') ? await accountByToken(db, h.slice(7)) : null;
    if (viewer) {
      const me = await db.query<{ hash: string }>('SELECT hash FROM votes WHERE election_id = $1 AND voter = $2', [e.id, viewer.id]);
      myVote = me.rows[0]?.hash ?? null;
    }
    const fresh = await db.query<{ status: string; winner: string | null; npc_votes: Record<string, number> }>('SELECT status, winner, npc_votes FROM elections WHERE id = $1', [e.id]);
    const counted = fresh.rows[0]!.status === 'counted';
    let results: Record<string, number> | null = null;
    if (counted) {
      const v = await db.query<{ candidate_id: string; n: string }>('SELECT candidate_id, count(*) AS n FROM votes WHERE election_id = $1 GROUP BY candidate_id', [e.id]);
      results = {};
      for (const c of cands.rows) results[c.id] = Number(fresh.rows[0]!.npc_votes?.[c.id] ?? 0);
      for (const x of v.rows) results[x.candidate_id] = (results[x.candidate_id] ?? 0) + Number(x.n);
    }
    return {
      id: e.id, ward, office, phase: e.flagged ? 'frozen' : phase, counted, winner: fresh.rows[0]!.winner ? Number(fresh.rows[0]!.winner) : null,
      candidates: cands.rows.map((c) => ({ id: Number(c.id), name: c.npc_name ?? c.name, npc: c.npc_name !== null, pid: c.pid, slogan: c.slogan, policy: c.policy, policyName: POLICIES[c.policy]?.name })),
      myReceipt: myVote, results, menu: POLICIES,
    };
  });

  // Run for office: verified, account ≥ 14 days, level ≥ 8, no strikes, ₦5,000 market fee.
  app.post('/api/elections/:id/run', async (req, reply) => {
    const a = await requireAccount(db, req, reply, { verified: true });
    if (!a) return;
    const id = Number((req.params as { id: string }).id);
    if (cycle().phase !== 'nomination') return reply.code(409).send({ error: 'not_nomination' });
    const minDays = Number(process.env.CANDIDATE_MIN_DAYS ?? 14);
    if (a.ageHours < minDays * 24 || a.level < 8 || a.strikes > 0) return reply.code(403).send({ error: 'not_eligible', need: { days: minDays, level: 8, strikes: 0 } });
    const b = (req.body ?? {}) as { slogan?: unknown; policy?: unknown };
    const slogan = checkText(b.slogan, { verified: false, max: 60 });
    if (!slogan.ok) return reply.code(400).send({ error: `slogan_${slogan.reason}` });
    if (!POLICIES[String(b.policy)]) return reply.code(400).send({ error: 'bad_policy' });
    return db.tx(async (t) => {
      await t.query('INSERT INTO wallets (player_id) VALUES ($1) ON CONFLICT DO NOTHING', [a.id]);
      const paid = await t.query(`UPDATE wallets SET balance = balance - 5000 WHERE player_id = $1 AND balance >= 5000 RETURNING balance`, [a.id]);
      if (paid.rows.length === 0) return reply.code(402).send({ error: 'insufficient', need: 5000 });
      await t.query(`INSERT INTO wallet_ledger (player_id, delta, reason) VALUES ($1, -5000, 'Nomination fee')`, [a.id]);
      const ins = await t.query<{ id: string }>('INSERT INTO candidates (election_id, player_id, slogan, policy, approved) VALUES ($1, $2, $3, $4, true) ON CONFLICT DO NOTHING RETURNING id', [id, a.id, slogan.text, String(b.policy)]);
      if (ins.rows.length === 0) throw Object.assign(new Error('already'), { statusCode: 409 });
      return { ok: true, candidate: Number(ins.rows[0]!.id) };
    }).catch((e: { statusCode?: number }) => reply.code(e.statusCode ?? 500).send({ error: e.statusCode === 409 ? 'already_running' : 'failed' }));
  });

  app.post('/api/elections/:id/vote', async (req, reply) => {
    const a = await requireAccount(db, req, reply, { verified: true });
    if (!a) return;
    const id = Number((req.params as { id: string }).id);
    if (cycle().phase !== 'voting') return reply.code(409).send({ error: 'polls_closed' });
    const cand = Number((req.body as { candidate?: unknown } | null)?.candidate);
    return db.tx(async (t) => {
      const e = await t.query<{ flagged: boolean; status: string }>('SELECT flagged, status FROM elections WHERE id = $1 FOR UPDATE', [id]);
      if (!e.rows[0] || e.rows[0]!.flagged || e.rows[0]!.status === 'counted') return reply.code(409).send({ error: 'frozen' });
      const c = await t.query('SELECT 1 FROM candidates WHERE id = $1 AND election_id = $2 AND approved', [cand, id]);
      if (c.rows.length === 0) return reply.code(400).send({ error: 'bad_candidate' });
      const prev = await t.query<{ hash: string }>('SELECT hash FROM votes WHERE election_id = $1 ORDER BY id DESC LIMIT 1', [id]);
      const prevHash = prev.rows[0]?.hash ?? 'genesis';
      const hash = createHash('sha256').update(`${prevHash}|${id}|${cand}|${a.id}|${Date.now()}`).digest('hex');
      const ins = await t.query('INSERT INTO votes (election_id, candidate_id, voter, prev_hash, hash) VALUES ($1, $2, $3, $4, $5) ON CONFLICT DO NOTHING RETURNING id', [id, cand, a.id, prevHash, hash]);
      if (ins.rows.length === 0) return reply.code(409).send({ error: 'already_voted' });
      // Anomaly check: a burst of votes from brand-new accounts freezes the election for review.
      const burst = await t.query<{ n: string }>(
        `SELECT count(*) AS n FROM votes v JOIN players p ON p.id = v.voter
          WHERE v.election_id = $1 AND v.created_at > now() - interval '10 minutes' AND p.created_at > now() - interval '7 days'`,
        [id],
      );
      if (Number(burst.rows[0]!.n) > Number(process.env.VOTE_BURST_LIMIT ?? 25)) await t.query('UPDATE elections SET flagged = true WHERE id = $1', [id]);
      return { ok: true, receipt: hash };
    });
  });

  // Public audit: the hash chain without voter identities.
  app.get('/api/elections/:id/audit', async (req, reply) => {
    reply.header('cache-control', 'no-store');
    const id = Number((req.params as { id: string }).id);
    const r = await db.query<{ prev_hash: string; hash: string }>('SELECT prev_hash, hash FROM votes WHERE election_id = $1 ORDER BY id', [id]);
    let ok = true;
    let prev = 'genesis';
    for (const v of r.rows) {
      if (v.prev_hash !== prev) ok = false;
      prev = v.hash;
    }
    return { votes: r.rows.length, chainIntact: ok, receipts: r.rows.map((v) => v.hash) };
  });

  // ---------- community polls ----------
  app.get('/api/polls', async (req, reply) => {
    reply.header('cache-control', 'no-store');
    const r = await db.query<{ id: string; question: string; kind: string; options: string[]; show_results: string; closes_at: Date; min_turnout: number }>(
      `SELECT id, question, kind, options, show_results, closes_at, min_turnout FROM polls WHERE status = 'open' AND opens_at <= now() ORDER BY id DESC LIMIT 20`,
    );
    const out = [];
    for (const p of r.rows) {
      const closed = new Date(p.closes_at) < new Date();
      const v = await db.query<{ choices: number[] }>('SELECT choices FROM poll_votes WHERE poll_id = $1', [p.id]);
      const counts = (p.options as string[]).map(() => 0);
      for (const x of v.rows) for (const i of x.choices) if (counts[i] !== undefined) counts[i]++;
      const show = closed ? v.rows.length >= Number(p.min_turnout) : p.show_results === 'live';
      out.push({ id: Number(p.id), question: p.question, kind: p.kind, options: p.options, closed, closes: p.closes_at, turnout: v.rows.length, results: show ? counts : null });
    }
    return { polls: out };
  });

  // Players at level ≥ 10 may propose polls; they wait for a moderator (admin approves).
  app.post('/api/polls', async (req, reply) => {
    const a = await requireAccount(db, req, reply, { verified: true });
    if (!a) return;
    if (a.level < 10) return reply.code(403).send({ error: 'level_10_needed' });
    const b = (req.body ?? {}) as { question?: unknown; options?: unknown; kind?: unknown; hours?: unknown };
    const q = checkText(b.question, { verified: true, max: 120 });
    if (!q.ok) return reply.code(400).send({ error: `question_${q.reason}` });
    const opts = Array.isArray(b.options) ? b.options.slice(0, 6).map((o) => checkText(o, { verified: true, max: 40 })) : [];
    if (opts.length < 2 || opts.some((o) => !o.ok)) return reply.code(400).send({ error: 'bad_options' });
    const hours = Math.max(1, Math.min(168, Number(b.hours) || 48));
    const r = await db.query<{ id: string }>(
      `INSERT INTO polls (question, kind, options, created_by, status, closes_at) VALUES ($1, $2, $3, $4, 'pending', now() + ($5 || ' hours')::interval) RETURNING id`,
      [q.text, b.kind === 'multi' ? 'multi' : 'single', JSON.stringify(opts.map((o) => (o as { text: string }).text)), a.id, String(hours)],
    );
    return { ok: true, id: Number(r.rows[0]!.id), status: 'pending' };
  });

  app.post('/api/polls/:id/vote', async (req, reply) => {
    const a = await requireAccount(db, req, reply, { verified: true });
    if (!a) return;
    const id = Number((req.params as { id: string }).id);
    const p = await db.query<{ kind: string; options: string[] }>(`SELECT kind, options FROM polls WHERE id = $1 AND status = 'open' AND closes_at > now() AND opens_at <= now()`, [id]);
    if (!p.rows[0]) return reply.code(404).send({ error: 'closed' });
    const raw = (req.body as { choices?: unknown } | null)?.choices;
    const choices = Array.isArray(raw) ? [...new Set(raw.map(Number))] : [];
    if (choices.length === 0 || choices.some((c) => !Number.isInteger(c) || c < 0 || c >= p.rows[0]!.options.length) || (p.rows[0]!.kind === 'single' && choices.length !== 1)) return reply.code(400).send({ error: 'bad_choice' });
    const r = await db.query('INSERT INTO poll_votes (poll_id, player_id, choices) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING RETURNING poll_id', [id, a.id, JSON.stringify(choices)]);
    if (r.rows.length === 0) return reply.code(409).send({ error: 'already_voted' });
    return { ok: true };
  });
}
