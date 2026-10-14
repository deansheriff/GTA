import type { FastifyInstance } from 'fastify';
import type { Db } from './db.ts';
import { accountById, isMuted, requireAccount, type Account } from './account.ts';
import { addStrike, checkText } from './moderation.ts';

/**
 * Venue chat (per street/room), DMs, blocks and reports (proposal §7).
 *  - Members may chat once their account is CHAT_MIN_AGE_HOURS old (default 24) or phone-verified.
 *  - Every message passes checkText() before anyone sees it; repeated hate or scam attempts strike.
 *  - Blocking hides a player's chat and DMs from you (enforced on the server).
 */
export interface ChatTarget {
  playerId: string;
  room?: string;
  send(msg: unknown): void;
}

const RATE_WINDOW_MS = 10_000;
const RATE_MAX = 5;
const ACCOUNT_TTL_MS = 30_000;

export class ChatHub {
  private db: Db;
  private targets: () => Iterable<ChatTarget>;
  private blocks = new Map<string, Set<string>>(); // player -> players they blocked
  private accounts = new Map<string, { a: Account; at: number }>();
  private recent = new Map<string, number[]>();
  private violations = new Map<string, number[]>();

  constructor(db: Db, targets: () => Iterable<ChatTarget>) {
    this.db = db;
    this.targets = targets;
  }

  private async account(id: string): Promise<Account | null> {
    const c = this.accounts.get(id);
    if (c && Date.now() - c.at < ACCOUNT_TTL_MS) return c.a;
    const a = await accountById(this.db, id);
    if (a) this.accounts.set(id, { a, at: Date.now() });
    return a;
  }

  forget(id: string) {
    this.accounts.delete(id);
  }

  async blockedBy(id: string): Promise<Set<string>> {
    let s = this.blocks.get(id);
    if (!s) {
      const r = await this.db.query<{ blocked_id: string }>('SELECT blocked_id FROM blocks WHERE player_id = $1', [id]);
      s = new Set(r.rows.map((x) => x.blocked_id));
      this.blocks.set(id, s);
    }
    return s;
  }

  invalidateBlocks(id: string) {
    this.blocks.delete(id);
  }

  /** Checks shared by chat and DMs. Returns an error code or the cleaned text. */
  private async gate(senderId: string, text: unknown): Promise<{ err: string } | { a: Account; text: string }> {
    const a = await this.account(senderId);
    if (!a) return { err: 'unauthorized' };
    if (isMuted(a)) return { err: 'muted' };
    const minAge = Number(process.env.CHAT_MIN_AGE_HOURS ?? 24);
    if (!a.verified && a.ageHours < minAge && a.level < 3) return { err: 'too_new' };
    const now = Date.now();
    const times = (this.recent.get(senderId) ?? []).filter((t) => now - t < RATE_WINDOW_MS);
    if (times.length >= RATE_MAX) return { err: 'slow_down' };
    times.push(now);
    this.recent.set(senderId, times);
    const v = checkText(text, { verified: a.verified });
    if (!v.ok) {
      if (['hate', 'off_platform_payment', 'abuse'].includes(v.reason)) {
        const vs = (this.violations.get(senderId) ?? []).filter((t) => now - t < 10 * 60_000);
        vs.push(now);
        this.violations.set(senderId, vs);
        if (vs.length >= 3) {
          this.violations.set(senderId, []);
          await addStrike(this.db, senderId, `auto: repeated ${v.reason}`, 'system');
          this.forget(senderId);
        }
      }
      return { err: v.hold ? 'held_for_review' : `blocked_${v.reason}` };
    }
    return { a, text: v.text };
  }

  /** Room chat: everyone in the same room except those who blocked the sender. */
  async chat(sender: ChatTarget, text: unknown): Promise<void> {
    if (!sender.room) return;
    const g = await this.gate(sender.playerId, text);
    if ('err' in g) return sender.send({ t: 'err', code: g.err });
    const r = await this.db.query<{ id: string }>('INSERT INTO chat_messages (channel, sender, text) VALUES ($1, $2, $3) RETURNING id', [sender.room, sender.playerId, g.text]);
    const msg = { t: 'chat', id: Number(r.rows[0]!.id), pid: sender.playerId, name: g.a.name, text: g.text, v: g.a.verified };
    for (const t of this.targets()) {
      if (t.room !== sender.room) continue;
      if ((await this.blockedBy(t.playerId)).has(sender.playerId)) continue;
      t.send(msg);
    }
  }

  async dm(sender: ChatTarget, to: unknown, text: unknown): Promise<void> {
    if (typeof to !== 'string' || !/^[0-9a-f-]{36}$/.test(to) || to === sender.playerId) return sender.send({ t: 'err', code: 'bad_recipient' });
    const g = await this.gate(sender.playerId, text);
    if ('err' in g) return sender.send({ t: 'err', code: g.err });
    const exists = await this.db.query('SELECT 1 FROM players WHERE id = $1', [to]);
    if (exists.rows.length === 0) return sender.send({ t: 'err', code: 'bad_recipient' });
    const blocked = (await this.blockedBy(to)).has(sender.playerId);
    const r = await this.db.query<{ id: string }>('INSERT INTO chat_messages (channel, sender, recipient, text, hidden) VALUES ($1, $2, $3, $4, $5) RETURNING id', ['dm', sender.playerId, to, g.text, blocked]);
    const msg = { t: 'dm', id: Number(r.rows[0]!.id), pid: sender.playerId, to, name: g.a.name, text: g.text };
    sender.send({ ...msg, sent: true });
    if (blocked) return; // the sender is not told they're blocked
    for (const t of this.targets()) if (t.playerId === to) t.send(msg);
  }
}

export function registerSocial(app: FastifyInstance, db: Db, hub: () => ChatHub): void {
  app.get('/api/dms', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    const other = String((req.query as { with?: string }).with ?? '');
    if (!/^[0-9a-f-]{36}$/.test(other)) return reply.code(400).send({ error: 'bad_player' });
    const r = await db.query(
      `SELECT m.id, m.sender AS pid, p.name, m.text, m.created_at AS at FROM chat_messages m JOIN players p ON p.id = m.sender
        WHERE m.channel = 'dm' AND ((m.sender = $1 AND m.recipient = $2) OR (m.sender = $2 AND m.recipient = $1 AND NOT m.hidden))
        ORDER BY m.id DESC LIMIT 50`,
      [a.id, other],
    );
    return { messages: r.rows.reverse() };
  });

  app.get('/api/dms/threads', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    const r = await db.query(
      `SELECT DISTINCT ON (other) other AS pid, p.name, last_text, last_at FROM (
         SELECT CASE WHEN sender = $1 THEN recipient ELSE sender END AS other, text AS last_text, created_at AS last_at, id
           FROM chat_messages WHERE channel = 'dm' AND (sender = $1 OR (recipient = $1 AND NOT hidden))
       ) t JOIN players p ON p.id = t.other ORDER BY other, t.id DESC`,
      [a.id],
    );
    return { threads: r.rows };
  });

  app.get('/api/blocks', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    const r = await db.query('SELECT b.blocked_id AS pid, p.name FROM blocks b JOIN players p ON p.id = b.blocked_id WHERE b.player_id = $1', [a.id]);
    return { blocked: r.rows };
  });

  app.post('/api/blocks', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    const id = String((req.body as { pid?: string } | null)?.pid ?? '');
    if (!/^[0-9a-f-]{36}$/.test(id) || id === a.id) return reply.code(400).send({ error: 'bad_player' });
    await db.query('INSERT INTO blocks (player_id, blocked_id) VALUES ($1, $2) ON CONFLICT DO NOTHING', [a.id, id]).catch(() => {});
    hub().invalidateBlocks(a.id);
    return { ok: true };
  });

  app.delete('/api/blocks/:pid', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    await db.query('DELETE FROM blocks WHERE player_id = $1 AND blocked_id = $2', [a.id, (req.params as { pid: string }).pid]);
    hub().invalidateBlocks(a.id);
    return { ok: true };
  });

  // Reports go to the moderator queue with the message text as context.
  app.post('/api/reports', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    const b = (req.body ?? {}) as { pid?: string; message?: number; gig?: number; reason?: string };
    const reason = String(b.reason ?? '').slice(0, 200);
    if (!reason) return reply.code(400).send({ error: 'reason_required' });
    const open = await db.query<{ n: string }>(`SELECT count(*) AS n FROM reports WHERE reporter = $1 AND created_at > now() - interval '1 hour'`, [a.id]);
    if (Number(open.rows[0]!.n) >= 10) return reply.code(429).send({ error: 'too_many_reports' });
    let target = b.pid && /^[0-9a-f-]{36}$/.test(b.pid) ? b.pid : null;
    let context: string | null = null;
    if (Number.isInteger(b.message)) {
      const m = await db.query<{ sender: string; text: string }>('SELECT sender, text FROM chat_messages WHERE id = $1', [b.message]);
      if (m.rows[0]) {
        target = m.rows[0]!.sender;
        context = m.rows[0]!.text;
      }
    }
    if (!target && !Number.isInteger(b.gig)) return reply.code(400).send({ error: 'nothing_to_report' });
    const r = await db.query<{ id: string }>('INSERT INTO reports (reporter, target_player, message_id, gig_id, reason, context) VALUES ($1, $2, $3, $4, $5, $6) RETURNING id', [a.id, target, Number.isInteger(b.message) ? b.message : null, Number.isInteger(b.gig) ? b.gig : null, reason, context]);
    return { ok: true, id: Number(r.rows[0]!.id) };
  });
}
