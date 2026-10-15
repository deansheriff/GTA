import { randomBytes } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import type { Db } from './db.ts';
import { requireAccount } from './account.ts';
import { checkText } from './moderation.ts';
import { walletMove, DISTRICTS } from './market.ts';
import { LANDMARKS, ROUTES } from './game_data.ts';

/**
 * M11 online street life. Everything here is checked against the server's own positions
 * (rooms.ts) and game data (game_data.ts); clients only ask.
 *  - Races and "who get road" duels: finish order comes from server positions; warping is a DQ.
 *  - Co-op jobs: one drives, one rides along (films or works the passengers); the server checks
 *    they really travelled together before paying both (market ₦).
 *  - Ranked street boxing: Elo ratings and weekly champions on top of the clash fight rules.
 *  - Crews hold routes by completing danfo runs on them (server-checked arrivals).
 *  - The trading market: district prices move with what players buy and sell.
 *  - The Lagos Gist feed: posts built from fixed templates (players can't post free text).
 */

export interface Where { x: number; y: number; m: 0 | 1; district: string; name: string }
export interface StreetPorts {
  where(pid: string): Where | null;
  send(pid: string, msg: unknown): void;
  /** Other players in the same room within `radius` px. */
  nearby(pid: string, radius: number): string[];
}

const dist = (a: { x: number; y: number }, b: { x: number; y: number }) => Math.hypot(a.x - b.x, a.y - b.y);

export function weekKey(d = new Date()): string {
  const t = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const day = t.getUTCDay() || 7;
  t.setUTCDate(t.getUTCDate() + 4 - day);
  const y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
  const w = Math.ceil(((t.getTime() - y0.getTime()) / 86400000 + 1) / 7);
  return `${t.getUTCFullYear()}-W${String(w).padStart(2, '0')}`;
}

// ---------- races ----------

const RACE_LOBBY_MS = 15_000;
const RACE_GO_MS = 3_000;
const RACE_MAX_MS = 4 * 60_000;
const FINISH_PX = 260;

interface Racer { name: string; finished?: number; dq?: string }
interface Race {
  id: string;
  host: string;
  to: string;
  finish: { x: number; y: number };
  duel: string | null;
  racers: Map<string, Racer>;
  invited: Set<string>;
  stage: 'lobby' | 'go' | 'run' | 'done';
  goAt: number;
  timer?: NodeJS.Timeout;
}

// ---------- co-op ----------

const COOP_MAX_MS = 8 * 60_000;
interface Coop {
  id: string;
  driver: string;
  partner: string;
  role: 'film' | 'conductor';
  route: (typeof ROUTES)[number];
  dest: { x: number; y: number };
  stage: 'invite' | 'run' | 'done';
  samples: number;
  together: number;
  score: number;
  timer?: NodeJS.Timeout;
}

export class StreetRealtime {
  private db: Db;
  private ports: StreetPorts;
  private races = new Map<string, Race>();
  private coops = new Map<string, Coop>();
  private boxInvites = new Map<string, { a: string; b: string; at: number }>();
  /** Set by realtime.ts: starts a ranked bout through the clash fight rules. */
  startBout: (a: string, b: string) => Promise<string> = async () => 'unavailable';

  constructor(db: Db, ports: StreetPorts) {
    this.db = db;
    this.ports = ports;
  }

  /** Handles a realtime message; returns true when it was one of ours. */
  async handle(pid: string, msg: Record<string, unknown>, now = Date.now()): Promise<boolean> {
    switch (msg.t) {
      case 'race_open': this.raceOpen(pid, String(msg.to ?? ''), typeof msg.duel === 'string' ? msg.duel : null, now); return true;
      case 'race_join': this.raceJoin(pid, String(msg.id ?? ''), now); return true;
      case 'coop_invite': this.coopInvite(pid, String(msg.pid ?? ''), msg.role === 'conductor' ? 'conductor' : 'film'); return true;
      case 'coop_accept': this.coopAccept(pid, String(msg.id ?? ''), now); return true;
      case 'coop_task': this.coopTask(pid, String(msg.id ?? ''), Number(msg.score)); return true;
      case 'box_challenge': this.boxChallenge(pid, String(msg.pid ?? ''), now); return true;
      case 'box_accept': await this.boxAccept(pid, String(msg.id ?? ''), now); return true;
    }
    return false;
  }

  private err(pid: string, code: string) {
    this.ports.send(pid, { t: 'err', code });
  }

  /** Called on every accepted move (rooms.ts already checked the speed). */
  moved(pid: string, x: number, y: number, warp: boolean, now = Date.now()): void {
    for (const r of this.races.values()) {
      const me = r.racers.get(pid);
      if (!me || r.stage !== 'run' || me.finished || me.dq) continue;
      if (warp) { me.dq = 'warp'; continue; }
      if (dist({ x, y }, r.finish) <= FINISH_PX) {
        me.finished = now - r.goAt;
        if ([...r.racers.values()].every((m) => m.finished || m.dq)) void this.raceEnd(r);
      }
    }
    for (const c of this.coops.values()) {
      if (c.stage !== 'run' || pid !== c.driver) continue;
      const p = this.ports.where(c.partner);
      c.samples++;
      if (p && dist(p, { x, y }) <= 320) c.together++;
      if (dist({ x, y }, c.dest) <= FINISH_PX && c.samples >= 15) void this.coopEnd(c, 'arrived');
    }
  }

  left(pid: string): void {
    for (const r of this.races.values()) {
      const me = r.racers.get(pid);
      if (me && !me.finished) me.dq = 'left';
      if (r.stage === 'run' && [...r.racers.values()].every((m) => m.finished || m.dq)) void this.raceEnd(r);
    }
    for (const c of this.coops.values()) if (c.stage !== 'done' && (c.driver === pid || c.partner === pid)) void this.coopEnd(c, 'left');
  }

  // ----- races -----

  raceOpen(host: string, to: string, duel: string | null, now: number): void {
    const me = this.ports.where(host);
    const lm = LANDMARKS[to];
    if (!me || me.m !== 1) return this.err(host, 'race_need_vehicle');
    if (!lm) return this.err(host, 'race_bad_finish');
    const d = dist(me, lm);
    if (d < 1500 || d > 9000) return this.err(host, 'race_finish_distance');
    for (const r of this.races.values()) if (r.stage !== 'done' && r.racers.has(host)) return this.err(host, 'race_busy');
    const r: Race = { id: randomBytes(6).toString('hex'), host, to, finish: { x: lm.x, y: lm.y }, duel, racers: new Map([[host, { name: me.name }]]), invited: new Set(), stage: 'lobby', goAt: 0 };
    let targets: string[];
    if (duel) {
      const other = this.ports.where(duel);
      if (!other || other.m !== 1 || dist(other, me) > 600) return this.err(host, 'race_duel_not_near');
      targets = [duel];
    } else {
      targets = this.ports.nearby(host, 1500).filter((p) => this.ports.where(p)?.m === 1);
    }
    targets.forEach((t) => r.invited.add(t));
    this.races.set(r.id, r);
    const invite = { t: 'race_invite', id: r.id, host: me.name, to: lm.name, duel: !!duel, ms: duel ? 10_000 : RACE_LOBBY_MS };
    for (const t of targets) this.ports.send(t, invite);
    this.ports.send(host, { t: 'race_open', id: r.id, to: lm.name, invited: targets.length, ms: invite.ms });
    r.timer = setTimeout(() => this.raceGo(r), invite.ms);
  }

  raceJoin(pid: string, id: string, now: number): void {
    const r = this.races.get(id);
    const me = this.ports.where(pid);
    const host = this.ports.where(r?.host ?? '');
    if (!r || r.stage !== 'lobby' || !r.invited.has(pid)) return this.err(pid, 'race_gone');
    if (!me || me.m !== 1 || !host || dist(me, host) > 1500) return this.err(pid, 'race_need_vehicle');
    r.racers.set(pid, { name: me.name });
    for (const p of r.racers.keys()) this.ports.send(p, { t: 'race_joined', id, name: me.name, count: r.racers.size });
    // A duel starts as soon as the challenged driver accepts.
    if (r.duel && r.racers.size === 2) {
      clearTimeout(r.timer);
      this.raceGo(r);
    }
  }

  private raceGo(r: Race): void {
    if (r.stage !== 'lobby') return;
    if (r.racers.size < 2) {
      r.stage = 'done';
      this.races.delete(r.id);
      this.ports.send(r.host, { t: 'race_end', id: r.id, cancelled: true });
      return;
    }
    // Everyone has to be lined up near the host at the start.
    const host = this.ports.where(r.host);
    for (const [pid, m] of r.racers) {
      const w = this.ports.where(pid);
      if (!w || !host || dist(w, host) > 900 || w.m !== 1) m.dq = 'not_at_start';
    }
    r.stage = 'go';
    r.goAt = Date.now() + RACE_GO_MS;
    for (const p of r.racers.keys()) this.ports.send(p, { t: 'race_go', id: r.id, to: LANDMARKS[r.to]!.name, finish: r.finish, in: RACE_GO_MS, dq: r.racers.get(p)!.dq ?? null });
    setTimeout(() => {
      r.stage = 'run';
      r.timer = setTimeout(() => void this.raceEnd(r), RACE_MAX_MS);
    }, RACE_GO_MS);
  }

  private async raceEnd(r: Race): Promise<void> {
    if (r.stage === 'done') return;
    clearTimeout(r.timer);
    r.stage = 'done';
    this.races.delete(r.id);
    const order = [...r.racers.entries()]
      .filter(([, m]) => m.finished !== undefined && !m.dq)
      .sort((a, b) => a[1].finished! - b[1].finished!);
    const results = order.map(([pid, m], i) => ({ pid, name: m.name, place: i + 1, ms: m.finished }));
    for (const [pid, m] of r.racers) if (!order.find(([p]) => p === pid)) results.push({ pid, name: m.name, place: 0, ms: undefined });
    for (const res of results) {
      await this.db.query('INSERT INTO race_results (race, player_id, place, ms, duel) VALUES ($1, $2, $3, $4, $5)', [r.id, res.pid, res.place, res.ms ?? null, !!r.duel]).catch(() => {});
    }
    for (const p of r.racers.keys()) this.ports.send(p, { t: 'race_end', id: r.id, to: LANDMARKS[r.to]!.name, results });
  }

  // ----- co-op -----

  coopInvite(driver: string, partner: string, role: 'film' | 'conductor'): void {
    const a = this.ports.where(driver);
    const b = this.ports.where(partner);
    if (!a || a.m !== 1) return this.err(driver, 'coop_need_vehicle');
    if (!b || dist(a, b) > 320) return this.err(driver, 'coop_not_near');
    const route = ROUTES[Math.floor(Math.random() * ROUTES.length)]!;
    const lm = LANDMARKS[route.to]!;
    const c: Coop = { id: randomBytes(6).toString('hex'), driver, partner, role, route, dest: { x: lm.x, y: lm.y }, stage: 'invite', samples: 0, together: 0, score: 0 };
    this.coops.set(c.id, c);
    this.ports.send(partner, { t: 'coop_invite', id: c.id, name: a.name, role, route: route.name });
    c.timer = setTimeout(() => { if (c.stage === 'invite') { this.coops.delete(c.id); this.ports.send(driver, { t: 'coop_end', id: c.id, outcome: 'declined' }); } }, 20_000);
  }

  coopAccept(partner: string, id: string, _now: number): void {
    const c = this.coops.get(id);
    if (!c || c.partner !== partner || c.stage !== 'invite') return this.err(partner, 'coop_gone');
    clearTimeout(c.timer);
    c.stage = 'run';
    const start = { t: 'coop_start', id, route: c.route.name, to: c.dest, role: c.role, driver: this.ports.where(c.driver)?.name ?? 'Driver', partner: this.ports.where(c.partner)?.name ?? 'Partner' };
    this.ports.send(c.driver, { ...start, you: 'driver' });
    this.ports.send(c.partner, { ...start, you: c.role, driver_pid: c.driver });
    c.timer = setTimeout(() => void this.coopEnd(c, 'timeout'), COOP_MAX_MS);
  }

  coopTask(pid: string, id: string, score: number): void {
    const c = this.coops.get(id);
    if (!c || c.partner !== pid || c.stage !== 'run' || !Number.isFinite(score)) return;
    c.score = Math.max(0, Math.min(100, Math.round(score)));
  }

  private async coopEnd(c: Coop, outcome: string): Promise<void> {
    if (c.stage === 'done') return;
    clearTimeout(c.timer);
    c.stage = 'done';
    this.coops.delete(c.id);
    const together = c.samples ? c.together / c.samples : 0;
    let paid = { driver: 0, partner: 0 };
    if (outcome === 'arrived' && together >= 0.7) {
      const base = c.route.fare * 14;
      paid = { driver: Math.round(base * 0.6), partner: Math.round(base * 0.4 * (0.5 + c.score / 200)) };
      await walletMove(this.db, c.driver, paid.driver, `Co-op job: ${c.route.name}`).catch(() => false);
      await walletMove(this.db, c.partner, paid.partner, `Co-op job: ${c.route.name}`).catch(() => false);
    } else if (outcome === 'arrived') {
      outcome = 'apart';
    }
    await this.db.query('INSERT INTO coop_jobs (id, driver, partner, route, role, outcome, together, score, paid) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)',
      [c.id, c.driver, c.partner, c.route.id, c.role, outcome, together, c.score, paid.driver + paid.partner]).catch(() => {});
    const end = { t: 'coop_end', id: c.id, outcome, together: Number(together.toFixed(2)), paid };
    this.ports.send(c.driver, end);
    this.ports.send(c.partner, end);
  }

  // ----- ranked boxing -----

  boxChallenge(a: string, b: string, now: number): void {
    const pa = this.ports.where(a);
    const pb = this.ports.where(b);
    if (!pa || !pb || pa.m !== 0 || pb.m !== 0) return this.err(a, 'box_on_foot');
    if (dist(pa, pb) > 300) return this.err(a, 'box_not_near');
    const id = randomBytes(6).toString('hex');
    this.boxInvites.set(id, { a, b, at: now });
    void this.rating(a).then((r) => this.ports.send(b, { t: 'box_invite', id, name: pa.name, rating: r }));
  }

  async boxAccept(b: string, id: string, now: number): Promise<void> {
    const inv = this.boxInvites.get(id);
    this.boxInvites.delete(id);
    if (!inv || inv.b !== b || now - inv.at > 20_000) return this.err(b, 'box_gone');
    const r = await this.startBout(inv.a, b);
    if (r !== 'ok') {
      this.err(inv.a, `box_${r}`);
      this.err(b, `box_${r}`);
    }
  }

  async rating(pid: string): Promise<number> {
    const r = await this.db.query<{ rating: number }>('SELECT rating FROM box_ratings WHERE player_id = $1', [pid]);
    return r.rows[0] ? Number(r.rows[0].rating) : 1000;
  }

  /** A ranked bout finished (clash.ts): Elo update and this week's wins. */
  async boutResult(a: string, b: string, winner: string | null): Promise<{ a: number; b: number }> {
    const ra = await this.rating(a);
    const rb = await this.rating(b);
    const ea = 1 / (1 + 10 ** ((rb - ra) / 400));
    const sa = winner === null ? 0.5 : winner === a ? 1 : 0;
    const na = Math.round(ra + 32 * (sa - ea));
    const nb = Math.round(rb + 32 * ((1 - sa) - (1 - ea)));
    for (const [pid, rating, won] of [[a, na, sa === 1], [b, nb, sa === 0]] as const) {
      await this.db.query(
        `INSERT INTO box_ratings (player_id, rating, wins, losses) VALUES ($1, $2, $3, $4)
         ON CONFLICT (player_id) DO UPDATE SET rating = $2, wins = box_ratings.wins + $3, losses = box_ratings.losses + $4`,
        [pid, rating, won ? 1 : 0, won || winner === null ? 0 : 1],
      );
      if (won) {
        await this.db.query(
          `INSERT INTO box_week_wins (week, player_id, wins) VALUES ($1, $2, 1)
           ON CONFLICT (week, player_id) DO UPDATE SET wins = box_week_wins.wins + 1`, [weekKey(), pid]);
      }
    }
    return { a: na, b: nb };
  }
}

// ---------- the trading market ----------

export const GOODS: Record<string, { name: string; base: number }> = {
  tomatoes: { name: 'Basket of tomatoes', base: 6000 },
  pepper: { name: 'Bag of tatashe pepper', base: 4500 },
  rice: { name: 'Bag of rice', base: 38000 },
  ankara: { name: 'Bundle of ankara fabric', base: 15000 },
  'palm-oil': { name: 'Keg of palm oil', base: 21000 },
  'phone-cases': { name: 'Box of phone cases', base: 9000 },
};
/** Cheap where it's sold wholesale, dear where the money lives. */
export const DISTRICT_K: Record<string, number> = {
  mushin: 0.78, oshodi: 0.8, 'agbado-ketu': 0.85, surulere: 0.92, yaba: 0.97, ikeja: 1.0,
  'lagos-island': 1.05, ikoyi: 1.25, 'victoria-island': 1.3, lekki: 1.35,
};
const MARKET_LEVY = 0.03;

async function priceOf(db: Db, good: string, district: string): Promise<number> {
  const target = GOODS[good]!.base * (DISTRICT_K[district] ?? 1);
  const r = await db.query<{ price: number; hours: number }>(
    `SELECT price, EXTRACT(EPOCH FROM (now() - updated_at)) / 3600 AS hours FROM market_prices WHERE good = $1 AND district = $2`, [good, district]);
  if (!r.rows[0]) return target;
  // Prices drift back toward normal: 4% of the gap closes each hour.
  const p = Number(r.rows[0].price);
  return target + (p - target) * 0.96 ** Number(r.rows[0].hours);
}

async function setPrice(db: Db, good: string, district: string, price: number): Promise<void> {
  await db.query(
    `INSERT INTO market_prices (good, district, price, updated_at) VALUES ($1, $2, $3, now())
     ON CONFLICT (good, district) DO UPDATE SET price = $3, updated_at = now()`, [good, district, price]);
}

// ---------- the Lagos Gist feed ----------

const GIST: Record<string, string> = {
  fight_win: '{name} won a street fight in {district}!',
  fight_loss: '{name} lost a street fight in {district}. E pain am.',
  race_win: '{name} won a danfo race to {detail}!',
  award: '{name} unlocked "{detail}".',
  owambe: '{name} crashed an owambe in {district} and ate the jollof!',
  fleet: '{name} just bought another danfo.',
  home: '{name} moved into a new house.',
  impound: "{name}'s bus was towed in {district}. Wahala!",
  hero: '{name} caught a thief on a danfo in {district}!',
  photo: '{name} posted a photo from {district}.',
  event: "{name} handled today's Lagos Wahala in {district}.",
  taskforce: '{name} fought off the Task Force in {district}!',
  zoom: '{name} zoomed past a checkpoint in {district}!',
  boxing: '{name} won a ranked boxing bout in {district}!',
};

export function registerStreetOnline(app: FastifyInstance, db: Db, ports: () => StreetPorts): void {
  // ----- crews and routes -----
  app.get('/api/crews', async (req, reply) => {
    if (!(await requireAccount(db, req, reply))) return;
    const r = await db.query(
      `SELECT c.id, c.name, c.tag, c.colour, (SELECT count(*) FROM crew_members m WHERE m.crew_id = c.id)::int AS members
       FROM crews c ORDER BY members DESC, c.id LIMIT 30`);
    return { crews: r.rows };
  });

  app.get('/api/crews/mine', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    const r = await db.query(
      `SELECT c.id, c.name, c.tag, c.colour, m.role FROM crew_members m JOIN crews c ON c.id = m.crew_id WHERE m.player_id = $1`, [a.id]);
    if (!r.rows[0]) return { crew: null };
    const members = await db.query(
      `SELECT p.name AS name, m.role FROM crew_members m JOIN players p ON p.id = m.player_id WHERE m.crew_id = $1 ORDER BY m.joined_at LIMIT 30`, [r.rows[0].id]);
    return { crew: { ...r.rows[0], members: members.rows } };
  });

  app.post('/api/crews', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    const b = (req.body ?? {}) as Record<string, unknown>;
    const name = checkText(b.name, { max: 24 });
    const tag = String(b.tag ?? '').toUpperCase();
    const colour = /^#[0-9a-fA-F]{6}$/.test(String(b.colour ?? '')) ? String(b.colour) : '#e0a91c';
    if (!name.ok) return reply.code(400).send({ error: `name_${name.reason}` });
    if (!/^[A-Z0-9]{2,4}$/.test(tag)) return reply.code(400).send({ error: 'bad_tag' });
    if ((await db.query('SELECT 1 FROM crew_members WHERE player_id = $1', [a.id])).rows.length) return reply.code(409).send({ error: 'already_in_crew' });
    if (!(await walletMove(db, a.id, -5000, 'Crew registration'))) return reply.code(402).send({ error: 'insufficient_funds' });
    try {
      const c = await db.query<{ id: string }>('INSERT INTO crews (name, tag, colour, owner) VALUES ($1, $2, $3, $4) RETURNING id', [name.text, tag, colour, a.id]);
      await db.query(`INSERT INTO crew_members (player_id, crew_id, role) VALUES ($1, $2, 'boss')`, [a.id, c.rows[0]!.id]);
      return { id: Number(c.rows[0]!.id), tag };
    } catch {
      await walletMove(db, a.id, 5000, 'Crew registration refund');
      return reply.code(409).send({ error: 'name_or_tag_taken' });
    }
  });

  app.post('/api/crews/:id/join', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    const id = Number((req.params as { id: string }).id);
    if ((await db.query('SELECT 1 FROM crew_members WHERE player_id = $1', [a.id])).rows.length) return reply.code(409).send({ error: 'already_in_crew' });
    const c = await db.query<{ n: number }>('SELECT (SELECT count(*) FROM crew_members WHERE crew_id = $1)::int AS n FROM crews WHERE id = $1', [id]);
    if (!c.rows[0]) return reply.code(404).send({ error: 'not_found' });
    if (Number(c.rows[0].n) >= 20) return reply.code(409).send({ error: 'crew_full' });
    await db.query('INSERT INTO crew_members (player_id, crew_id) VALUES ($1, $2)', [a.id, id]);
    return { ok: true };
  });

  app.post('/api/crews/leave', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    await db.query('DELETE FROM crew_members WHERE player_id = $1', [a.id]);
    return { ok: true };
  });

  async function standings(week: string) {
    const r = await db.query<{ route: string; crew_id: string; tag: string; name: string; colour: string; points: number }>(
      `SELECT rp.route, rp.crew_id, c.tag, c.name, c.colour, rp.points FROM route_points rp JOIN crews c ON c.id = rp.crew_id
       WHERE rp.week = $1 ORDER BY rp.route, rp.points DESC`, [week]);
    return ROUTES.map((route) => {
      const rows = r.rows.filter((x) => x.route === route.id).slice(0, 3).map((x) => ({ crew: Number(x.crew_id), tag: x.tag, name: x.name, colour: x.colour, points: Number(x.points) }));
      return { id: route.id, name: route.name, holder: rows[0] ?? null, top: rows };
    });
  }

  app.get('/api/routes', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    const mine = await db.query<{ crew_id: string }>('SELECT crew_id FROM crew_members WHERE player_id = $1', [a.id]);
    const crew = mine.rows[0] ? Number(mine.rows[0].crew_id) : null;
    const routes = await standings(weekKey());
    return { week: weekKey(), routes, held: routes.filter((r) => crew !== null && r.holder?.crew === crew).map((r) => r.id) };
  });

  /** A crew member finished a danfo run: checked against the server's own position. */
  app.post('/api/crews/route-run', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    const route = ROUTES.find((r) => r.id === String(((req.body ?? {}) as Record<string, unknown>).route ?? ''));
    if (!route) return reply.code(400).send({ error: 'bad_route' });
    const mine = await db.query<{ crew_id: string }>('SELECT crew_id FROM crew_members WHERE player_id = $1', [a.id]);
    if (!mine.rows[0]) return reply.code(409).send({ error: 'no_crew' });
    const w = ports().where(a.id);
    const dest = LANDMARKS[route.to]!;
    if (!w || w.m !== 1 || dist(w, dest) > 450) return reply.code(409).send({ error: 'not_at_destination' });
    const last = await db.query<{ s: number }>(`SELECT EXTRACT(EPOCH FROM (now() - max(created_at))) AS s FROM route_runs WHERE player_id = $1`, [a.id]);
    if (last.rows[0]?.s !== null && last.rows[0]?.s !== undefined && Number(last.rows[0].s) < 120) return reply.code(429).send({ error: 'too_soon' });
    await db.query('INSERT INTO route_runs (player_id, route) VALUES ($1, $2)', [a.id, route.id]);
    const crew = Number(mine.rows[0].crew_id);
    await db.query(
      `INSERT INTO route_points (crew_id, route, week, points) VALUES ($1, $2, $3, 1)
       ON CONFLICT (crew_id, route, week) DO UPDATE SET points = route_points.points + 1`, [crew, route.id, weekKey()]);
    const s = (await standings(weekKey())).find((r) => r.id === route.id)!;
    return { holder: s.holder, yours: s.holder?.crew === crew };
  });

  // ----- ranked boxing -----
  app.get('/api/boxing', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    // Settle last week's champion the first time anyone looks this week.
    const last = weekKey(new Date(Date.now() - 7 * 86400000));
    if (!(await db.query('SELECT 1 FROM box_champions WHERE week = $1', [last])).rows.length) {
      const top = await db.query<{ player_id: string; name: string; wins: number }>(
        `SELECT w.player_id, p.name AS name, w.wins FROM box_week_wins w JOIN players p ON p.id = w.player_id
         WHERE w.week = $1 ORDER BY w.wins DESC LIMIT 1`, [last]);
      if (top.rows[0]) {
        await db.query('INSERT INTO box_champions (week, player_id, name, wins) VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING',
          [last, top.rows[0].player_id, top.rows[0].name, top.rows[0].wins]);
      }
    }
    const top = await db.query(
      `SELECT p.name AS name, b.rating, b.wins, b.losses FROM box_ratings b JOIN players p ON p.id = b.player_id ORDER BY b.rating DESC LIMIT 20`);
    const champs = await db.query('SELECT week, name, wins FROM box_champions ORDER BY week DESC LIMIT 8');
    const week = await db.query(
      `SELECT p.name AS name, w.wins FROM box_week_wins w JOIN players p ON p.id = w.player_id WHERE w.week = $1 ORDER BY w.wins DESC LIMIT 5`, [weekKey()]);
    const me = await db.query('SELECT rating, wins, losses FROM box_ratings WHERE player_id = $1', [a.id]);
    return { top: top.rows, champions: champs.rows, thisWeek: week.rows, me: me.rows[0] ?? { rating: 1000, wins: 0, losses: 0 } };
  });

  // ----- trading -----
  app.get('/api/trade', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    const district = String((req.query as Record<string, unknown>).district ?? ports().where(a.id)?.district ?? 'oshodi');
    if (!DISTRICTS.includes(district)) return reply.code(400).send({ error: 'bad_district' });
    const prices: Record<string, number> = {};
    for (const g of Object.keys(GOODS)) prices[g] = Math.round(await priceOf(db, g, district));
    const h = await db.query<{ good: string; qty: number; cost: string }>('SELECT good, qty, cost FROM market_holdings WHERE player_id = $1 AND qty > 0', [a.id]);
    const w = await db.query<{ balance: string }>('SELECT balance FROM wallets WHERE player_id = $1', [a.id]);
    return { district, goods: GOODS, prices, holdings: h.rows.map((r) => ({ good: r.good, qty: Number(r.qty), cost: Number(r.cost) })), balance: Number(w.rows[0]?.balance ?? 0) };
  });

  /** Buy or sell where you're standing (the server knows which district you're in). */
  app.post('/api/trade', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    const b = (req.body ?? {}) as Record<string, unknown>;
    const good = String(b.good ?? '');
    const qty = Math.floor(Number(b.qty));
    if (!GOODS[good] || !Number.isFinite(qty) || qty < 1 || qty > 50) return reply.code(400).send({ error: 'bad_trade' });
    const w = ports().where(a.id);
    if (!w) return reply.code(409).send({ error: 'go_online_in_a_district' });
    const district = w.district;
    const price = await priceOf(db, good, district);
    const held = await db.query<{ qty: number; cost: string }>('SELECT qty, cost FROM market_holdings WHERE player_id = $1 AND good = $2', [a.id, good]);
    const have = Number(held.rows[0]?.qty ?? 0);
    const cost = Number(held.rows[0]?.cost ?? 0);
    if (b.side === 'buy') {
      const total = Math.round(price * qty);
      if (!(await walletMove(db, a.id, -total, `Bought ${qty} × ${GOODS[good]!.name} in ${district}`))) return reply.code(402).send({ error: 'insufficient_funds' });
      await db.query(
        `INSERT INTO market_holdings (player_id, good, qty, cost) VALUES ($1, $2, $3, $4)
         ON CONFLICT (player_id, good) DO UPDATE SET qty = market_holdings.qty + $3, cost = market_holdings.cost + $4`, [a.id, good, qty, total]);
      await setPrice(db, good, district, price * 1.012 ** qty);
      return { side: 'buy', district, qty, total, price: Math.round(price * 1.012 ** qty) };
    }
    if (b.side === 'sell') {
      if (have < qty) return reply.code(409).send({ error: 'not_enough' });
      const total = Math.round(price * qty * (1 - MARKET_LEVY));
      const basis = Math.round((cost / have) * qty);
      await walletMove(db, a.id, total, `Sold ${qty} × ${GOODS[good]!.name} in ${district}`);
      await db.query('UPDATE market_holdings SET qty = qty - $3, cost = cost - $4 WHERE player_id = $1 AND good = $2', [a.id, good, qty, basis]);
      await setPrice(db, good, district, price * 0.988 ** qty);
      return { side: 'sell', district, qty, total, profit: total - basis, price: Math.round(price * 0.988 ** qty) };
    }
    return reply.code(400).send({ error: 'bad_side' });
  });

  // ----- the Lagos Gist feed -----
  app.post('/api/gist', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    const b = (req.body ?? {}) as Record<string, unknown>;
    const tpl = GIST[String(b.kind ?? '')];
    if (!tpl) return reply.code(400).send({ error: 'bad_kind' });
    let detail = '';
    if (tpl.includes('{detail}')) {
      const v = checkText(b.detail, { max: 60 });
      if (!v.ok) return reply.code(400).send({ error: `detail_${v.reason}` });
      detail = v.text;
    }
    const recent = await db.query<{ n: number; s: number | null }>(
      `SELECT count(*)::int AS n, EXTRACT(EPOCH FROM (now() - max(created_at))) AS s FROM gist_posts WHERE player_id = $1 AND created_at > now() - interval '1 day'`, [a.id]);
    if (Number(recent.rows[0]?.n ?? 0) >= 40) return reply.code(429).send({ error: 'daily_limit' });
    if (recent.rows[0]?.s !== null && recent.rows[0]?.s !== undefined && Number(recent.rows[0].s) < 20) return reply.code(429).send({ error: 'too_soon' });
    const district = ports().where(a.id)?.district ?? 'lagos';
    const name = a.name;
    const text = tpl.replace('{name}', name).replace('{district}', district.replace(/-/g, ' ')).replace('{detail}', detail);
    await db.query('INSERT INTO gist_posts (player_id, name, district, kind, text) VALUES ($1, $2, $3, $4, $5)', [a.id, name, district, String(b.kind), text]);
    return { ok: true, text };
  });

  app.get('/api/gist', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    const district = String((req.query as Record<string, unknown>).district ?? '');
    const r = await db.query(
      `SELECT g.name, g.district, g.kind, g.text, g.created_at FROM gist_posts g
       WHERE ($2 = '' OR g.district = $2)
         AND NOT EXISTS (SELECT 1 FROM blocks bl WHERE (bl.player_id = $1 AND bl.blocked_id = g.player_id) OR (bl.player_id = g.player_id AND bl.blocked_id = $1))
       ORDER BY g.created_at DESC LIMIT 30`, [a.id, district]);
    return { posts: r.rows };
  });
}
