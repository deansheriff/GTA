import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { LiteDb, PgDb, type Db } from './db.ts';
import { migrate } from './migrations.ts';

/**
 * Player accounts and cloud saves. Guests get a random token once (only its SHA-256 hash is
 * stored); a verified phone (OTP, see auth.ts) upgrades the same account (proposal §7 tiers).
 */
export interface PlayerRecord {
  id: string;
  name: string;
  look: Record<string, unknown>;
}

export interface Store {
  /** The SQL database behind the store; feature modules (chat, gigs, polls…) use it directly. */
  db: Db;
  init(): Promise<void>;
  createGuest(name: string, look: Record<string, unknown>): Promise<{ player: PlayerRecord; token: string }>;
  findByToken(token: string): Promise<PlayerRecord | null>;
  touch(id: string, name: string, look: Record<string, unknown>): Promise<void>;
  getSave(playerId: string): Promise<{ revision: number; data: unknown } | null>;
  /** Stores the save only if `revision` is newer than the stored one. Returns the stored revision. */
  putSave(playerId: string, revision: number, data: unknown): Promise<{ ok: boolean; revision: number }>;
  health(): Promise<boolean>;
  close(): Promise<void>;
}

export const hashToken = (token: string) => createHash('sha256').update(token).digest('hex');
export const newToken = () => randomBytes(32).toString('base64url');

export class SqlStore implements Store {
  db: Db;

  constructor(db: Db) {
    this.db = db;
  }

  async init() {
    await migrate(this.db);
  }

  async createGuest(name: string, look: Record<string, unknown>) {
    const token = newToken();
    const id = randomUUID();
    await this.db.query('INSERT INTO players (id, name, look, token_hash) VALUES ($1, $2, $3, $4)', [id, name, JSON.stringify(look), hashToken(token)]);
    return { player: { id, name, look }, token };
  }

  async findByToken(token: string) {
    const r = await this.db.query<{ id: string; name: string; look: Record<string, unknown> }>('SELECT id, name, look FROM players WHERE token_hash = $1', [hashToken(token)]);
    const row = r.rows[0];
    return row ? { id: row.id, name: row.name, look: row.look } : null;
  }

  async touch(id: string, name: string, look: Record<string, unknown>) {
    await this.db.query('UPDATE players SET name = $2, look = $3, last_seen = now() WHERE id = $1', [id, name, JSON.stringify(look)]);
  }

  async getSave(playerId: string) {
    const r = await this.db.query<{ revision: number; data: unknown }>('SELECT revision, data FROM saves WHERE player_id = $1', [playerId]);
    return r.rows[0] ? { revision: Number(r.rows[0].revision), data: r.rows[0].data } : null;
  }

  async putSave(playerId: string, revision: number, data: unknown) {
    // Atomic "newer revision wins": the update only happens if the stored revision is older.
    const r = await this.db.query(
      `INSERT INTO saves (player_id, revision, data) VALUES ($1, $2, $3)
       ON CONFLICT (player_id) DO UPDATE SET revision = EXCLUDED.revision, data = EXCLUDED.data, updated_at = now()
       WHERE saves.revision < EXCLUDED.revision
       RETURNING revision`,
      [playerId, revision, JSON.stringify(data)],
    );
    if (r.rows.length === 1) return { ok: true, revision };
    const cur = await this.getSave(playerId);
    return { ok: false, revision: cur?.revision ?? 0 };
  }

  async health() {
    try {
      await this.db.query('SELECT 1');
      return true;
    } catch {
      return false;
    }
  }

  async close() {
    await this.db.close();
  }
}

/** Development and tests: the same SQL on an in-memory embedded Postgres. */
export async function memoryStore(): Promise<SqlStore> {
  return new SqlStore(await LiteDb.create());
}

/**
 * Choose the store from the environment. Production refuses to run without PostgreSQL so a
 * misconfigured deploy can't silently lose everyone's progress.
 */
export async function storeFromEnv(env: NodeJS.ProcessEnv): Promise<Store> {
  if (env.PGHOST) {
    return new SqlStore(PgDb.fromConfig({ host: env.PGHOST, port: Number(env.PGPORT ?? 5432), user: env.PGUSER, password: env.PGPASSWORD, database: env.PGDATABASE }));
  }
  if (env.DATABASE_URL) return new SqlStore(PgDb.fromConfig({ connectionString: env.DATABASE_URL }));
  if (env.NODE_ENV === 'production') throw new Error('PostgreSQL is required in production (set PGHOST/PGUSER/PGPASSWORD/PGDATABASE).');
  return memoryStore();
}
