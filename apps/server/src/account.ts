import type { FastifyReply, FastifyRequest } from 'fastify';
import type { Db } from './db.ts';
import { hashToken } from './store.ts';

/** Who is calling, with everything the tier and moderation checks need (proposal §7). */
export interface Account {
  id: string;
  name: string;
  verified: boolean;
  phoneTail: string | null;
  strikes: number;
  mutedUntil: Date | null;
  bannedUntil: Date | null;
  ageHours: number;
  level: number;
}

type Row = { id: string; name: string; verified_at: Date | null; phone_tail: string | null; strikes: number; muted_until: Date | null; banned_until: Date | null; age_h: number; level: number };

export async function accountByToken(db: Db, token: string): Promise<Account | null> {
  const r = await db.query<Row>(
    `SELECT id, name, verified_at, phone_tail, strikes, muted_until, banned_until, level,
            EXTRACT(EPOCH FROM (now() - created_at)) / 3600 AS age_h
       FROM players WHERE token_hash = $1`,
    [hashToken(token)],
  );
  return r.rows[0] ? toAccount(r.rows[0]) : null;
}

export async function accountById(db: Db, id: string): Promise<Account | null> {
  const r = await db.query<Row>(
    `SELECT id, name, verified_at, phone_tail, strikes, muted_until, banned_until, level,
            EXTRACT(EPOCH FROM (now() - created_at)) / 3600 AS age_h
       FROM players WHERE id = $1`,
    [id],
  );
  return r.rows[0] ? toAccount(r.rows[0]) : null;
}

function toAccount(r: Row): Account {
  return {
    id: r.id,
    name: r.name,
    verified: r.verified_at !== null,
    phoneTail: r.phone_tail,
    strikes: Number(r.strikes),
    mutedUntil: r.muted_until ? new Date(r.muted_until) : null,
    bannedUntil: r.banned_until ? new Date(r.banned_until) : null,
    ageHours: Number(r.age_h),
    level: Number(r.level),
  };
}

export const isBanned = (a: Account) => a.bannedUntil !== null && a.bannedUntil.getTime() > Date.now();
export const isMuted = (a: Account) => isBanned(a) || (a.mutedUntil !== null && a.mutedUntil.getTime() > Date.now());

/**
 * Route guard: resolves the Bearer token to an account, or sends 401/403 and returns null.
 * `verified` requires a phone-verified account (gigs, voting, public posts).
 */
export async function requireAccount(db: Db, req: FastifyRequest, reply: FastifyReply, opts: { verified?: boolean } = {}): Promise<Account | null> {
  reply.header('cache-control', 'no-store');
  const h = String(req.headers.authorization ?? '');
  if (!h.startsWith('Bearer ') || h.length > 300) {
    reply.code(401).send({ error: 'unauthorized' });
    return null;
  }
  const a = await accountByToken(db, h.slice(7));
  if (!a) {
    reply.code(401).send({ error: 'unauthorized' });
    return null;
  }
  if (isBanned(a)) {
    reply.code(403).send({ error: 'banned', until: a.bannedUntil });
    return null;
  }
  if (opts.verified && !a.verified) {
    reply.code(403).send({ error: 'verify_phone' });
    return null;
  }
  return a;
}
