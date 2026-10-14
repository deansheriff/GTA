import { createHash, randomBytes, randomUUID } from 'node:crypto';
import pg from 'pg';

/**
 * Player accounts. M0 uses guest accounts: the server issues a random token once, the phone
 * keeps it, and only its SHA-256 hash is stored. Phone/OTP verification arrives with the
 * features that need it (gigs, voting, prizes; proposal §7).
 */
export interface PlayerRecord {
  id: string;
  name: string;
  look: Record<string, unknown>;
}

export interface Store {
  init(): Promise<void>;
  createGuest(name: string, look: Record<string, unknown>): Promise<{ player: PlayerRecord; token: string }>;
  findByToken(token: string): Promise<PlayerRecord | null>;
  touch(id: string, name: string, look: Record<string, unknown>): Promise<void>;
  health(): Promise<boolean>;
  close(): Promise<void>;
}

const hash = (token: string) => createHash('sha256').update(token).digest('hex');
const newToken = () => randomBytes(32).toString('base64url');

export class MemoryStore implements Store {
  private byHash = new Map<string, PlayerRecord>();
  async init() {}
  async createGuest(name: string, look: Record<string, unknown>) {
    const token = newToken();
    const player = { id: randomUUID(), name, look };
    this.byHash.set(hash(token), player);
    return { player, token };
  }
  async findByToken(token: string) {
    return this.byHash.get(hash(token)) ?? null;
  }
  async touch(id: string, name: string, look: Record<string, unknown>) {
    for (const p of this.byHash.values()) if (p.id === id) { p.name = name; p.look = look; }
  }
  async health() { return true; }
  async close() {}
}

const MIGRATIONS = [
  `CREATE TABLE IF NOT EXISTS schema_version (version int PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())`,
  `CREATE TABLE IF NOT EXISTS players (
     id uuid PRIMARY KEY,
     name text NOT NULL,
     look jsonb NOT NULL DEFAULT '{}'::jsonb,
     token_hash text NOT NULL UNIQUE,
     created_at timestamptz NOT NULL DEFAULT now(),
     last_seen timestamptz NOT NULL DEFAULT now()
   )`,
];

export class PgStore implements Store {
  private pool: pg.Pool;

  constructor(config: pg.PoolConfig) {
    this.pool = new pg.Pool({ max: 10, ...config });
  }

  async init() {
    const client = await this.pool.connect();
    try {
      // One app instance migrates at a time.
      await client.query('SELECT pg_advisory_lock(424242)');
      for (const sql of MIGRATIONS) await client.query(sql);
      await client.query('INSERT INTO schema_version (version) VALUES (1) ON CONFLICT DO NOTHING');
    } finally {
      await client.query('SELECT pg_advisory_unlock(424242)').catch(() => {});
      client.release();
    }
  }

  async createGuest(name: string, look: Record<string, unknown>) {
    const token = newToken();
    const id = randomUUID();
    await this.pool.query('INSERT INTO players (id, name, look, token_hash) VALUES ($1, $2, $3, $4)', [id, name, JSON.stringify(look), hash(token)]);
    return { player: { id, name, look }, token };
  }

  async findByToken(token: string) {
    const r = await this.pool.query('SELECT id, name, look FROM players WHERE token_hash = $1', [hash(token)]);
    const row = r.rows[0];
    return row ? { id: row.id as string, name: row.name as string, look: row.look as Record<string, unknown> } : null;
  }

  async touch(id: string, name: string, look: Record<string, unknown>) {
    await this.pool.query('UPDATE players SET name = $2, look = $3, last_seen = now() WHERE id = $1', [id, name, JSON.stringify(look)]);
  }

  async health() {
    try {
      await this.pool.query('SELECT 1');
      return true;
    } catch {
      return false;
    }
  }

  async close() {
    await this.pool.end();
  }
}

/**
 * Choose the store from the environment. Production refuses to run without PostgreSQL so a
 * misconfigured deploy can't silently lose everyone's progress.
 */
export function storeFromEnv(env: NodeJS.ProcessEnv): Store {
  if (env.PGHOST) {
    return new PgStore({ host: env.PGHOST, port: Number(env.PGPORT ?? 5432), user: env.PGUSER, password: env.PGPASSWORD, database: env.PGDATABASE });
  }
  if (env.DATABASE_URL) return new PgStore({ connectionString: env.DATABASE_URL });
  if (env.NODE_ENV === 'production') throw new Error('PostgreSQL is required in production (set PGHOST/PGUSER/PGPASSWORD/PGDATABASE).');
  return new MemoryStore();
}
