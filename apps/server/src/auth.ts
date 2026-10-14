import { createHash, createHmac, randomInt, timingSafeEqual } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import type { Db } from './db.ts';
import { accountById, requireAccount } from './account.ts';
import { hashToken, newToken } from './store.ts';

/**
 * Phone verification by one-time code (proposal §7, "Verified" tier). The phone number is never
 * stored: only an HMAC (with a server-side pepper) and its last two digits for display.
 *
 * SMS delivery is pluggable (🔒 the owner chooses and pays for a provider):
 *   SMS_PROVIDER=webhook  POST {to, message} to SMS_WEBHOOK_URL with "Authorization: Bearer SMS_WEBHOOK_TOKEN"
 *   SMS_PROVIDER=console  print to the server log (development only)
 * With no provider configured, OTP endpoints answer 503 so nothing silently pretends to work.
 */
export interface SmsProvider {
  name: string;
  send(to: string, message: string): Promise<void>;
}

export function smsFromEnv(env: NodeJS.ProcessEnv): SmsProvider | null {
  // Without a pepper, phone hashes would be guessable: no OTP at all in production.
  if (env.NODE_ENV === 'production' && !env.PHONE_PEPPER) return null;
  const p = env.SMS_PROVIDER ?? (env.NODE_ENV === 'production' ? '' : 'console');
  if (p === 'webhook' && env.SMS_WEBHOOK_URL) {
    return {
      name: 'webhook',
      async send(to, message) {
        const res = await fetch(env.SMS_WEBHOOK_URL!, {
          method: 'POST',
          headers: { 'content-type': 'application/json', ...(env.SMS_WEBHOOK_TOKEN ? { authorization: `Bearer ${env.SMS_WEBHOOK_TOKEN}` } : {}) },
          body: JSON.stringify({ to, message }),
          signal: AbortSignal.timeout(10_000),
        });
        if (!res.ok) throw new Error(`sms webhook ${res.status}`);
      },
    };
  }
  if (p === 'console') {
    return { name: 'console', async send(to, message) { console.log(`[sms:console] to ${to.slice(0, 4)}…${to.slice(-2)}: ${message}`); } };
  }
  return null;
}

/** Normalise to E.164. Nigerian local numbers (0803…) become +234803…. */
export function normalisePhone(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  let d = raw.replace(/[\s\-().]/g, '');
  if (/^0[789][01]\d{8}$/.test(d)) d = '+234' + d.slice(1);
  if (/^234\d{10}$/.test(d)) d = '+' + d;
  return /^\+[1-9]\d{7,14}$/.test(d) ? d : null;
}

const pepper = () => {
  const p = process.env.PHONE_PEPPER;
  if (!p && process.env.NODE_ENV === 'production') throw new Error('PHONE_PEPPER must be set in production');
  return p ?? 'dev-only-pepper';
};
export const phoneHash = (e164: string) => createHmac('sha256', pepper()).update(e164).digest('hex');
const codeHash = (code: string, ph: string) => createHash('sha256').update(`${ph}:${code}`).digest('hex');

const CODE_TTL_MIN = 10;
const MAX_ATTEMPTS = 5;

export function registerAuth(app: FastifyInstance, db: Db, sms: SmsProvider | null): void {
  app.get('/api/me', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    const w = await db.query<{ balance: string }>('SELECT balance FROM wallets WHERE player_id = $1', [a.id]);
    return {
      id: a.id, name: a.name, verified: a.verified, phone: a.phoneTail ? `••••${a.phoneTail}` : null,
      strikes: a.strikes, mutedUntil: a.mutedUntil, level: a.level, market: Number(w.rows[0]?.balance ?? 0),
    };
  });

  app.post('/api/auth/otp/start', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    if (!sms) return reply.code(503).send({ error: 'otp_unavailable' });
    const phone = normalisePhone((req.body as { phone?: unknown } | null)?.phone);
    if (!phone) return reply.code(400).send({ error: 'bad_phone' });
    const ph = phoneHash(phone);
    // Rate limits: 3 codes per phone and 5 per account per hour, 20 per IP per hour.
    const lim = await db.query<{ by_phone: string; by_player: string; by_ip: string }>(
      `SELECT count(*) FILTER (WHERE phone_hash = $1) AS by_phone,
              count(*) FILTER (WHERE player_id = $2) AS by_player,
              count(*) FILTER (WHERE ip = $3) AS by_ip
         FROM otp_codes WHERE created_at > now() - interval '1 hour'`,
      [ph, a.id, req.ip],
    );
    const l = lim.rows[0]!;
    if (Number(l.by_phone) >= 3 || Number(l.by_player) >= 5 || Number(l.by_ip) >= 20) return reply.code(429).send({ error: 'too_many_codes' });
    const code = String(randomInt(100000, 1000000));
    await db.query(
      `INSERT INTO otp_codes (phone_hash, player_id, code_hash, ip, expires_at) VALUES ($1, $2, $3, $4, now() + interval '${CODE_TTL_MIN} minutes')`,
      [ph, a.id, codeHash(code, ph), req.ip],
    );
    try {
      await sms.send(phone, `Naija Street Life code: ${code}. It expires in ${CODE_TTL_MIN} minutes. Never share it.`);
    } catch (e) {
      req.log.error({ err: e }, 'sms send failed');
      return reply.code(502).send({ error: 'sms_failed' });
    }
    return { ok: true, sentTo: `${phone.slice(0, 4)}•••••${phone.slice(-2)}`, ...(process.env.OTP_DEV_ECHO === '1' ? { devCode: code } : {}) };
  });

  app.post('/api/auth/otp/verify', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    const body = (req.body ?? {}) as { phone?: unknown; code?: unknown };
    const phone = normalisePhone(body.phone);
    const code = typeof body.code === 'string' ? body.code.trim() : '';
    if (!phone || !/^\d{6}$/.test(code)) return reply.code(400).send({ error: 'bad_code' });
    const ph = phoneHash(phone);
    const r = await db.query<{ id: string; code_hash: string; attempts: number }>(
      `SELECT id, code_hash, attempts FROM otp_codes
        WHERE phone_hash = $1 AND player_id = $2 AND expires_at > now()
        ORDER BY created_at DESC LIMIT 1`,
      [ph, a.id],
    );
    const row = r.rows[0];
    if (!row || Number(row.attempts) >= MAX_ATTEMPTS) return reply.code(400).send({ error: 'code_expired' });
    const want = Buffer.from(row.code_hash, 'hex');
    const got = Buffer.from(codeHash(code, ph), 'hex');
    if (want.length !== got.length || !timingSafeEqual(want, got)) {
      await db.query('UPDATE otp_codes SET attempts = attempts + 1 WHERE id = $1', [row.id]);
      return reply.code(400).send({ error: 'wrong_code', attemptsLeft: MAX_ATTEMPTS - Number(row.attempts) - 1 });
    }
    await db.query('DELETE FROM otp_codes WHERE phone_hash = $1', [ph]);
    // Already verified on another account (new phone, reinstalled game): sign in to that account
    // by issuing it a fresh token. The old token stops working.
    const owner = await db.query<{ id: string }>('SELECT id FROM players WHERE phone_hash = $1', [ph]);
    if (owner.rows[0] && owner.rows[0]!.id !== a.id) {
      const token = newToken();
      await db.query('UPDATE players SET token_hash = $2 WHERE id = $1', [owner.rows[0]!.id, hashToken(token)]);
      const other = await accountById(db, owner.rows[0]!.id);
      return { ok: true, verified: true, switched: true, token, id: other?.id, name: other?.name };
    }
    await db.query('UPDATE players SET phone_hash = $2, phone_tail = $3, verified_at = now() WHERE id = $1', [a.id, ph, phone.slice(-2)]);
    return { ok: true, verified: true, switched: false };
  });
}
