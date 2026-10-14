import { timingSafeEqual } from 'node:crypto';
import { readFileSync } from 'node:fs';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import type { Db } from './db.ts';
import { addStrike } from './moderation.ts';
import { count } from './civic.ts';

/**
 * Moderator/admin console (proposal §7 tooling): report queue, player history, strikes and bans,
 * poll approval, election freeze/re-run, transparency stats and an audit trail of every action.
 * Enabled only when ADMIN_TOKEN (≥ 24 chars) is set. UI: GET /admin (static page).
 */
export function registerAdmin(app: FastifyInstance, db: Db, onPlayerChanged: (id: string) => void): void {
  const token = process.env.ADMIN_TOKEN ?? '';
  const enabled = token.length >= 24;

  const guard = (req: FastifyRequest, reply: FastifyReply): string | null => {
    reply.header('cache-control', 'no-store');
    if (!enabled) {
      reply.code(404).send({ error: 'admin_disabled' });
      return null;
    }
    const h = String(req.headers.authorization ?? '');
    const got = Buffer.from(h.startsWith('Bearer ') ? h.slice(7) : '');
    const want = Buffer.from(token);
    if (got.length !== want.length || !timingSafeEqual(got, want)) {
      reply.code(401).send({ error: 'unauthorized' });
      return null;
    }
    // Moderators sign their actions with a name (shown in the audit trail).
    return String(req.headers['x-moderator'] ?? 'admin').slice(0, 40);
  };
  const audit = (actor: string, action: string, target: string | null, detail: unknown = {}) =>
    db.query('INSERT INTO admin_actions (actor, action, target, detail) VALUES ($1, $2, $3, $4)', [actor, action, target, JSON.stringify(detail)]);

  app.get('/admin', async (_req, reply) => {
    if (!enabled) return reply.code(404).send('Admin console is disabled (set ADMIN_TOKEN).');
    reply.header('content-type', 'text/html; charset=utf-8').header('cache-control', 'no-store');
    return readFileSync(new URL('./admin.html', import.meta.url), 'utf8');
  });

  app.get('/api/admin/stats', async (req, reply) => {
    if (!guard(req, reply)) return;
    const q = async (sql: string) => Number((await db.query<{ n: string }>(sql)).rows[0]!.n);
    return {
      players: await q('SELECT count(*) AS n FROM players'),
      verified: await q('SELECT count(*) AS n FROM players WHERE verified_at IS NOT NULL'),
      active24h: await q(`SELECT count(*) AS n FROM players WHERE last_seen > now() - interval '24 hours'`),
      messages24h: await q(`SELECT count(*) AS n FROM chat_messages WHERE created_at > now() - interval '24 hours'`),
      openReports: await q(`SELECT count(*) AS n FROM reports WHERE status = 'open'`),
      strikes30d: await q(`SELECT count(*) AS n FROM strikes_log WHERE created_at > now() - interval '30 days'`),
      openGigs: await q(`SELECT count(*) AS n FROM gigs WHERE status = 'open' AND expires_at > now()`),
      pendingPolls: await q(`SELECT count(*) AS n FROM polls WHERE status = 'pending'`),
      flaggedElections: await q('SELECT count(*) AS n FROM elections WHERE flagged'),
    };
  });

  app.get('/api/admin/reports', async (req, reply) => {
    if (!guard(req, reply)) return;
    const status = String((req.query as { status?: string }).status ?? 'open');
    const r = await db.query(
      `SELECT r.id, r.reason, r.context, r.status, r.resolution, r.created_at, r.gig_id, r.message_id,
              rp.name AS reporter, tp.id AS target_id, tp.name AS target, tp.strikes AS target_strikes
         FROM reports r JOIN players rp ON rp.id = r.reporter LEFT JOIN players tp ON tp.id = r.target_player
        WHERE r.status = $1 ORDER BY r.id DESC LIMIT 100`,
      [status],
    );
    return { reports: r.rows };
  });

  app.post('/api/admin/reports/:id/resolve', async (req, reply) => {
    const actor = guard(req, reply);
    if (!actor) return;
    const id = Number((req.params as { id: string }).id);
    const b = (req.body ?? {}) as { action?: string; note?: string };
    const rep = await db.query<{ target_player: string | null; message_id: string | null; gig_id: string | null }>('SELECT target_player, message_id, gig_id FROM reports WHERE id = $1', [id]);
    if (!rep.rows[0]) return reply.code(404).send({ error: 'not_found' });
    const action = ['dismiss', 'strike', 'hide'].includes(String(b.action)) ? String(b.action) : 'dismiss';
    let result = 'dismissed';
    if (action !== 'dismiss' && rep.rows[0]!.message_id) await db.query('UPDATE chat_messages SET hidden = true WHERE id = $1', [rep.rows[0]!.message_id]);
    if (action !== 'dismiss' && rep.rows[0]!.gig_id) await db.query(`UPDATE gigs SET status = 'removed' WHERE id = $1`, [rep.rows[0]!.gig_id]);
    if (action === 'strike' && rep.rows[0]!.target_player) {
      result = await addStrike(db, rep.rows[0]!.target_player, `report #${id}: ${String(b.note ?? '').slice(0, 120)}`, actor);
      onPlayerChanged(rep.rows[0]!.target_player);
    } else if (action === 'hide') result = 'hidden';
    await db.query(`UPDATE reports SET status = 'resolved', resolution = $2 WHERE id = $1`, [id, `${result}${b.note ? ': ' + String(b.note).slice(0, 200) : ''}`]);
    await audit(actor, `report.${action}`, String(id), { result });
    return { ok: true, result };
  });

  app.get('/api/admin/players', async (req, reply) => {
    if (!guard(req, reply)) return;
    const q = String((req.query as { q?: string }).q ?? '').slice(0, 40);
    const r = await db.query(
      `SELECT id, name, verified_at IS NOT NULL AS verified, strikes, muted_until, banned_until, level, created_at, last_seen
         FROM players WHERE name ILIKE $1 OR id::text = $2 ORDER BY last_seen DESC LIMIT 50`,
      [`%${q}%`, q],
    );
    return { players: r.rows };
  });

  app.get('/api/admin/players/:id', async (req, reply) => {
    if (!guard(req, reply)) return;
    const id = (req.params as { id: string }).id;
    const strikes = await db.query('SELECT reason, action, by_actor, created_at FROM strikes_log WHERE player_id = $1 ORDER BY id DESC', [id]);
    const reports = await db.query('SELECT id, reason, context, status, created_at FROM reports WHERE target_player = $1 ORDER BY id DESC LIMIT 50', [id]);
    const messages = await db.query('SELECT id, channel, text, hidden, created_at FROM chat_messages WHERE sender = $1 ORDER BY id DESC LIMIT 50', [id]);
    return { strikes: strikes.rows, reports: reports.rows, messages: messages.rows };
  });

  app.post('/api/admin/players/:id/:action', async (req, reply) => {
    const actor = guard(req, reply);
    if (!actor) return;
    const { id, action } = req.params as { id: string; action: string };
    const b = (req.body ?? {}) as { reason?: string; hours?: number };
    let result = action;
    if (action === 'strike') result = await addStrike(db, id, String(b.reason ?? 'moderator').slice(0, 200), actor);
    else if (action === 'mute') await db.query(`UPDATE players SET muted_until = now() + ($2 || ' hours')::interval WHERE id = $1`, [id, String(Math.max(1, Math.min(720, Number(b.hours) || 24)))]);
    else if (action === 'unban') await db.query('UPDATE players SET banned_until = NULL, muted_until = NULL WHERE id = $1', [id]);
    else if (action === 'ban') await db.query(`UPDATE players SET banned_until = 'infinity' WHERE id = $1`, [id]);
    else return reply.code(400).send({ error: 'bad_action' });
    onPlayerChanged(id);
    await audit(actor, `player.${action}`, id, { reason: b.reason, result });
    return { ok: true, result };
  });

  // Polls: admins create (open immediately) and approve or reject player proposals.
  app.get('/api/admin/polls', async (req, reply) => {
    if (!guard(req, reply)) return;
    const r = await db.query(`SELECT p.id, p.question, p.options, p.kind, p.status, p.closes_at, pl.name AS by FROM polls p LEFT JOIN players pl ON pl.id = p.created_by ORDER BY p.id DESC LIMIT 50`);
    return { polls: r.rows };
  });

  app.post('/api/admin/polls', async (req, reply) => {
    const actor = guard(req, reply);
    if (!actor) return;
    const b = (req.body ?? {}) as { question?: string; options?: string[]; kind?: string; hours?: number; showResults?: string; minTurnout?: number };
    const question = String(b.question ?? '').slice(0, 120);
    const options = (Array.isArray(b.options) ? b.options : []).map((o) => String(o).slice(0, 40)).filter(Boolean).slice(0, 6);
    if (!question || options.length < 2) return reply.code(400).send({ error: 'bad_poll' });
    const r = await db.query<{ id: string }>(
      `INSERT INTO polls (question, kind, options, status, show_results, min_turnout, closes_at)
       VALUES ($1, $2, $3, 'open', $4, $5, now() + ($6 || ' hours')::interval) RETURNING id`,
      [question, b.kind === 'multi' ? 'multi' : 'single', JSON.stringify(options), b.showResults === 'live' ? 'live' : 'after', Math.max(0, Number(b.minTurnout) || 0), String(Math.max(1, Math.min(720, Number(b.hours) || 48)))],
    );
    await audit(actor, 'poll.create', r.rows[0]!.id, { question });
    return { ok: true, id: Number(r.rows[0]!.id) };
  });

  app.post('/api/admin/polls/:id/:action', async (req, reply) => {
    const actor = guard(req, reply);
    if (!actor) return;
    const { id, action } = req.params as { id: string; action: string };
    if (!['approve', 'reject', 'close'].includes(action)) return reply.code(400).send({ error: 'bad_action' });
    const status = action === 'approve' ? 'open' : action === 'reject' ? 'rejected' : 'closed';
    await db.query(`UPDATE polls SET status = $2${action === 'approve' ? ', opens_at = now()' : ''} WHERE id = $1`, [id, status]);
    await audit(actor, `poll.${action}`, id);
    return { ok: true, status };
  });

  // Elections: freeze a suspicious one, re-run it (votes wiped), or force the count.
  app.get('/api/admin/elections', async (req, reply) => {
    if (!guard(req, reply)) return;
    const r = await db.query(`SELECT e.id, e.ward, e.office, e.week_start, e.status, e.flagged, e.policy, (SELECT count(*) FROM votes v WHERE v.election_id = e.id) AS votes FROM elections e ORDER BY e.id DESC LIMIT 60`);
    return { elections: r.rows };
  });

  app.post('/api/admin/elections/:id/:action', async (req, reply) => {
    const actor = guard(req, reply);
    if (!actor) return;
    const { id, action } = req.params as { id: string; action: string };
    if (action === 'freeze') await db.query('UPDATE elections SET flagged = true WHERE id = $1', [id]);
    else if (action === 'unfreeze') await db.query('UPDATE elections SET flagged = false WHERE id = $1', [id]);
    else if (action === 'rerun') {
      await db.query('DELETE FROM votes WHERE election_id = $1', [id]);
      await db.query(`UPDATE elections SET flagged = false, status = 'open', winner = NULL, policy = NULL WHERE id = $1`, [id]);
    } else if (action === 'count') await count(db, Number(id));
    else return reply.code(400).send({ error: 'bad_action' });
    await audit(actor, `election.${action}`, id);
    return { ok: true };
  });

  app.get('/api/admin/actions', async (req, reply) => {
    if (!guard(req, reply)) return;
    const r = await db.query('SELECT actor, action, target, detail, created_at FROM admin_actions ORDER BY id DESC LIMIT 200');
    return { actions: r.rows };
  });
}
