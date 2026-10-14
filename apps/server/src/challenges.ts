import { createHash, randomBytes } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import type { Db } from './db.ts';
import { requireAccount } from './account.ts';
import type { Flags } from './flags.ts';

/**
 * F5 skill challenges (proposal F5 ⚖️). Free entry, skill only, no purchase or stake ever.
 *
 * Anti-cheat by server replay: the server creates the run (the exact beat times, question order or
 * jerrycan sequence) and keeps it; the client plays it and sends back only its input log; the
 * server re-scores the log against its own copy. Impossible inputs score zero.
 *
 * Rewards: points and weekly leaderboards now. Prize tickets (airtime/data) are issued only when
 * the owner switches on `prizes_enabled` after legal sign-off 🔒: 18+ (declared), phone-verified,
 * one ticket per phone per day, a weekly cap, a monthly pool that closes when empty, and delayed,
 * idempotent fulfilment through a provider (none is wired in until the owner picks one).
 */
export const GAMES = ['spray', 'interview', 'dodge'] as const;
type Game = (typeof GAMES)[number];

const QUESTIONS = [
  { q: 'Purpose of your visit?', a: [['To study content creation. And come back.', 12], ['Vacation. For… ten years.', -15], ['Japa. I mean— tourism!', -20]] },
  { q: 'Who is sponsoring you?', a: [['My savings. Here are six months of statements.', 15], ['My uncle. He is… somewhere.', -10], ['God.', -5]] },
  { q: "Describe your relationship with your grandmother's goat.", a: [['Cordial. We respect each other\'s boundaries.', 12], ["The goat and I don't talk about that.", -8], ['Is this part of the visa?', -12]] },
  { q: 'Have you ever been to Northvale?', a: [['No, sir. First time applying.', 10], ['In my dreams, every night.', -10], ['My cousin has. Does that count?', -6]] },
  { q: 'What will you do if your visa is refused?', a: [['Improve my documents and try again.', 14], ['Cry. Publicly. On camera.', -10], ['Go by road.', -25]] },
  { q: 'Why are you sweating?', a: [['Lagos heat, sir. And respect.', 10], ["Because you haven't blinked in four minutes.", -6], ["I'm not sweating, the chair is.", -8]] },
  { q: 'Name three things you will bring back to Nigeria.', a: [['Skills, savings and a winter jacket for my mother.', 14], ['A Northvale wife.', -15], ["Nothing. I'm not coming— I mean everything!", -22]] },
] as const;

function rng(seed: string) {
  let h = createHash('sha256').update(seed).digest();
  let i = 0;
  return () => {
    if (i + 4 > h.length) { h = createHash('sha256').update(h).digest(); i = 0; }
    const v = h.readUInt32BE(i) / 0x100000000;
    i += 4;
    return v;
  };
}

/** The run the client must play (sent to it) and the answer key (kept on the server). */
export function makeRun(game: Game, seed: string): { play: Record<string, unknown>; key: Record<string, unknown> } {
  const r = rng(seed);
  if (game === 'spray') {
    const bpm = 96 + Math.floor(r() * 24);
    const interval = 60 / bpm;
    const beats: number[] = [];
    let t = 1.2;
    for (let i = 0; i < 24; i++) { beats.push(Number(t.toFixed(3))); t += interval * (r() < 0.2 ? 0.5 : 1); }
    return { play: { beats, bpm }, key: { beats } };
  }
  if (game === 'interview') {
    const order = [...QUESTIONS.keys()].sort(() => r() - 0.5).slice(0, 5);
    const rounds = order.map((qi) => {
      const perm = [0, 1, 2].sort(() => r() - 0.5);
      return { q: QUESTIONS[qi]!.q, answers: perm.map((p) => QUESTIONS[qi]!.a[p]![0]), deltas: perm.map((p) => QUESTIONS[qi]!.a[p]![1]) };
    });
    return { play: { rounds: rounds.map((x) => ({ q: x.q, answers: x.answers })), round_time: 7 }, key: { deltas: rounds.map((x) => x.deltas) } };
  }
  const dirs = ['left', 'right', 'high'];
  const seq = Array.from({ length: 10 }, () => dirs[Math.floor(r() * 3)]!);
  return { play: { seq, windows: seq.map((_, i) => Number(Math.max(0.9, 1.6 - i * 0.08).toFixed(2))) }, key: { seq } };
}

/** Re-score an input log against the server's copy of the run. Mirrors the game's rules. */
export function score(game: Game, key: Record<string, any>, log: unknown): number {
  if (!Array.isArray(log) || log.length > 200) return 0;
  if (game === 'spray') {
    const beats: number[] = key.beats;
    const taps = log.map(Number).filter((x) => Number.isFinite(x) && x >= 0 && x < 120).sort((a, b) => a - b);
    if (taps.length > beats.length * 3) return 0; // button-mashing isn't rhythm
    const used = new Set<number>();
    let points = 0;
    for (const t of taps) {
      let best = -1;
      let bd = 9;
      beats.forEach((b, i) => { const d = Math.abs(b - t); if (!used.has(i) && d < bd) { bd = d; best = i; } });
      if (best < 0 || bd > 0.32) continue;
      used.add(best);
      points += bd < 0.09 ? 100 : 60;
    }
    return Math.round(points / beats.length);
  }
  if (game === 'interview') {
    const deltas: number[][] = key.deltas;
    let composure = 60;
    for (let i = 0; i < deltas.length; i++) {
      const e = log[i] as { pick?: number; t?: number } | undefined;
      const late = !e || !Number.isFinite(e.t) || Number(e.t) > 7 || Number(e.t) < 0.25; // faster than reading is a bot
      composure = Math.max(0, Math.min(100, composure + (late || !Number.isInteger(e?.pick) || e!.pick! < 0 || e!.pick! > 2 ? -12 : deltas[i]![e!.pick!]!)));
    }
    return Math.round(composure);
  }
  const seq: string[] = key.seq;
  let hits = 0;
  for (let i = 0; i < seq.length; i++) {
    const e = log[i] as { dodge?: string; t?: number } | undefined;
    const window = Math.max(0.9, 1.6 - i * 0.08);
    if (!e || e.dodge !== seq[i] || !Number.isFinite(e.t) || Number(e.t) > window || Number(e.t) < 0.12) hits++;
  }
  return Math.round(((seq.length - hits) / seq.length) * 100);
}

const TARGET: Record<Game, number> = { spray: 75, interview: 70, dodge: 80 };
const today = () => new Date(Date.now() + 3600_000).toISOString().slice(0, 10); // Lagos date

export function registerChallenges(app: FastifyInstance, db: Db, flags: Flags): void {
  app.get('/api/challenges', async (req, reply) => {
    reply.header('cache-control', 'no-store');
    const prizes = await flags.get<boolean>('prizes_enabled');
    const lb = await db.query<{ game: string; name: string; best: number }>(
      `SELECT DISTINCT ON (r.game, r.player_id) r.game, p.name, r.score AS best FROM challenge_runs r JOIN players p ON p.id = r.player_id
        WHERE r.status = 'scored' AND r.created_at > now() - interval '7 days' ORDER BY r.game, r.player_id, r.score DESC`,
    );
    const boards: Record<string, { name: string; best: number }[]> = {};
    for (const g of GAMES) boards[g] = lb.rows.filter((x) => x.game === g).sort((a, b) => b.best - a.best).slice(0, 10).map((x) => ({ name: x.name, best: Number(x.best) }));
    return {
      day: today(),
      games: GAMES.map((g) => ({ id: g, target: TARGET[g] })),
      leaderboards: boards,
      prizes: prizes ? 'on' : 'off',
      rules: 'Free to play, skill only. No purchase needed. Prizes (when switched on): 18+, phone-verified, one per phone per day.',
    };
  });

  // Start: the server creates and remembers the run; the client gets only what it needs to play.
  app.post('/api/challenges/:game/start', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    const game = (req.params as { game: string }).game as Game;
    if (!GAMES.includes(game)) return reply.code(404).send({ error: 'no_game' });
    const open = await db.query<{ n: string }>(`SELECT count(*) AS n FROM challenge_runs WHERE player_id = $1 AND created_at > now() - interval '1 hour'`, [a.id]);
    if (Number(open.rows[0]!.n) >= 20) return reply.code(429).send({ error: 'slow_down' });
    const seed = randomBytes(16).toString('hex');
    const run = makeRun(game, seed);
    const r = await db.query<{ id: string }>('INSERT INTO challenge_runs (player_id, game, seed, key) VALUES ($1, $2, $3, $4) RETURNING id', [a.id, game, seed, JSON.stringify(run.key)]);
    return { run: Number(r.rows[0]!.id), game, target: TARGET[game], ...run.play };
  });

  app.post('/api/challenges/runs/:id/finish', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    const id = Number((req.params as { id: string }).id);
    const r = await db.query<{ game: Game; key: Record<string, unknown>; status: string; age: number }>(
      `SELECT game, key, status, EXTRACT(EPOCH FROM (now() - created_at)) AS age FROM challenge_runs WHERE id = $1 AND player_id = $2`,
      [id, a.id],
    );
    const run = r.rows[0];
    if (!run || run.status !== 'open') return reply.code(404).send({ error: 'no_run' });
    if (Number(run.age) > 15 * 60) return reply.code(410).send({ error: 'expired' });
    const s = score(run.game, run.key, (req.body as { log?: unknown } | null)?.log);
    const points = Math.max(0, s - 40) * 2;
    await db.query(`UPDATE challenge_runs SET status = 'scored', score = $2, points = $3 WHERE id = $1`, [id, s, points]);
    let ticket: string | null = null;
    if (s >= TARGET[run.game]) ticket = await maybeTicket(db, flags, a.id, a.verified);
    return { score: s, target: TARGET[run.game], passed: s >= TARGET[run.game], points, ticket };
  });

  // Self-declared age (proposal §7: 18+ for prizes); stored as a birth year only.
  app.post('/api/me/age', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    const year = Number((req.body as { birthYear?: unknown } | null)?.birthYear);
    const now = new Date().getFullYear();
    if (!Number.isInteger(year) || year < now - 110 || year > now) return reply.code(400).send({ error: 'bad_year' });
    await db.query('UPDATE players SET birth_year = $2 WHERE id = $1', [a.id, year]);
    return { ok: true, adult: now - year >= 18 };
  });
}

/**
 * Prize tickets: only with prizes switched on, verified, 18+, one per day per phone, inside the
 * weekly cap and the monthly pool. Fulfilment is a separate, delayed job (provider 🔒).
 */
async function maybeTicket(db: Db, flags: Flags, playerId: string, verified: boolean): Promise<string | null> {
  if (!(await flags.get<boolean>('prizes_enabled')) || !verified) return null;
  const p = await db.query<{ birth_year: number | null; phone_hash: string | null }>('SELECT birth_year, phone_hash FROM players WHERE id = $1', [playerId]);
  const row = p.rows[0];
  if (!row?.phone_hash || !row.birth_year || new Date().getFullYear() - Number(row.birth_year) < 18) return null;
  const value = Number((await flags.get<number>('prize_value_naira')) ?? 100);
  const limits = await db.query<{ today: string; week: string; month: string }>(
    `SELECT count(*) FILTER (WHERE phone_hash = $1 AND created_at > now() - interval '1 day') AS today,
            coalesce(sum(value) FILTER (WHERE phone_hash = $1 AND created_at > now() - interval '7 days'), 0) AS week,
            coalesce(sum(value) FILTER (WHERE created_at > date_trunc('month', now())), 0) AS month
       FROM prize_tickets`,
    [row.phone_hash],
  );
  const l = limits.rows[0]!;
  if (Number(l.today) >= 1) return null;
  if (Number(l.week) + value > Number((await flags.get<number>('prize_weekly_cap_naira')) ?? 500)) return null;
  if (Number(l.month) + value > Number((await flags.get<number>('prize_pool_naira')) ?? 0)) return null; // pool closed
  const code = randomBytes(8).toString('hex');
  await db.query(`INSERT INTO prize_tickets (code, player_id, phone_hash, value, status, fulfil_after) VALUES ($1, $2, $3, $4, 'pending', now() + interval '15 minutes')`, [code, playerId, row.phone_hash, value]);
  return code;
}
