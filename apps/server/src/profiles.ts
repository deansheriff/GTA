import type { FastifyInstance } from 'fastify';
import type { Db } from './db.ts';
import { requireAccount, accountByToken } from './account.ts';
import { checkText } from './moderation.ts';

/**
 * F2 profiles: bio, district, languages, declared real skills, experience, portfolio links,
 * availability and rate, the in-game CV (synced from the save), verified badges and per-section
 * visibility (public / members / only me). Public search needs explicit consent (NDPA, ⚖️).
 */
const SECTIONS = ['bio', 'skills', 'experience', 'portfolio', 'cv', 'rate'] as const;
type Vis = 'public' | 'members' | 'me';
const REAL_SKILLS = ['photography', 'video', 'design', 'catering', 'tutoring', 'delivery', 'driving', 'tailoring', 'music', 'comedy', 'coding', 'hair', 'makeup', 'events'];
const LANGS = ['English', 'Pidgin', 'Yoruba', 'Igbo', 'Hausa', 'Efik', 'Edo', 'Ijaw', 'French'];

function list(v: unknown, max: number): unknown[] {
  return Array.isArray(v) ? v.slice(0, max) : [];
}

export function registerProfiles(app: FastifyInstance, db: Db): void {
  app.put('/api/profile', async (req, reply) => {
    const a = await requireAccount(db, req, reply);
    if (!a) return;
    const b = (req.body ?? {}) as Record<string, unknown>;
    const bio = b.bio ? checkText(b.bio, { verified: a.verified, max: 300 }) : { ok: true as const, text: '' };
    if (!bio.ok) return reply.code(400).send({ error: `bio_${bio.reason}` });
    const skills = list(b.skills, 8)
      .map((s) => s as { skill?: string; level?: number })
      .filter((s) => REAL_SKILLS.includes(String(s.skill)))
      .map((s) => ({ skill: String(s.skill), level: Math.max(1, Math.min(5, Number(s.level) || 1)) }));
    const experience: { title: string; years: number }[] = [];
    for (const e of list(b.experience, 6) as { title?: unknown; years?: unknown }[]) {
      const t = checkText(e.title, { verified: a.verified, max: 80 });
      if (t.ok) experience.push({ title: t.text, years: Math.max(0, Math.min(50, Number(e.years) || 0)) });
    }
    // Portfolio links only from verified members (links are a classic scam vector).
    const portfolio: string[] = [];
    for (const p of list(b.portfolio, 5)) {
      if (!a.verified) break;
      const s = String(p);
      if (/^https:\/\/[\w.-]+\.[a-z]{2,}(\/[\w\-./?=&%#]*)?$/i.test(s) && s.length <= 200 && checkText(s, { verified: true }).ok) portfolio.push(s);
    }
    const languages = list(b.languages, 6).map(String).filter((l) => LANGS.includes(l));
    const visibility: Record<string, Vis> = {};
    const vin = (b.visibility ?? {}) as Record<string, unknown>;
    for (const s of SECTIONS) visibility[s] = (['public', 'members', 'me'] as const).includes(vin[s] as Vis) ? (vin[s] as Vis) : 'members';
    const district = typeof b.district === 'string' ? b.district.slice(0, 30) : '';
    const availability = ['open', 'busy', 'weekends', ''].includes(String(b.availability ?? '')) ? String(b.availability ?? '') : '';
    const rate = typeof b.rate === 'string' ? b.rate.replace(/[^\d₦,\- ]/g, '').slice(0, 30) : '';
    // The in-game CV: skill levels, story progress and hustles, as reported by the save.
    const cvIn = (b.cv ?? {}) as Record<string, unknown>;
    const cv = {
      skills: Object.fromEntries(Object.entries((cvIn.skills ?? {}) as Record<string, unknown>).slice(0, 12).map(([k, v]) => [k.slice(0, 20), Math.max(1, Math.min(10, Number(v) || 1))])),
      missions: Math.max(0, Math.min(40, Number(cvIn.missions) || 0)),
      ending: typeof cvIn.ending === 'string' ? cvIn.ending.slice(0, 1) : null,
      hero: typeof cvIn.hero === 'string' ? cvIn.hero.slice(0, 10) : null,
    };
    const level = Math.max(1, Math.min(60, Object.values(cv.skills).reduce((s, v) => s + Number(v), 0)));
    await db.query(
      `INSERT INTO profiles (player_id, bio, district, languages, skills, experience, portfolio, availability, rate_range, visibility, searchable, game_cv, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, now())
       ON CONFLICT (player_id) DO UPDATE SET bio = EXCLUDED.bio, district = EXCLUDED.district, languages = EXCLUDED.languages,
         skills = EXCLUDED.skills, experience = EXCLUDED.experience, portfolio = EXCLUDED.portfolio, availability = EXCLUDED.availability,
         rate_range = EXCLUDED.rate_range, visibility = EXCLUDED.visibility, searchable = EXCLUDED.searchable, game_cv = EXCLUDED.game_cv, updated_at = now()`,
      [a.id, bio.text, district, JSON.stringify(languages), JSON.stringify(skills), JSON.stringify(experience), JSON.stringify(portfolio), availability, rate, JSON.stringify(visibility), b.searchable === true, JSON.stringify(cv)],
    );
    await db.query('UPDATE players SET level = $2 WHERE id = $1', [a.id, level]);
    return { ok: true, level };
  });

  app.get('/api/profiles/:pid', async (req, reply) => {
    reply.header('cache-control', 'no-store');
    const pid = (req.params as { pid: string }).pid;
    if (!/^[0-9a-f-]{36}$/.test(pid)) return reply.code(400).send({ error: 'bad_player' });
    const h = String(req.headers.authorization ?? '');
    const viewer = h.startsWith('Bearer ') ? await accountByToken(db, h.slice(7)) : null;
    const r = await db.query<Record<string, any>>(
      `SELECT p.id, p.name, p.verified_at, p.level, p.created_at, pr.* FROM players p LEFT JOIN profiles pr ON pr.player_id = p.id WHERE p.id = $1`,
      [pid],
    );
    const row = r.rows[0];
    if (!row) return reply.code(404).send({ error: 'not_found' });
    const me = viewer?.id === pid;
    const vis = (row.visibility ?? {}) as Record<string, Vis>;
    const can = (s: string) => me || (vis[s] ?? 'members') === 'public' || ((vis[s] ?? 'members') === 'members' && viewer !== null);
    // Verified skill badges come from completed gigs, not self-declaration.
    const done = await db.query<{ skill: string; n: string }>(`SELECT g.skill, count(*) AS n FROM gig_assignments ga JOIN gigs g ON g.id = ga.gig_id WHERE ga.worker = $1 AND ga.status = 'done' GROUP BY g.skill`, [pid]);
    const rating = await db.query<{ avg: string | null; n: string }>('SELECT round(avg(stars)::numeric, 1) AS avg, count(*) AS n FROM ratings WHERE ratee = $1', [pid]);
    return {
      pid, name: row.name, level: Number(row.level), verified: row.verified_at !== null, since: row.created_at,
      district: row.district ?? '', languages: row.languages ?? [], availability: row.availability ?? '',
      bio: can('bio') ? row.bio ?? '' : null,
      skills: can('skills') ? row.skills ?? [] : null,
      experience: can('experience') ? row.experience ?? [] : null,
      portfolio: can('portfolio') ? row.portfolio ?? [] : null,
      rate: can('rate') ? row.rate_range ?? '' : null,
      cv: can('cv') ? row.game_cv ?? {} : null,
      gigBadges: Object.fromEntries(done.rows.map((d) => [d.skill, Number(d.n)])),
      rating: rating.rows[0]!.avg === null ? null : Number(rating.rows[0]!.avg), ratings: Number(rating.rows[0]!.n),
      ...(me ? { visibility: vis, searchable: row.searchable ?? false } : {}),
    };
  });

  // Search only lists people who opted in to public search.
  app.get('/api/profiles', async (req, reply) => {
    reply.header('cache-control', 'no-store');
    const q = req.query as { skill?: string; district?: string };
    const params: unknown[] = [];
    let where = 'pr.searchable';
    if (q.skill && REAL_SKILLS.includes(q.skill)) { params.push(JSON.stringify([{ skill: q.skill }])); where += ` AND pr.skills @> $${params.length}::jsonb`; }
    if (q.district && typeof q.district === 'string') { params.push(q.district.slice(0, 30)); where += ` AND pr.district = $${params.length}`; }
    const r = await db.query(`SELECT p.id AS pid, p.name, p.level, p.verified_at IS NOT NULL AS verified, pr.district, pr.availability FROM profiles pr JOIN players p ON p.id = pr.player_id WHERE ${where} ORDER BY p.level DESC LIMIT 30`, params);
    return { people: r.rows };
  });
}
