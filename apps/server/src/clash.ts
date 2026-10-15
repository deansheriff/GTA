import { createHash, randomBytes } from 'node:crypto';
import type { Db } from './db.ts';

/**
 * Street clashes between online players (owner request, 2026-10-15): a collision on the street
 * asks both players "Fight or apologise?". Apologising is a real choice, but it is not a shield:
 * if EITHER player chooses to fight, the fight happens and the peaceful one has to defend.
 *
 * Fair and cheat-resistant: the server checks the collision against its own positions, creates
 * one move sequence for both fighters, and re-scores each player's input log (as in challenges).
 * Slapstick only (Story Bible): no blood, no money changes hands, small cosmetic effects.
 * Abuse limits: per-pair cooldown, hourly cap per player, blocks respected, every clash logged.
 */
export const MOVES = ['jab', 'duck', 'block'] as const;
const CHOICE_MS = 10_000;
const FIGHT_MS = 25_000;
const PAIR_COOLDOWN_MS = 3 * 60_000;
const HOURLY_CAP = 8;
const CONTACT_PX = 220;

export interface ClashParty {
  pid: string;
  name: string;
  send(msg: unknown): void;
}

interface Clash {
  id: string;
  a: ClashParty;
  b: ClashParty;
  choice: Record<string, 'fight' | 'peace'>;
  seq: string[];
  logs: Record<string, unknown>;
  stage: 'choose' | 'fight' | 'done';
  timer?: NodeJS.Timeout;
  started: number;
}

export function makeFight(seed: string): { seq: string[]; windows: number[] } {
  let h = createHash('sha256').update(seed).digest();
  const seq: string[] = [];
  for (let i = 0; i < 10; i++) {
    if (i >= h.length) h = createHash('sha256').update(h).digest();
    seq.push(MOVES[h[i]! % 3]!);
  }
  return { seq, windows: seq.map((_, i) => Number(Math.max(0.8, 1.5 - i * 0.07).toFixed(2))) };
}

/** Same rules as the game's fist-fight mini-game: right move inside the window scores. */
export function scoreFight(seq: string[], log: unknown): number {
  if (!Array.isArray(log) || log.length > 40) return 0;
  let hits = 0;
  for (let i = 0; i < seq.length; i++) {
    const e = log[i] as { move?: string; t?: number } | undefined;
    const window = Math.max(0.8, 1.5 - i * 0.07);
    if (e && e.move === seq[i] && Number.isFinite(e.t) && Number(e.t) >= 0.12 && Number(e.t) <= window) hits++;
  }
  return Math.round((hits / seq.length) * 100);
}

export class ClashManager {
  private db: Db;
  private active = new Map<string, Clash>();
  private pairAt = new Map<string, number>();
  private recent = new Map<string, number[]>();

  constructor(db: Db) {
    this.db = db;
  }

  private pairKey(a: string, b: string) {
    return a < b ? `${a}|${b}` : `${b}|${a}`;
  }

  busy(pid: string): boolean {
    for (const c of this.active.values()) if (c.a.pid === pid || c.b.pid === pid) return true;
    return false;
  }

  /**
   * A client reports a collision. `posA`/`posB` are the server's own positions for both players.
   * Returns an error code or "ok".
   */
  async report(a: ClashParty, b: ClashParty, posA: { x: number; y: number }, posB: { x: number; y: number }, now = Date.now()): Promise<string> {
    if (a.pid === b.pid) return 'self';
    if (Math.hypot(posA.x - posB.x, posA.y - posB.y) > CONTACT_PX) return 'too_far';
    if (this.busy(a.pid) || this.busy(b.pid)) return 'busy';
    const key = this.pairKey(a.pid, b.pid);
    if (now - (this.pairAt.get(key) ?? 0) < PAIR_COOLDOWN_MS) return 'cooldown';
    const mine = (this.recent.get(a.pid) ?? []).filter((t) => now - t < 3600_000);
    if (mine.length >= HOURLY_CAP) return 'cap';
    const blocked = await this.db.query('SELECT 1 FROM blocks WHERE (player_id = $1 AND blocked_id = $2) OR (player_id = $2 AND blocked_id = $1)', [a.pid, b.pid]);
    if (blocked.rows.length) return 'blocked';
    mine.push(now);
    this.recent.set(a.pid, mine);
    this.pairAt.set(key, now);
    const c: Clash = { id: randomBytes(8).toString('hex'), a, b, choice: {}, seq: [], logs: {}, stage: 'choose', started: now };
    this.active.set(c.id, c);
    for (const [me, other] of [[a, b], [b, a]] as const) me.send({ t: 'clash', id: c.id, pid: other.pid, name: other.name, ms: CHOICE_MS });
    // No answer in time counts as peace (nobody can be forced to click).
    c.timer = setTimeout(() => void this.decide(c), CHOICE_MS + 500);
    return 'ok';
  }

  choose(pid: string, id: unknown, choice: unknown): void {
    const c = this.active.get(String(id));
    if (!c || c.stage !== 'choose' || (c.a.pid !== pid && c.b.pid !== pid)) return;
    c.choice[pid] = choice === 'fight' ? 'fight' : 'peace';
    if (c.choice[c.a.pid] && c.choice[c.b.pid]) void this.decide(c);
  }

  private async decide(c: Clash): Promise<void> {
    if (c.stage !== 'choose') return;
    clearTimeout(c.timer);
    const ca = c.choice[c.a.pid] ?? 'peace';
    const cb = c.choice[c.b.pid] ?? 'peace';
    if (ca === 'peace' && cb === 'peace') {
      c.stage = 'done';
      this.active.delete(c.id);
      for (const p of [c.a, c.b]) p.send({ t: 'clash_end', id: c.id, outcome: 'peace' });
      await this.log(c, ca, cb, 'peace', null, null, null);
      return;
    }
    // Someone wants a fight: it happens, whatever the other chose.
    c.stage = 'fight';
    const f = makeFight(c.id);
    c.seq = f.seq;
    for (const [me, other] of [[c.a, c.b], [c.b, c.a]] as const) {
      me.send({ t: 'clash_fight', id: c.id, name: other.name, seq: f.seq, windows: f.windows, you: c.choice[me.pid] ?? 'peace', them: c.choice[other.pid] ?? 'peace' });
    }
    c.timer = setTimeout(() => void this.finish(c), FIGHT_MS);
  }

  result(pid: string, id: unknown, log: unknown): void {
    const c = this.active.get(String(id));
    if (!c || c.stage !== 'fight' || (c.a.pid !== pid && c.b.pid !== pid) || pid in c.logs) return;
    c.logs[pid] = log;
    if (c.a.pid in c.logs && c.b.pid in c.logs) void this.finish(c);
  }

  private async finish(c: Clash): Promise<void> {
    if (c.stage !== 'fight') return;
    clearTimeout(c.timer);
    c.stage = 'done';
    this.active.delete(c.id);
    const sa = scoreFight(c.seq, c.logs[c.a.pid]);
    const sb = scoreFight(c.seq, c.logs[c.b.pid]);
    const winner = sa === sb ? null : sa > sb ? c.a.pid : c.b.pid;
    for (const p of [c.a, c.b]) p.send({ t: 'clash_end', id: c.id, outcome: 'fight', winner, scores: { [c.a.pid]: sa, [c.b.pid]: sb } });
    await this.log(c, c.choice[c.a.pid] ?? 'peace', c.choice[c.b.pid] ?? 'peace', 'fight', winner, sa, sb);
  }

  /** A player who disconnects mid-clash simply loses the round (or it ends in peace). */
  left(pid: string): void {
    for (const c of this.active.values()) {
      if (c.a.pid !== pid && c.b.pid !== pid) continue;
      if (c.stage === 'choose') {
        c.choice[pid] = 'peace';
        void this.decide(c);
      } else if (c.stage === 'fight' && !(pid in c.logs)) {
        c.logs[pid] = [];
        if (c.a.pid in c.logs && c.b.pid in c.logs) void this.finish(c);
      }
    }
  }

  private async log(c: Clash, ca: string, cb: string, outcome: string, winner: string | null, sa: number | null, sb: number | null) {
    await this.db.query(
      'INSERT INTO clashes (a, b, choice_a, choice_b, outcome, winner, score_a, score_b) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)',
      [c.a.pid, c.b.pid, ca, cb, outcome, winner, sa, sb],
    ).catch(() => {});
  }
}
