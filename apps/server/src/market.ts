import type { FastifyInstance } from 'fastify';
import type { Db } from './db.ts';
import { requireAccount } from './account.ts';
import { checkText } from './moderation.ts';

/**
 * F1 gig board, in-game lane (game money only; the real-naira lane is M7 and 🔒 licensing).
 *
 * Market wallet: gigs are paid from a server-side "market ₦" balance so escrow can't be faked by a
 * client. Players move game money in and out of it from their save, capped per day and taxed 5%
 * on the way out ("no game-money trading", proposal §7).
 *
 * A gig's pay × slots is escrowed from the poster when posted. Completing a gig is gameplay: the
 * worker plays the mini-game for the skill and reports the score; ≥ 50 releases the pay, anything
 * lower returns it to the poster. Both sides can rate each other after a completed gig.
 * NPC gigs (fictional businesses) keep the board alive in quiet wards.
 */
export const SKILLS = ['driving', 'cooking', 'haggling', 'filming', 'charisma', 'hustle'] as const;
export const DISTRICTS = ['ikeja', 'agbado-ketu', 'oshodi', 'mushin', 'yaba', 'surulere', 'lagos-island', 'ikoyi', 'victoria-island', 'lekki'];
const DAILY_MOVE_CAP = 50_000;
const WITHDRAW_TAX = 0.05;
const MAX_OPEN_GIGS = 3;
const PASS_SCORE = 50;

const NPC_GIGS = [
  { npc: 'Royal Pavilion Events', title: 'Cook for a Saturday owambe', skill: 'cooking', district: 'lekki', pay: 6000, description: 'Jollof for 200 guests. Elders first. No takeaway packs.' },
  { npc: 'Baba Wale Logistics', title: 'Drive a wedding convoy', skill: 'driving', district: 'surulere', pay: 5000, description: 'Lead the convoy from the church to the hall. Horn allowed, wahala not.' },
  { npc: 'Gidi Gist FM', title: 'Film a street interview', skill: 'filming', district: 'yaba', pay: 4500, description: 'Ask ten people what they would do with 24 hours of light.' },
  { npc: 'Mama Nkem Market Council', title: 'Run the POS stand on market day', skill: 'haggling', district: 'oshodi', pay: 4000, description: 'Network will fail. Customers will not wait. Good luck.' },
  { npc: 'Eko Thunder FC', title: 'Hype the crowd at the match', skill: 'charisma', district: 'ikeja', pay: 3500, description: 'Lead the chants. Keep it clean. Ajegunle Rovers fans will be there.' },
  { npc: 'Tap-Tap POS', title: 'Hand out flyers at the motor park', skill: 'hustle', district: 'lagos-island', pay: 3000, description: '500 flyers, Obalende motor park. Do not argue with agberos.' },
];

type Gig = { id: string; poster: string | null; npc_name: string | null; title: string; description: string; skill: string; district: string; pay: number; slots: number; filled: number; status: string; expires_at: Date; poster_name: string | null };

async function walletMove(db: Db, player: string, delta: number, reason: string, ref?: string): Promise<boolean> {
  await db.query('INSERT INTO wallets (player_id) VALUES ($1) ON CONFLICT DO NOTHING', [player]);
  const r = await db.query('UPDATE wallets SET balance = balance + $2 WHERE player_id = $1 AND balance + $2 >= 0 RETURNING balance', [player, delta]);
  if (r.rows.length === 0) return false;
  await db.query('INSERT INTO wallet_ledger (player_id, delta, reason, ref) VALUES ($1, $2, $3, $4)', [player, delta, reason, ref ?? null]);
  return true;
}

/** Top up the board with NPC gigs so every skill has something open. */
export async function seedNpcGigs(db: Db): Promise<void> {
  for (const g of NPC_GIGS) {
    const open = await db.query(`SELECT 1 FROM gigs WHERE npc_name = $1 AND title = $2 AND status = 'open' AND expires_at > now()`, [g.npc, g.title]);
    if (open.rows.length) continue;
    await db.query(
      `INSERT INTO gigs (npc_name, title, description, skill, district, pay, slots, expires_at) VALUES ($1, $2, $3, $4, $5, $6, 5, now() + interval '2 days')`,
      [g.npc, g.title, g.description, g.skill, g.district, g.pay],
    );
  }
}

export function registerMarket(app: FastifyInstance, db: Db): void {
  // ---------- wallet ----------
  app.get('/api/wallet', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    const w = await db.query<{ balance: string }>('SELECT balance FROM wallets WHERE player_id = $1', [a.id]);
    const l = await db.query('SELECT delta, reason, created_at AS at FROM wallet_ledger WHERE player_id = $1 ORDER BY id DESC LIMIT 20', [a.id]);
    return { balance: Number(w.rows[0]?.balance ?? 0), ledger: l.rows };
  });

  // Move game money between the save (client wallet) and the market wallet. The client applies the
  // opposite change to its save only after this succeeds.
  app.post('/api/wallet/move', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    const amount = Number((req.body as { amount?: unknown } | null)?.amount);
    if (!Number.isInteger(amount) || amount === 0 || Math.abs(amount) > DAILY_MOVE_CAP) return reply.code(400).send({ error: 'bad_amount' });
    return db.tx(async (t) => {
      await t.query('INSERT INTO wallets (player_id) VALUES ($1) ON CONFLICT DO NOTHING', [a.id]);
      await t.query(`UPDATE wallets SET moved_today = 0, moved_day = CURRENT_DATE WHERE player_id = $1 AND moved_day <> CURRENT_DATE`, [a.id]);
      const cap = await t.query<{ moved_today: string }>('SELECT moved_today FROM wallets WHERE player_id = $1 FOR UPDATE', [a.id]);
      if (Number(cap.rows[0]!.moved_today) + Math.abs(amount) > DAILY_MOVE_CAP) return reply.code(429).send({ error: 'daily_cap', cap: DAILY_MOVE_CAP });
      if (amount > 0) {
        await walletMove(t, a.id, amount, 'Deposit from pocket');
        await t.query('UPDATE wallets SET moved_today = moved_today + $2 WHERE player_id = $1', [a.id, amount]);
        return { ok: true, toSave: -amount };
      }
      const out = -amount;
      if (!(await walletMove(t, a.id, -out, 'Withdraw to pocket'))) return reply.code(400).send({ error: 'insufficient' });
      await t.query('UPDATE wallets SET moved_today = moved_today + $2 WHERE player_id = $1', [a.id, out]);
      return { ok: true, toSave: Math.floor(out * (1 - WITHDRAW_TAX)), tax: out - Math.floor(out * (1 - WITHDRAW_TAX)) };
    });
  });

  // ---------- gigs ----------
  app.get('/api/gigs', async (req, reply) => {
    reply.header('cache-control', 'no-store');
    await seedNpcGigs(db);
    const q = req.query as { skill?: string; district?: string; q?: string };
    const params: unknown[] = [];
    let where = `g.status = 'open' AND g.expires_at > now() AND g.filled < g.slots`;
    if (q.skill && (SKILLS as readonly string[]).includes(q.skill)) { params.push(q.skill); where += ` AND g.skill = $${params.length}`; }
    if (q.district && DISTRICTS.includes(q.district)) { params.push(q.district); where += ` AND g.district = $${params.length}`; }
    if (q.q && typeof q.q === 'string' && q.q.length <= 40) { params.push(`%${q.q}%`); where += ` AND g.title ILIKE $${params.length}`; }
    const r = await db.query<Gig & { rating: string | null }>(
      `SELECT g.*, p.name AS poster_name,
              (SELECT round(avg(stars)::numeric, 1) FROM ratings WHERE ratee = g.poster) AS rating
         FROM gigs g LEFT JOIN players p ON p.id = g.poster WHERE ${where} ORDER BY g.created_at DESC LIMIT 50`,
      params,
    );
    return { gigs: r.rows.map((g) => ({ id: Number(g.id), title: g.title, description: g.description, skill: g.skill, district: g.district, pay: Number(g.pay), slots: Number(g.slots), filled: Number(g.filled), by: g.npc_name ?? g.poster_name, npc: g.poster === null, rating: g.rating === null ? null : Number(g.rating) })) };
  });

  app.post('/api/gigs', async (req, reply) => {
    const a = await requireAccount(db, req, reply, { verified: true });
    if (!a) return;
    const b = (req.body ?? {}) as Record<string, unknown>;
    const title = checkText(b.title, { verified: true, max: 60 });
    const desc = checkText(b.description, { verified: true, max: 400 });
    if (!title.ok) return reply.code(400).send({ error: `title_${title.reason}` });
    if (!desc.ok) return reply.code(400).send({ error: `description_${desc.reason}` });
    const skill = String(b.skill);
    const district = String(b.district);
    const pay = Number(b.pay);
    const slots = Number(b.slots ?? 1);
    if (!(SKILLS as readonly string[]).includes(skill) || !DISTRICTS.includes(district)) return reply.code(400).send({ error: 'bad_category' });
    if (!Number.isInteger(pay) || pay < 500 || pay > 20_000 || !Number.isInteger(slots) || slots < 1 || slots > 5) return reply.code(400).send({ error: 'bad_pay' });
    // New-account limits and anti-spam.
    if (a.ageHours < 24 && a.level < 3) return reply.code(403).send({ error: 'too_new' });
    const mine = await db.query<{ n: string; dup: string }>(
      `SELECT count(*) FILTER (WHERE status = 'open' AND expires_at > now()) AS n,
              count(*) FILTER (WHERE lower(title) = lower($2) AND created_at > now() - interval '24 hours') AS dup
         FROM gigs WHERE poster = $1`,
      [a.id, title.text],
    );
    if (Number(mine.rows[0]!.n) >= MAX_OPEN_GIGS) return reply.code(429).send({ error: 'too_many_open' });
    if (Number(mine.rows[0]!.dup) > 0) return reply.code(409).send({ error: 'duplicate' });
    return db.tx(async (t) => {
      const fee = Math.ceil(pay * slots * 0.02); // posting fee in game money filters spam
      if (!(await walletMove(t, a.id, -(pay * slots + fee), 'Gig escrow + 2% posting fee'))) return reply.code(402).send({ error: 'insufficient', need: pay * slots + fee });
      const r = await t.query<{ id: string }>(
        `INSERT INTO gigs (poster, title, description, skill, district, pay, slots, expires_at) VALUES ($1, $2, $3, $4, $5, $6, $7, now() + interval '3 days') RETURNING id`,
        [a.id, title.text, desc.text, skill, district, pay, slots],
      );
      return { ok: true, id: Number(r.rows[0]!.id), escrowed: pay * slots, fee };
    });
  });

  // Apply = take a slot (NPC gigs and player gigs alike; the gameplay is the interview).
  app.post('/api/gigs/:id/take', async (req, reply) => {
    const a = await requireAccount(db, req, reply, { verified: true });
    if (!a) return;
    const id = Number((req.params as { id: string }).id);
    return db.tx(async (t) => {
      const g = await t.query<Gig>(`SELECT * FROM gigs WHERE id = $1 FOR UPDATE`, [id]);
      const gig = g.rows[0];
      if (!gig || gig.status !== 'open' || new Date(gig.expires_at) < new Date() || Number(gig.filled) >= Number(gig.slots)) return reply.code(404).send({ error: 'gone' });
      if (gig.poster === a.id) return reply.code(400).send({ error: 'own_gig' });
      const active = await t.query<{ n: string }>(`SELECT count(*) AS n FROM gig_assignments WHERE worker = $1 AND status = 'accepted'`, [a.id]);
      if (Number(active.rows[0]!.n) >= 2) return reply.code(429).send({ error: 'finish_your_gigs_first' });
      const ins = await t.query<{ id: string }>(`INSERT INTO gig_assignments (gig_id, worker, status) VALUES ($1, $2, 'accepted') ON CONFLICT (gig_id, worker) DO NOTHING RETURNING id`, [id, a.id]);
      if (ins.rows.length === 0) return reply.code(409).send({ error: 'already_taken' });
      await t.query('UPDATE gigs SET filled = filled + 1 WHERE id = $1', [id]);
      return { ok: true, assignment: Number(ins.rows[0]!.id), skill: gig.skill, pay: Number(gig.pay) };
    });
  });

  // Finish: the worker reports the mini-game score. Pay releases from escrow (or the NPC) at ≥ 50.
  app.post('/api/gigs/:id/finish', async (req, reply) => {
    const a = await requireAccount(db, req, reply, { verified: true });
    if (!a) return;
    const id = Number((req.params as { id: string }).id);
    const score = Number((req.body as { score?: unknown } | null)?.score);
    if (!Number.isInteger(score) || score < 0 || score > 100) return reply.code(400).send({ error: 'bad_score' });
    return db.tx(async (t) => {
      const r = await t.query<{ aid: string; poster: string | null; pay: number; title: string; created_at: Date }>(
        `SELECT ga.id AS aid, g.poster, g.pay, g.title, ga.created_at FROM gig_assignments ga JOIN gigs g ON g.id = ga.gig_id
          WHERE ga.gig_id = $1 AND ga.worker = $2 AND ga.status = 'accepted' FOR UPDATE OF ga`,
        [id, a.id],
      );
      const row = r.rows[0];
      if (!row) return reply.code(404).send({ error: 'no_assignment' });
      // A gig takes at least a minute of play: instant "finishes" are not believed.
      if (Date.now() - new Date(row.created_at).getTime() < Number(process.env.GIG_MIN_SECONDS ?? 60) * 1000) return reply.code(425).send({ error: 'too_fast' });
      const passed = score >= PASS_SCORE;
      await t.query(`UPDATE gig_assignments SET status = $2, score = $3, completed_at = now() WHERE id = $1`, [row.aid, passed ? 'done' : 'failed', score]);
      if (passed) {
        await walletMove(t, a.id, Number(row.pay), `Gig: ${row.title}`, `gig:${id}`);
      } else if (row.poster) {
        await walletMove(t, row.poster, Number(row.pay), `Gig refund: ${row.title}`, `gig:${id}`);
      }
      return { ok: true, passed, paid: passed ? Number(row.pay) : 0 };
    });
  });

  app.get('/api/gigs/mine', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    const posted = await db.query(`SELECT id, title, skill, district, pay, slots, filled, status FROM gigs WHERE poster = $1 ORDER BY id DESC LIMIT 20`, [a.id]);
    const working = await db.query(
      `SELECT g.id, g.title, g.skill, g.district, g.pay, ga.status, ga.score, coalesce(g.npc_name, p.name) AS by
         FROM gig_assignments ga JOIN gigs g ON g.id = ga.gig_id LEFT JOIN players p ON p.id = g.poster
        WHERE ga.worker = $1 ORDER BY ga.id DESC LIMIT 20`,
      [a.id],
    );
    return { posted: posted.rows, working: working.rows };
  });

  // Close an open gig: unfilled slots are refunded.
  app.post('/api/gigs/:id/close', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    const id = Number((req.params as { id: string }).id);
    return db.tx(async (t) => {
      const g = await t.query<Gig>(`SELECT * FROM gigs WHERE id = $1 AND poster = $2 AND status = 'open' FOR UPDATE`, [id, a.id]);
      if (!g.rows[0]) return reply.code(404).send({ error: 'not_yours' });
      const refund = (Number(g.rows[0]!.slots) - Number(g.rows[0]!.filled)) * Number(g.rows[0]!.pay);
      await t.query(`UPDATE gigs SET status = 'closed' WHERE id = $1`, [id]);
      if (refund > 0) await walletMove(t, a.id, refund, `Gig closed: ${g.rows[0]!.title}`, `gig:${id}`);
      return { ok: true, refunded: refund };
    });
  });

  // Ratings only after a completed gig, between its poster and worker.
  app.post('/api/gigs/:id/rate', async (req, reply) => {
    const a = await requireAccount(db, req, reply, { verified: true });
    if (!a) return;
    const id = Number((req.params as { id: string }).id);
    const b = (req.body ?? {}) as { pid?: string; stars?: unknown; text?: unknown };
    const stars = Number(b.stars);
    if (!Number.isInteger(stars) || stars < 1 || stars > 5) return reply.code(400).send({ error: 'bad_stars' });
    const text = b.text ? checkText(b.text, { verified: true, max: 200 }) : { ok: true as const, text: '' };
    if (!text.ok) return reply.code(400).send({ error: `text_${text.reason}` });
    const pair = await db.query<{ poster: string; worker: string }>(
      `SELECT g.poster, ga.worker FROM gigs g JOIN gig_assignments ga ON ga.gig_id = g.id
        WHERE g.id = $1 AND ga.status = 'done' AND g.poster IS NOT NULL AND ((g.poster = $2 AND ga.worker = $3) OR (ga.worker = $2 AND g.poster = $3))`,
      [id, a.id, String(b.pid ?? '')],
    );
    if (!pair.rows[0]) return reply.code(403).send({ error: 'not_eligible' });
    await db.query('INSERT INTO ratings (gig_id, rater, ratee, stars, text) VALUES ($1, $2, $3, $4, $5) ON CONFLICT (gig_id, rater, ratee) DO UPDATE SET stars = EXCLUDED.stars, text = EXCLUDED.text', [id, a.id, b.pid, stars, text.text]);
    return { ok: true };
  });
}
