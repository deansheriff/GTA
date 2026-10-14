import type { FastifyInstance } from 'fastify';
import type { Db } from './db.ts';
import { AiUnavailable, hedge, mentionsPerson, type AiService } from './ai.ts';
import type { Flags } from './flags.ts';
import { checkText } from './moderation.ts';

/**
 * F7 news service + F8 news banter.
 *
 * Ingest: publisher RSS/Atom feeds chosen by the owner (NEWS_FEEDS="Outlet|https://…/rss,…") ⚖️,
 * headline + link + a short lede only; conditional GET; dedupe by canonical URL, then by title
 * shingles. Stories expire after 72 h.
 * Classify: category + sensitivity flags (rules first; Gemini structured output when available),
 * and a 1–2 sentence neutral summary in our own words (never the article text).
 * Banter: approved, non-sensitive topics become short NPC lines per archetype, always framed as
 * hearsay, checked in code (moderation, real-person detector, length), then reviewed by a person
 * before publishing (unless the owner turns on auto-publish). Story scenes never depend on news.
 */
export const CATEGORIES = ['economy', 'fuel-power', 'transport', 'weather', 'sports', 'entertainment', 'tech', 'politics', 'security', 'health', 'tragedy', 'other'] as const;
export const ARCHETYPES = ['traders', 'drivers', 'students', 'church', 'okada', 'youth'] as const;
const SENSITIVE = ['death_injury', 'elections_politicians', 'religion_ethnicity', 'allegation', 'minors', 'private_person'] as const;

const RULES: [string, RegExp][] = [
  ['tragedy', /\b(kill(ed|s)?|dead|death|dies|died|collapse[sd]?|drown(ed)?|victims?|fire guts|explosion|crash)\b/i],
  ['security', /\b(bandits?|kidnap(ped|pers|ping)?|gunmen|attack(ed)?|terror|robbery|cultists?|police arrest)\b/i],
  ['politics', /\b(election|governor|senat(e|or)|president|minister|assembly|lawmakers?|party|inec|campaign|tribunal|rerun|councillor)\b/i],
  ['health', /\b(cholera|lassa|outbreak|hospital|vaccine|disease|ncdc|malaria)\b/i],
  ['fuel-power', /\b(fuel|petrol|pms|diesel|electricity|power supply|tariff|band a|grid|disco|blackout|outage)\b/i],
  ['transport', /\b(traffic|brt|danfo|keke|okada|road|bridge|rail|airport|flight|ferry|lastma|go-?slow)\b/i],
  ['weather', /\b(rain|flood(ing)?|heat|harmattan|nimet|weather|storm)\b/i],
  ['sports', /\b(super eagles|falcons|league|match|goal|fifa|caf|afcon|football|striker|coach|olympic|athlete)\b/i],
  ['economy', /\b(naira|dollar|inflation|price[sd]?|market|tomato|rice|bank|cbn|economy|salary|wage|tax|budget)\b/i],
  ['entertainment', /\b(nollywood|afrobeats|album|movie|music|concert|award|bbnaija|comedian|film|star)\b/i],
  ['tech', /\b(tech|startup|app|internet|data|telco|mtn|airtel|5g|fintech|ai)\b/i],
];
const SENS_RULES: Record<string, RegExp> = {
  death_injury: RULES[0]![1],
  elections_politicians: RULES[2]![1],
  religion_ethnicity: /\b(church|mosque|muslim|christian|religio|ethnic|tribe|igbo|yoruba|hausa|fulani)\b/i,
  allegation: /\b(alleged(ly)?|accused|arraign(ed)?|court|efcc|icpc|fraud|probe|charged|detained|suspect)\b/i,
  minors: /\b(child(ren)?|pupils?|minors?|schoolgirls?|schoolboys?|teenager|baby)\b/i,
  private_person: /\b(man|woman|resident|trader) (identified as|named)\b/i,
};

export function ruleClassify(title: string, lede: string): { category: string; sensitivity: Record<string, boolean> } {
  const text = `${title} ${lede}`;
  let category = 'other';
  for (const [c, re] of RULES) if (re.test(text)) { category = c; break; }
  const sensitivity: Record<string, boolean> = {};
  for (const k of SENSITIVE) sensitivity[k] = SENS_RULES[k]!.test(text);
  return { category, sensitivity };
}

// ---------- feeds ----------

export function parseFeed(xml: string): { title: string; link: string; lede: string; published: string | null }[] {
  const decode = (s: string) => s.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1').replace(/<[^>]+>/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#0?39;|&apos;/g, "'").replace(/&#8217;/g, '’').replace(/&#8216;/g, '‘').replace(/&#82(20|21);/g, '"').replace(/\s+/g, ' ').trim();
  const tag = (block: string, name: string) => {
    const m = block.match(new RegExp(`<${name}[^>]*>([\\s\\S]*?)</${name}>`, 'i'));
    return m ? decode(m[1]!) : '';
  };
  const out: { title: string; link: string; lede: string; published: string | null }[] = [];
  for (const m of xml.matchAll(/<(item|entry)\b[\s\S]*?<\/\1>/gi)) {
    const b = m[0];
    let link = tag(b, 'link');
    if (!link) link = b.match(/<link[^>]*href="([^"]+)"/i)?.[1] ?? '';
    const title = tag(b, 'title');
    if (!title || !/^https?:\/\//.test(link)) continue;
    out.push({ title: title.slice(0, 200), link, lede: (tag(b, 'description') || tag(b, 'summary')).slice(0, 300), published: tag(b, 'pubDate') || tag(b, 'published') || tag(b, 'updated') || null });
  }
  return out;
}

export function canonicalUrl(u: string): string {
  try {
    const url = new URL(u);
    for (const k of [...url.searchParams.keys()]) if (/^(utm_|fbclid|gclid|ref)/.test(k)) url.searchParams.delete(k);
    url.hash = '';
    url.hostname = url.hostname.toLowerCase().replace(/^www\./, '');
    return url.toString().replace(/\/$/, '');
  } catch {
    return u;
  }
}

function shingles(title: string): Set<string> {
  const w = title.toLowerCase().replace(/[^\p{L}\p{N}\s]/gu, ' ').split(/\s+/).filter((x) => x.length > 2);
  const s = new Set<string>();
  for (let i = 0; i + 1 < w.length; i++) s.add(`${w[i]} ${w[i + 1]}`);
  return s;
}

export function similar(a: string, b: string): number {
  const A = shingles(a);
  const B = shingles(b);
  if (A.size === 0 || B.size === 0) return 0;
  let inter = 0;
  for (const x of A) if (B.has(x)) inter++;
  return inter / (A.size + B.size - inter);
}

const etags = new Map<string, string>();

export function feedsFromEnv(env: NodeJS.ProcessEnv): { outlet: string; url: string }[] {
  return (env.NEWS_FEEDS ?? '').split(',').map((s) => s.trim()).filter(Boolean).map((s) => {
    const [outlet, url] = s.includes('|') ? s.split('|') : [new URL(s).hostname, s];
    return { outlet: outlet!.trim(), url: url!.trim() };
  });
}

// ---------- pipeline ----------

export class NewsService {
  private db: Db;
  private ai: AiService;
  private flags: Flags;
  fetcher: (url: string, etag?: string) => Promise<{ status: number; body: string; etag?: string }>;

  constructor(db: Db, ai: AiService, flags: Flags) {
    this.db = db;
    this.ai = ai;
    this.flags = flags;
    this.fetcher = async (url, etag) => {
      const res = await fetch(url, { headers: { 'user-agent': 'NaijaStreetLife/1.0 (+headline-and-link news cards)', ...(etag ? { 'if-none-match': etag } : {}) }, signal: AbortSignal.timeout(15_000) });
      return { status: res.status, body: res.status === 200 ? await res.text() : '', etag: res.headers.get('etag') ?? undefined };
    };
  }

  /** Fetch every feed and store new, non-duplicate stories. Returns how many were added. */
  async ingest(feeds: { outlet: string; url: string }[]): Promise<number> {
    if (!(await this.flags.get<boolean>('news_enabled'))) return 0;
    const blockedOutlets = await this.flags.get<string[]>('blocked_outlets');
    let added = 0;
    const recent = await this.db.query<{ id: string; title: string }>(`SELECT id, title FROM news_items WHERE created_at > now() - interval '72 hours' AND duplicate_of IS NULL`);
    for (const f of feeds) {
      if (blockedOutlets.includes(f.outlet)) continue;
      let res;
      try {
        res = await this.fetcher(f.url, etags.get(f.url));
      } catch {
        continue;
      }
      if (res.status !== 200) continue;
      if (res.etag) etags.set(f.url, res.etag);
      for (const item of parseFeed(res.body).slice(0, 30)) {
        const url = canonicalUrl(item.link);
        const dup = recent.rows.find((r) => similar(r.title, item.title) >= 0.5);
        const published = item.published && !Number.isNaN(Date.parse(item.published)) ? new Date(item.published) : null;
        const r = await this.db.query<{ id: string }>(
          `INSERT INTO news_items (outlet, url, title, lede, published_at, duplicate_of, status, expires_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, now() + interval '72 hours') ON CONFLICT (url) DO NOTHING RETURNING id`,
          [f.outlet, url, item.title, item.lede, published, dup ? dup.id : null, dup ? 'duplicate' : 'new'],
        );
        if (r.rows[0] && !dup) {
          added++;
          recent.rows.push({ id: r.rows[0].id, title: item.title });
        }
      }
    }
    return added;
  }

  /** Category, sensitivity and a neutral summary for every new story. */
  async classifyNew(limit = 20): Promise<number> {
    const rows = await this.db.query<{ id: string; title: string; lede: string }>(`SELECT id, title, lede FROM news_items WHERE status = 'new' ORDER BY id LIMIT $1`, [limit]);
    const blocked = await this.flags.get<string[]>('blocked_categories');
    for (const n of rows.rows) {
      let { category, sensitivity } = ruleClassify(n.title, n.lede);
      let summary: string | null = null;
      try {
        const out = (await this.ai.json({
          purpose: 'news.classify',
          system: 'You classify Nigerian news headlines for a video game. You only see the headline and a short lede. Answer in JSON. The summary must be neutral, 1-2 short sentences, in your own words, and must NOT name any person (use roles like "the government", "a minister", "the club").',
          input: JSON.stringify({ headline: n.title, lede: n.lede.slice(0, 300) }),
          schema: {
            type: 'object',
            properties: {
              category: { type: 'string', enum: [...CATEGORIES] },
              sensitivity: { type: 'object', properties: Object.fromEntries(SENSITIVE.map((k) => [k, { type: 'boolean' }])), required: [...SENSITIVE] },
              summary: { type: 'string' },
            },
            required: ['category', 'sensitivity', 'summary'],
          },
          maxTokens: 300,
          temperature: 0.2,
        })) as { category?: string; sensitivity?: Record<string, boolean>; summary?: string };
        if (out.category && (CATEGORIES as readonly string[]).includes(out.category)) category = out.category;
        // Sensitivity: either signal is enough (rules OR model) to treat a story as sensitive.
        for (const k of SENSITIVE) sensitivity[k] = Boolean(sensitivity[k] || out.sensitivity?.[k]);
        if (typeof out.summary === 'string' && out.summary.length <= 300 && !mentionsPerson(out.summary) && checkText(out.summary, { verified: true, max: 300 }).ok) summary = out.summary;
      } catch (e) {
        if (!(e instanceof AiUnavailable)) console.warn('news classify failed', String(e).slice(0, 120));
      }
      const sensitive = Object.values(sensitivity).some(Boolean);
      const eligible = !sensitive && !blocked.includes(category) && category !== 'other';
      await this.db.query(`UPDATE news_items SET category = $2, sensitivity = $3, summary = $4, eligible = $5, status = 'classified' WHERE id = $1`, [n.id, category, JSON.stringify(sensitivity), summary, eligible]);
    }
    return rows.rows.length;
  }

  /** NPC lines for eligible stories that don't have any yet. AI when available, templates otherwise. */
  async generateBanter(limit = 5): Promise<number> {
    if (!(await this.flags.get<boolean>('banter_enabled'))) return 0;
    const auto = await this.flags.get<boolean>('news_auto_publish');
    const rows = await this.db.query<{ id: string; title: string; summary: string | null; category: string }>(
      `SELECT n.id, n.title, n.summary, n.category FROM news_items n
        WHERE n.status = 'classified' AND n.eligible AND n.expires_at > now()
          AND NOT EXISTS (SELECT 1 FROM banter_lines b WHERE b.news_id = n.id) ORDER BY n.id DESC LIMIT $1`,
      [limit],
    );
    let made = 0;
    for (const n of rows.rows) {
      let lines: { archetype: string; text: string; source: string }[] = [];
      try {
        const out = (await this.ai.json({
          purpose: 'banter',
          system: `You write short ambient lines for NPCs in a comedy game set in Lagos, Nigeria, in light Nigerian Pidgin English.
Rules you must follow:
- React to the TOPIC only, as opinion or hearsay ("I hear say…", "Dem say…", "Radio talk say…"). Never state it as fact.
- Never name or quote any real person, party or politician. Use roles ("government", "the club", "dem").
- No insults about any group, no tragedy jokes, no advice about elections.
- Each line at most 120 characters. Funny, warm, everyday.`,
          input: JSON.stringify({ topic: n.summary ?? n.title, category: n.category, archetypes: ARCHETYPES, lines_per_archetype: 2 }),
          schema: { type: 'object', properties: { lines: { type: 'array', items: { type: 'object', properties: { archetype: { type: 'string', enum: [...ARCHETYPES] }, text: { type: 'string' } }, required: ['archetype', 'text'] } } }, required: ['lines'] },
          maxTokens: 900,
          temperature: 0.9,
        })) as { lines?: { archetype: string; text: string }[] };
        lines = (out.lines ?? []).map((l) => ({ archetype: l.archetype, text: String(l.text ?? ''), source: 'ai' }));
      } catch (e) {
        if (!(e instanceof AiUnavailable)) console.warn('banter generation failed', String(e).slice(0, 120));
        lines = templateBanter(n.category);
      }
      for (const l of lines) {
        if (!(ARCHETYPES as readonly string[]).includes(l.archetype)) continue;
        const text = hedge(l.text);
        // Guardrails in code: moderation, length, no real people, no source-headline names.
        if (text.length > 140 || mentionsPerson(text) || !checkText(text, { verified: false, max: 140 }).ok) continue;
        await this.db.query('INSERT INTO banter_lines (news_id, archetype, text, source, status) VALUES ($1, $2, $3, $4, $5)', [n.id, l.archetype, text, l.source, auto ? 'approved' : 'pending']);
        made++;
      }
    }
    return made;
  }

  async runOnce(feeds: { outlet: string; url: string }[]): Promise<{ added: number; classified: number; lines: number }> {
    await this.db.query(`DELETE FROM news_items WHERE expires_at < now() - interval '7 days'`); // keep an audit week after expiry
    const added = await this.ingest(feeds);
    const classified = await this.classifyNew();
    const lines = await this.generateBanter();
    return { added, classified, lines };
  }
}

/** Rules-only fallback lines per category (no headline content; the source link still travels). */
function templateBanter(category: string): { archetype: string; text: string; source: string }[] {
  const T: Record<string, string[]> = {
    'fuel-power': ['I hear say fuel and light matter don enter news again. This country sha!', 'Radio talk say power matter dey change. Make we see am first.'],
    transport: ['I hear say road matter dey for news. Go-slow no go kill us.', 'Dem say transport wahala dey change. Danfo still dey run sha.'],
    economy: ['I hear say price matter don enter news. Market go loud today.', 'Dem say money matter dey shake. Tomato no dey wait for anybody.'],
    weather: ['Radio talk say weather go do anyhow. Carry umbrella o.', 'I hear say rain fit fall well well. Gutter, behave yourself.'],
    sports: ['I hear say football matter dey hot for news. Una don see am?', 'Dem say match result don come out. Viewing centre go full tonight.'],
    entertainment: ['I hear say one new song don drop. Owambe DJs go happy.', 'Dem say entertainment people don cause another gist.'],
    tech: ['I hear say new app matter dey trend. Data go finish again.', 'Radio talk say tech people don do another thing. Network sef dey learn.'],
  };
  const lines = T[category] ?? T.economy!;
  return ARCHETYPES.map((a, i) => ({ archetype: a, text: lines[i % lines.length]!, source: 'template' }));
}

export function registerNews(app: FastifyInstance, db: Db, flags: Flags): void {
  // Kill switches apply at read time too, so flipping one takes effect within seconds.
  const blocked = async () => ({ outlets: await flags.get<string[]>('blocked_outlets'), cats: await flags.get<string[]>('blocked_categories'), news: await flags.get<boolean>('news_enabled'), banter: await flags.get<boolean>('banter_enabled') });

  // Approved topic cards: neutral summary + source attribution (the UI shows "via Outlet").
  app.get('/api/news/topics', async (_req, reply) => {
    reply.header('cache-control', 'public, max-age=300');
    const k = await blocked();
    if (!k.news) return { topics: [] };
    const r = await db.query(
      `SELECT id, outlet, url, category, coalesce(summary, title) AS summary, coalesce(published_at, created_at) AS at
         FROM news_items WHERE status = 'classified' AND eligible AND expires_at > now()
          AND NOT (outlet = ANY($1::text[])) AND NOT (category = ANY($2::text[])) ORDER BY id DESC LIMIT 20`,
      [k.outlets, k.cats],
    );
    return { topics: r.rows };
  });

  // Published banter for the client's line banks, each with its source.
  app.get('/api/banter', async (_req, reply) => {
    reply.header('cache-control', 'public, max-age=300');
    const k = await blocked();
    if (!k.news || !k.banter) return { lines: [] };
    const r = await db.query(
      `SELECT b.id, b.archetype, b.text, n.outlet, n.url, coalesce(n.published_at, n.created_at) AS at
         FROM banter_lines b JOIN news_items n ON n.id = b.news_id
        WHERE b.status = 'approved' AND n.eligible AND n.expires_at > now()
          AND NOT (n.outlet = ANY($1::text[])) AND NOT (n.category = ANY($2::text[])) ORDER BY b.id DESC LIMIT 120`,
      [k.outlets, k.cats],
    );
    return { lines: r.rows };
  });
}
