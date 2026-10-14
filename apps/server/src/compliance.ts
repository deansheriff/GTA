import { readFileSync } from 'node:fs';
import type { FastifyInstance } from 'fastify';
import type { Db } from './db.ts';
import { requireAccount } from './account.ts';
import type { Flags } from './flags.ts';

/**
 * Compliance (M7): privacy policy and terms pages, NDPA data-subject rights (export and erasure),
 * opt-in anonymous telemetry and crash reports, and the hard "off" switch for real money.
 * The legal texts are DRAFTS for the owner's lawyer ⚖️ (apps/server/src/legal/*.md).
 */
function md(text: string): string {
  const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const inline = (s: string) => esc(s).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>').replace(/\[(.+?)\]\((https?:\/\/[^)\s]+|\/[^)\s]*)\)/g, '<a href="$2">$1</a>');
  const out: string[] = [];
  let list = false;
  for (const line of text.split(/\r?\n/)) {
    const li = line.match(/^\s*[-*] (.*)$/);
    if (li) {
      if (!list) { out.push('<ul>'); list = true; }
      out.push(`<li>${inline(li[1]!)}</li>`);
      continue;
    }
    if (list) { out.push('</ul>'); list = false; }
    const h = line.match(/^(#{1,3}) (.*)$/);
    if (h) out.push(`<h${h[1]!.length}>${inline(h[2]!)}</h${h[1]!.length}>`);
    else if (line.trim()) out.push(`<p>${inline(line)}</p>`);
  }
  if (list) out.push('</ul>');
  return out.join('\n');
}

function page(title: string, body: string): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${title}</title>
<style>body{margin:0;background:#f1e6c8;color:#1d1611;font:16px/1.6 system-ui,sans-serif}main{max-width:760px;margin:auto;padding:24px 16px}h1{color:#a8382c}a{color:#2f6f99}</style></head><body><main>${body}</main></body></html>`;
}

/** Retention periods from the privacy policy, enforced by a periodic job. */
export async function enforceRetention(db: Db): Promise<void> {
  await db.query(`DELETE FROM chat_messages WHERE created_at < now() - interval '12 months'`);
  await db.query(`DELETE FROM telemetry_events WHERE created_at < now() - interval '13 months'`);
  await db.query(`DELETE FROM crash_reports WHERE created_at < now() - interval '13 months'`);
  await db.query(`DELETE FROM strikes_log WHERE created_at < now() - interval '24 months'`);
  await db.query(`DELETE FROM reports WHERE status <> 'open' AND created_at < now() - interval '24 months'`);
  await db.query(`DELETE FROM otp_codes WHERE expires_at < now() - interval '1 day'`);
  await db.query(`DELETE FROM npc_chat_log WHERE created_at < now() - interval '12 months'`);
  await db.query(`DELETE FROM challenge_runs WHERE status = 'open' AND created_at < now() - interval '1 day'`);
}

const ALLOWED_EVENTS = new Set(['session_start', 'mission_start', 'mission_complete', 'mission_fail', 'minigame', 'fps_bucket', 'preset', 'gig_done', 'challenge', 'switch_hero', 'ending']);

export function registerCompliance(app: FastifyInstance, db: Db, flags: Flags): void {
  for (const [path, file, title] of [['/privacy', 'privacy.md', 'Privacy policy'], ['/terms', 'terms.md', 'Terms of use']] as const) {
    app.get(path, async (_req, reply) => {
      reply.header('content-type', 'text/html; charset=utf-8').header('cache-control', 'public, max-age=3600');
      return page(`Naija Street Life · ${title}`, md(readFileSync(new URL(`./legal/${file}`, import.meta.url), 'utf8')));
    });
  }

  // NDPA: a copy of everything we hold about you.
  app.get('/api/me/export', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    const q = async (sql: string) => (await db.query(sql, [a.id])).rows;
    return {
      exportedAt: new Date().toISOString(),
      account: (await q('SELECT id, name, look, created_at, last_seen, verified_at, phone_tail, strikes, muted_until, banned_until, level, birth_year FROM players WHERE id = $1'))[0],
      note: 'Your phone number is not stored, only a keyed hash and its last two digits.',
      save: (await q('SELECT revision, data, updated_at FROM saves WHERE player_id = $1'))[0] ?? null,
      profile: (await q('SELECT * FROM profiles WHERE player_id = $1'))[0] ?? null,
      messages: await q('SELECT channel, recipient, text, created_at FROM chat_messages WHERE sender = $1 ORDER BY id'),
      blocks: await q('SELECT blocked_id, 1 AS x FROM blocks WHERE player_id = $1'),
      reportsFiled: await q('SELECT reason, status, created_at FROM reports WHERE reporter = $1'),
      strikes: await q('SELECT reason, action, created_at FROM strikes_log WHERE player_id = $1'),
      wallet: (await q('SELECT balance FROM wallets WHERE player_id = $1'))[0] ?? null,
      walletLedger: await q('SELECT delta, reason, created_at FROM wallet_ledger WHERE player_id = $1 ORDER BY id'),
      gigsPosted: await q('SELECT title, skill, district, pay, status, created_at FROM gigs WHERE poster = $1'),
      gigsWorked: await q('SELECT gig_id, status, score, created_at FROM gig_assignments WHERE worker = $1'),
      ratingsGiven: await q('SELECT gig_id, stars, text FROM ratings WHERE rater = $1'),
      pollVotes: await q('SELECT poll_id, choices, created_at FROM poll_votes WHERE player_id = $1'),
      electionVotes: await q('SELECT election_id, hash AS receipt, created_at FROM votes WHERE voter = $1'),
      npcChats: await q('SELECT npc, player_text, reply, created_at FROM npc_chat_log WHERE player_id = $1'),
      challenges: await q('SELECT game, score, points, created_at FROM challenge_runs WHERE player_id = $1 ORDER BY id'),
    };
  });

  // NDPA: erasure. Votes stay in the election chain but lose the link to you.
  app.delete('/api/me', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    if ((req.body as { confirm?: string } | null)?.confirm !== 'DELETE') return reply.code(400).send({ error: 'confirm_with_DELETE' });
    await db.tx(async (t) => {
      await t.query('UPDATE gigs SET status = \'removed\' WHERE poster = $1', [a.id]);
      await t.query('DELETE FROM players WHERE id = $1', [a.id]);
    });
    return { ok: true, deleted: true };
  });

  // Opt-in, anonymous telemetry and crash reports: a random per-install session id, whitelisted
  // event names, small numeric/short-string props. No account id, no location, no device ids.
  const recent = new Map<string, number[]>();
  app.post('/api/telemetry', { bodyLimit: 32 * 1024 }, async (req, reply) => {
    reply.header('cache-control', 'no-store');
    if (!(await flags.get<boolean>('telemetry_enabled'))) return { ok: true, dropped: true };
    const now = Date.now();
    const times = (recent.get(req.ip) ?? []).filter((t) => now - t < 60_000);
    if (times.length >= 12) return reply.code(429).send({ error: 'slow_down' });
    times.push(now);
    recent.set(req.ip, times);
    const b = (req.body ?? {}) as { session?: unknown; version?: unknown; platform?: unknown; events?: unknown; crashes?: unknown };
    const session = typeof b.session === 'string' && /^[a-f0-9]{16,32}$/.test(b.session) ? b.session : null;
    if (!session) return reply.code(400).send({ error: 'bad_session' });
    const version = String(b.version ?? '').slice(0, 20);
    let stored = 0;
    for (const e of (Array.isArray(b.events) ? b.events : []).slice(0, 50) as { name?: unknown; props?: Record<string, unknown> }[]) {
      const name = String(e?.name ?? '');
      if (!ALLOWED_EVENTS.has(name)) continue;
      const props: Record<string, string | number | boolean> = {};
      for (const [k, v] of Object.entries(e.props ?? {}).slice(0, 8)) {
        if (typeof v === 'number' && Number.isFinite(v)) props[k.slice(0, 20)] = v;
        else if (typeof v === 'boolean') props[k.slice(0, 20)] = v;
        else if (typeof v === 'string' && v.length <= 24 && /^[\w.\- ]*$/.test(v)) props[k.slice(0, 20)] = v;
      }
      await db.query('INSERT INTO telemetry_events (session, name, props, version) VALUES ($1, $2, $3, $4)', [session, name, JSON.stringify(props), version]);
      stored++;
    }
    for (const c of (Array.isArray(b.crashes) ? b.crashes : []).slice(0, 10) as { message?: unknown; stack?: unknown }[]) {
      const message = String(c?.message ?? '').slice(0, 300);
      if (!message) continue;
      // Strip anything that looks like a path with a user name in it.
      const clean = (s: string) => s.replace(/[A-Z]:\\Users\\[^\\]+/gi, '<home>').replace(/\/home\/[^/]+|\/Users\/[^/]+/g, '<home>');
      await db.query('INSERT INTO crash_reports (session, version, platform, message, stack) VALUES ($1, $2, $3, $4, $5)', [session, version, String(b.platform ?? '').slice(0, 20), clean(message), clean(String(c.stack ?? '').slice(0, 2000))]);
      stored++;
    }
    return { ok: true, stored };
  });

  // The real-naira lane (proposal F1) stays shut until a company, licensed escrow/payment partner
  // and legal sign-off exist 🔒. The flag exists so nothing can be switched on by accident.
  app.all('/api/real/*', async (_req, reply) => {
    const on = await flags.get<boolean>('real_money_enabled');
    return reply.code(on ? 501 : 403).send({ error: on ? 'provider_not_configured' : 'not_available' });
  });
}
