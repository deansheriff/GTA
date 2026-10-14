import type { Db } from './db.ts';

/**
 * Kill switches and feature flags (proposal F8 §5): global AI, news ingest, banter, live NPC chat,
 * and per-category / per-outlet news blocks. Admins flip them in the console; reads are cached
 * for a few seconds so hot paths don't hit the database.
 */
export const DEFAULT_FLAGS: Record<string, unknown> = {
  ai_enabled: true,
  news_enabled: true,
  banter_enabled: true,
  live_chat_enabled: false, // proposal: live chat ships behind a flag
  news_auto_publish: false, // banter is sampled by a person before it goes live
  blocked_categories: ['politics', 'security', 'tragedy', 'health'],
  blocked_outlets: [] as string[],
  live_chat_daily_cap: 20,
  // M7 (proposal F5 / F1 real lane): all money features stay off until legal sign-off 🔒.
  prizes_enabled: false,
  prize_value_naira: 100,
  prize_weekly_cap_naira: 500,
  prize_pool_naira: 0,
  real_money_enabled: false,
  telemetry_enabled: true,
};

export class Flags {
  private db: Db;
  private cache: { at: number; values: Record<string, unknown> } | null = null;

  constructor(db: Db) {
    this.db = db;
  }

  async all(): Promise<Record<string, unknown>> {
    if (this.cache && Date.now() - this.cache.at < 5000) return this.cache.values;
    const r = await this.db.query<{ key: string; value: unknown }>('SELECT key, value FROM flags');
    const values = { ...DEFAULT_FLAGS };
    for (const row of r.rows) values[row.key] = row.value;
    this.cache = { at: Date.now(), values };
    return values;
  }

  async get<T>(key: string): Promise<T> {
    return (await this.all())[key] as T;
  }

  async set(key: string, value: unknown): Promise<void> {
    if (!(key in DEFAULT_FLAGS)) throw new Error(`unknown flag ${key}`);
    await this.db.query('INSERT INTO flags (key, value, updated_at) VALUES ($1, $2, now()) ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()', [key, JSON.stringify(value)]);
    this.cache = null;
  }
}
