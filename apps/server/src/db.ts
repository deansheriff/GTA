import pg from 'pg';

/**
 * One SQL dialect everywhere: PostgreSQL in production (Coolify), PGlite (embedded Postgres in
 * WASM) for development and tests. Feature modules only see this interface.
 */
export interface Db {
  query<T = Record<string, unknown>>(sql: string, params?: unknown[]): Promise<{ rows: T[]; rowCount: number }>;
  /** Run `fn` in a transaction; it commits if `fn` resolves and rolls back if it throws. */
  tx<T>(fn: (db: Db) => Promise<T>): Promise<T>;
  close(): Promise<void>;
}

export class PgDb implements Db {
  private pool: pg.Pool;

  constructor(pool: pg.Pool) {
    this.pool = pool;
  }

  static fromConfig(config: pg.PoolConfig): PgDb {
    return new PgDb(new pg.Pool({ max: 10, ...config }));
  }

  async query<T>(sql: string, params: unknown[] = []) {
    const r = await this.pool.query(sql, params);
    return { rows: r.rows as T[], rowCount: r.rowCount ?? 0 };
  }

  async tx<T>(fn: (db: Db) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    const inner: Db = {
      query: async <R>(sql: string, params: unknown[] = []) => {
        const r = await client.query(sql, params);
        return { rows: r.rows as R[], rowCount: r.rowCount ?? 0 };
      },
      tx: (f) => f(inner),
      close: async () => {},
    };
    try {
      await client.query('BEGIN');
      const out = await fn(inner);
      await client.query('COMMIT');
      return out;
    } catch (e) {
      await client.query('ROLLBACK').catch(() => {});
      throw e;
    } finally {
      client.release();
    }
  }

  async close() {
    await this.pool.end();
  }
}

type Lite = {
  query<T>(sql: string, params?: unknown[]): Promise<{ rows: T[]; affectedRows?: number }>;
  transaction<T>(fn: (tx: { query<R>(sql: string, params?: unknown[]): Promise<{ rows: R[]; affectedRows?: number }> }) => Promise<T>): Promise<T>;
  close(): Promise<void>;
};

export class LiteDb implements Db {
  private lite: Lite;

  private constructor(lite: Lite) {
    this.lite = lite;
  }

  /** In-memory embedded Postgres (dev/tests). Loaded lazily so production never imports it. */
  static async create(): Promise<LiteDb> {
    const { PGlite } = await import('@electric-sql/pglite');
    return new LiteDb(new PGlite() as unknown as Lite);
  }

  async query<T>(sql: string, params: unknown[] = []) {
    const r = await this.lite.query<T>(sql, params);
    return { rows: r.rows, rowCount: r.affectedRows || r.rows.length };
  }

  tx<T>(fn: (db: Db) => Promise<T>): Promise<T> {
    return this.lite.transaction(async (t) => {
      const inner: Db = {
        query: async <R>(sql: string, params: unknown[] = []) => {
          const r = await t.query<R>(sql, params);
          return { rows: r.rows, rowCount: r.affectedRows || r.rows.length };
        },
        tx: (f) => f(inner),
        close: async () => {},
      };
      return fn(inner);
    });
  }

  async close() {
    await this.lite.close();
  }
}
