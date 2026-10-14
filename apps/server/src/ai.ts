import type { Db } from './db.ts';
import type { Flags } from './flags.ts';

/**
 * Gemini on the server only (D-003; the key never reaches the APK). Every call:
 *  - asks for structured JSON against a schema and validates the result in code,
 *  - is metered (tokens and USD) per day and purpose, with a hard daily budget,
 *  - goes through a circuit breaker, and respects the admin "AI off" switch.
 * Callers always have a rules fallback, so the game works with AI off (proposal F6).
 *
 * API: Gemini Interactions API, POST /v1beta/interactions (checked against ai.google.dev, 2026-10-14):
 *   body { model, input, system_instruction, response_format: { type: "text", mime_type: "application/json", schema },
 *          generation_config: { max_output_tokens, thinking_level, temperature } }
 *   reply { steps: [{ type: "model_output", content: [{ type: "text", text }] }], usage: { total_input_tokens, total_output_tokens, total_thought_tokens } }
 */
export interface JsonRequest {
  purpose: string; // e.g. "news.classify", "banter", "brains", "npc.talk"
  system: string;
  input: string;
  schema: Record<string, unknown>;
  maxTokens?: number;
  temperature?: number;
}

export interface Llm {
  json(req: JsonRequest): Promise<unknown>;
}

export class AiUnavailable extends Error {}

const DEFAULT_MODEL = 'gemini-3.1-flash-lite';
// USD per 1M tokens (ai.google.dev pricing, 2026-10-14). Thinking tokens are billed as output.
const PRICES: Record<string, { in: number; out: number }> = {
  'gemini-3.1-flash-lite': { in: 0.25, out: 1.5 },
  'gemini-3.5-flash-lite': { in: 0.25, out: 1.5 },
  'gemini-3.8-flash': { in: 0.75, out: 3.75 },
};

/** Raw transport so tests can substitute a fake model. Returns the JSON text and token usage. */
export type Transport = (body: Record<string, unknown>) => Promise<{ text: string; inTok: number; outTok: number }>;

export function geminiTransport(key: string): Transport {
  return async (body) => {
    const res = await fetch('https://generativelanguage.googleapis.com/v1beta/interactions', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-goog-api-key': key },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(30_000),
    });
    const json = (await res.json().catch(() => ({}))) as Record<string, any>;
    if (!res.ok) throw new Error(`gemini ${res.status}: ${JSON.stringify(json.error ?? json).slice(0, 200)}`);
    const steps: any[] = Array.isArray(json.steps) ? json.steps : [];
    const text = steps
      .filter((s) => s?.type === 'model_output')
      .flatMap((s) => (Array.isArray(s.content) ? s.content : []))
      .filter((c: any) => c?.type === 'text')
      .map((c: any) => String(c.text))
      .join('');
    const u = json.usage ?? {};
    return { text, inTok: Number(u.total_input_tokens ?? 0), outTok: Number(u.total_output_tokens ?? 0) + Number(u.total_thought_tokens ?? 0) };
  };
}

export class AiService implements Llm {
  private db: Db;
  private flags: Flags;
  private transport: Transport | null;
  private model: string;
  private failures = 0;
  private openUntil = 0;

  constructor(db: Db, flags: Flags, transport: Transport | null, model = process.env.GEMINI_MODEL ?? DEFAULT_MODEL) {
    this.db = db;
    this.flags = flags;
    this.transport = transport;
    this.model = model;
  }

  get configured(): boolean {
    return this.transport !== null;
  }

  async spentToday(): Promise<number> {
    const r = await this.db.query<{ usd: string }>('SELECT coalesce(sum(usd), 0) AS usd FROM ai_usage WHERE day = CURRENT_DATE');
    return Number(r.rows[0]?.usd ?? 0);
  }

  async json(req: JsonRequest): Promise<unknown> {
    if (!this.transport) throw new AiUnavailable('no_key');
    if (!(await this.flags.get<boolean>('ai_enabled'))) throw new AiUnavailable('ai_off');
    if (Date.now() < this.openUntil) throw new AiUnavailable('circuit_open');
    const budget = Number(process.env.AI_DAILY_BUDGET_USD ?? 2);
    if ((await this.spentToday()) >= budget) throw new AiUnavailable('budget');
    const body = {
      model: this.model,
      input: req.input,
      system_instruction: req.system,
      response_format: { type: 'text', mime_type: 'application/json', schema: req.schema },
      generation_config: { max_output_tokens: req.maxTokens ?? 600, thinking_level: 'minimal', temperature: req.temperature ?? 0.7 },
    };
    try {
      const r = await this.transport(body);
      const parsed = JSON.parse(r.text) as unknown;
      const p = PRICES[this.model] ?? PRICES[DEFAULT_MODEL]!;
      const usd = (r.inTok * p.in + r.outTok * p.out) / 1e6;
      await this.meter(req.purpose, r.inTok, r.outTok, usd, false);
      this.failures = 0;
      return parsed;
    } catch (e) {
      await this.meter(req.purpose, 0, 0, 0, true);
      // Billing or quota problems won't fix themselves in minutes: back off for an hour.
      if (/gemini (402|429)/.test(String(e))) this.openUntil = Date.now() + 60 * 60_000;
      else if (++this.failures >= 5) {
        this.openUntil = Date.now() + 10 * 60_000; // trip the breaker for 10 minutes
        this.failures = 0;
      }
      throw e;
    }
  }

  private async meter(purpose: string, inTok: number, outTok: number, usd: number, failed: boolean) {
    await this.db.query(
      `INSERT INTO ai_usage (day, purpose, calls, failures, input_tokens, output_tokens, usd) VALUES (CURRENT_DATE, $1, 1, $2, $3, $4, $5)
       ON CONFLICT (day, purpose) DO UPDATE SET calls = ai_usage.calls + 1, failures = ai_usage.failures + EXCLUDED.failures,
         input_tokens = ai_usage.input_tokens + EXCLUDED.input_tokens, output_tokens = ai_usage.output_tokens + EXCLUDED.output_tokens, usd = ai_usage.usd + EXCLUDED.usd`,
      [purpose, failed ? 1 : 0, inTok, outTok, usd],
    );
  }

  /** Cached JSON call: identical keys reuse the stored answer until it expires (archetype decisions). */
  async cached(key: string, ttlMinutes: number, req: JsonRequest): Promise<unknown> {
    const hit = await this.db.query<{ value: unknown }>('SELECT value FROM ai_cache WHERE key = $1 AND expires_at > now()', [key]);
    if (hit.rows[0]) return hit.rows[0].value;
    const value = await this.json(req);
    await this.db.query(
      `INSERT INTO ai_cache (key, value, expires_at) VALUES ($1, $2, now() + ($3 || ' minutes')::interval)
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, expires_at = EXCLUDED.expires_at`,
      [key, JSON.stringify(value), String(ttlMinutes)],
    );
    return value;
  }
}

// ---------- shared guardrails (enforced in code, not just prompts; proposal F8) ----------

/** Words that may appear capitalised without being a person's name. */
const ALLOW = new Set(`Lagos Nigeria Nigerian Nigerians Abuja Ikeja Yaba Lekki Ikoyi Surulere Mushin Oshodi Obalende Ketu Agbado Victoria Island Mainland Third Bridge Eko Naira Super Eagles Falcons Premier League Champions League NPFL Africa African Ghana Kano Port Harcourt Ibadan Enugu Kaduna Benin Warri Jos
I God Monday Tuesday Wednesday Thursday Friday Saturday Sunday January February March April May June July August September October November December Christmas Easter Sallah Ramadan
NEPA PHCN Danfo BRT LASG CBN NNPC NiMet Light Darkness PetroNaija Konfam Gidi Miracle FM Aunty Boss Tunde KC Sule Teacher Chief Mama Oga Baba Madam Abeg Wahala Na Una Dem Dey Make Ehn Ah Oh Wetin Shey Abi Sha O`.split(/\s+/));

/**
 * Heuristic real-person detector: two or more consecutive capitalised words that aren't known
 * places, days, brands of our fiction or Pidgin interjections (e.g. "Bola Adeyemi said").
 * Over-blocks on purpose: a rejected line just falls back to a canned one.
 */
export function mentionsPerson(text: string): boolean {
  // Per sentence, so a capitalised word after "Ehen!" doesn't pair with it across the boundary.
  for (const sentence of text.split(/[.!?…:;"“”]+/)) {
    const words = sentence.replace(/[^\p{L}\s'-]/gu, ' ').split(/\s+/).filter(Boolean);
    let run = 0;
    for (let i = 0; i < words.length; i++) {
      const w = words[i]!;
      const cap = /^\p{Lu}[\p{Ll}'-]+$/u.test(w) && !ALLOW.has(w);
      run = cap ? run + 1 : 0;
      if (run >= 2) return true;
    }
  }
  return /\b(President|Governor|Senator|Minister|Hon\.|Chief Justice|Gov\.|Sen\.)\b/.test(text);
}

const HEDGES = /\b(i hear(d)? say|dem say|na wetin|radio (talk|say)|people dey talk|i read say|news say|word on the street|rumour (get am|say)|i see am for news)\b/i;

/** Every news line is opinion or hearsay, never stated as fact. */
export function hedge(line: string): string {
  const t = line.trim();
  if (HEDGES.test(t)) return t;
  return 'I hear say ' + t.charAt(0).toLowerCase() + t.slice(1);
}
