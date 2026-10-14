import type { Db } from './db.ts';

/**
 * Ordered schema migrations. Each version runs once (recorded in schema_version), inside an
 * advisory lock so two app instances can't migrate at the same time.
 */
const MIGRATIONS: { v: number; sql: string[] }[] = [
  {
    v: 1,
    sql: [
      `CREATE TABLE IF NOT EXISTS players (
         id uuid PRIMARY KEY,
         name text NOT NULL,
         look jsonb NOT NULL DEFAULT '{}'::jsonb,
         token_hash text NOT NULL UNIQUE,
         created_at timestamptz NOT NULL DEFAULT now(),
         last_seen timestamptz NOT NULL DEFAULT now()
       )`,
      `CREATE TABLE IF NOT EXISTS saves (
         player_id uuid PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
         revision integer NOT NULL,
         data jsonb NOT NULL,
         updated_at timestamptz NOT NULL DEFAULT now()
       )`,
    ],
  },
  {
    // M5: accounts and OTP, chat and moderation, gig board, profiles, polls and elections, admin.
    v: 2,
    sql: [
      `ALTER TABLE players ADD COLUMN IF NOT EXISTS phone_hash text UNIQUE`,
      `ALTER TABLE players ADD COLUMN IF NOT EXISTS phone_tail text`,
      `ALTER TABLE players ADD COLUMN IF NOT EXISTS verified_at timestamptz`,
      `ALTER TABLE players ADD COLUMN IF NOT EXISTS muted_until timestamptz`,
      `ALTER TABLE players ADD COLUMN IF NOT EXISTS banned_until timestamptz`,
      `ALTER TABLE players ADD COLUMN IF NOT EXISTS strikes integer NOT NULL DEFAULT 0`,
      `ALTER TABLE players ADD COLUMN IF NOT EXISTS level integer NOT NULL DEFAULT 1`,
      `CREATE TABLE IF NOT EXISTS otp_codes (
         id bigserial PRIMARY KEY,
         phone_hash text NOT NULL,
         player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
         code_hash text NOT NULL,
         attempts integer NOT NULL DEFAULT 0,
         ip text,
         expires_at timestamptz NOT NULL,
         created_at timestamptz NOT NULL DEFAULT now()
       )`,
      `CREATE INDEX IF NOT EXISTS otp_phone_idx ON otp_codes (phone_hash, created_at)`,
      `CREATE TABLE IF NOT EXISTS chat_messages (
         id bigserial PRIMARY KEY,
         channel text NOT NULL,
         sender uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
         recipient uuid REFERENCES players(id) ON DELETE CASCADE,
         text text NOT NULL,
         hidden boolean NOT NULL DEFAULT false,
         created_at timestamptz NOT NULL DEFAULT now()
       )`,
      `CREATE INDEX IF NOT EXISTS chat_dm_idx ON chat_messages (recipient, created_at)`,
      `CREATE TABLE IF NOT EXISTS blocks (
         player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
         blocked_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
         PRIMARY KEY (player_id, blocked_id)
       )`,
      `CREATE TABLE IF NOT EXISTS reports (
         id bigserial PRIMARY KEY,
         reporter uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
         target_player uuid REFERENCES players(id) ON DELETE CASCADE,
         message_id bigint,
         gig_id bigint,
         reason text NOT NULL,
         context text,
         status text NOT NULL DEFAULT 'open',
         resolution text,
         created_at timestamptz NOT NULL DEFAULT now()
       )`,
      `CREATE TABLE IF NOT EXISTS strikes_log (
         id bigserial PRIMARY KEY,
         player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
         reason text NOT NULL,
         action text NOT NULL,
         by_actor text NOT NULL,
         created_at timestamptz NOT NULL DEFAULT now()
       )`,
      `CREATE TABLE IF NOT EXISTS wallets (
         player_id uuid PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
         balance bigint NOT NULL DEFAULT 0 CHECK (balance >= 0),
         moved_today bigint NOT NULL DEFAULT 0,
         moved_day date NOT NULL DEFAULT CURRENT_DATE
       )`,
      `CREATE TABLE IF NOT EXISTS wallet_ledger (
         id bigserial PRIMARY KEY,
         player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
         delta bigint NOT NULL,
         reason text NOT NULL,
         ref text,
         created_at timestamptz NOT NULL DEFAULT now()
       )`,
      `CREATE TABLE IF NOT EXISTS gigs (
         id bigserial PRIMARY KEY,
         poster uuid REFERENCES players(id) ON DELETE CASCADE,
         npc_name text,
         title text NOT NULL,
         description text NOT NULL,
         skill text NOT NULL,
         district text NOT NULL,
         pay integer NOT NULL CHECK (pay > 0),
         slots integer NOT NULL DEFAULT 1,
         filled integer NOT NULL DEFAULT 0,
         status text NOT NULL DEFAULT 'open',
         created_at timestamptz NOT NULL DEFAULT now(),
         expires_at timestamptz NOT NULL
       )`,
      `CREATE INDEX IF NOT EXISTS gigs_open_idx ON gigs (status, skill, district)`,
      `CREATE TABLE IF NOT EXISTS gig_assignments (
         id bigserial PRIMARY KEY,
         gig_id bigint NOT NULL REFERENCES gigs(id) ON DELETE CASCADE,
         worker uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
         status text NOT NULL DEFAULT 'applied',
         score integer,
         created_at timestamptz NOT NULL DEFAULT now(),
         completed_at timestamptz,
         UNIQUE (gig_id, worker)
       )`,
      `CREATE TABLE IF NOT EXISTS ratings (
         id bigserial PRIMARY KEY,
         gig_id bigint NOT NULL REFERENCES gigs(id) ON DELETE CASCADE,
         rater uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
         ratee uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
         stars integer NOT NULL CHECK (stars BETWEEN 1 AND 5),
         text text,
         created_at timestamptz NOT NULL DEFAULT now(),
         UNIQUE (gig_id, rater, ratee)
       )`,
      `CREATE TABLE IF NOT EXISTS profiles (
         player_id uuid PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
         bio text NOT NULL DEFAULT '',
         district text NOT NULL DEFAULT '',
         languages jsonb NOT NULL DEFAULT '[]'::jsonb,
         skills jsonb NOT NULL DEFAULT '[]'::jsonb,
         experience jsonb NOT NULL DEFAULT '[]'::jsonb,
         portfolio jsonb NOT NULL DEFAULT '[]'::jsonb,
         availability text NOT NULL DEFAULT '',
         rate_range text NOT NULL DEFAULT '',
         visibility jsonb NOT NULL DEFAULT '{}'::jsonb,
         searchable boolean NOT NULL DEFAULT false,
         game_cv jsonb NOT NULL DEFAULT '{}'::jsonb,
         updated_at timestamptz NOT NULL DEFAULT now()
       )`,
      `CREATE TABLE IF NOT EXISTS polls (
         id bigserial PRIMARY KEY,
         question text NOT NULL,
         kind text NOT NULL DEFAULT 'single',
         options jsonb NOT NULL,
         created_by uuid REFERENCES players(id) ON DELETE SET NULL,
         status text NOT NULL DEFAULT 'pending',
         min_turnout integer NOT NULL DEFAULT 0,
         show_results text NOT NULL DEFAULT 'after',
         opens_at timestamptz NOT NULL DEFAULT now(),
         closes_at timestamptz NOT NULL,
         created_at timestamptz NOT NULL DEFAULT now()
       )`,
      `CREATE TABLE IF NOT EXISTS poll_votes (
         poll_id bigint NOT NULL REFERENCES polls(id) ON DELETE CASCADE,
         player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
         choices jsonb NOT NULL,
         created_at timestamptz NOT NULL DEFAULT now(),
         PRIMARY KEY (poll_id, player_id)
       )`,
      `CREATE TABLE IF NOT EXISTS elections (
         id bigserial PRIMARY KEY,
         ward text NOT NULL,
         office text NOT NULL,
         week_start date NOT NULL,
         status text NOT NULL DEFAULT 'open',
         winner bigint,
         policy text,
         npc_votes jsonb NOT NULL DEFAULT '{}'::jsonb,
         flagged boolean NOT NULL DEFAULT false,
         created_at timestamptz NOT NULL DEFAULT now(),
         UNIQUE (ward, office, week_start)
       )`,
      `CREATE TABLE IF NOT EXISTS candidates (
         id bigserial PRIMARY KEY,
         election_id bigint NOT NULL REFERENCES elections(id) ON DELETE CASCADE,
         player_id uuid REFERENCES players(id) ON DELETE CASCADE,
         npc_name text,
         slogan text NOT NULL,
         policy text NOT NULL,
         approved boolean NOT NULL DEFAULT false,
         created_at timestamptz NOT NULL DEFAULT now(),
         UNIQUE (election_id, player_id)
       )`,
      `CREATE TABLE IF NOT EXISTS votes (
         id bigserial PRIMARY KEY,
         election_id bigint NOT NULL REFERENCES elections(id) ON DELETE CASCADE,
         candidate_id bigint NOT NULL REFERENCES candidates(id) ON DELETE CASCADE,
         voter uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
         prev_hash text NOT NULL,
         hash text NOT NULL,
         created_at timestamptz NOT NULL DEFAULT now(),
         UNIQUE (election_id, voter)
       )`,
      `CREATE TABLE IF NOT EXISTS policies (
         ward text NOT NULL,
         policy text NOT NULL,
         election_id bigint REFERENCES elections(id) ON DELETE SET NULL,
         from_ts timestamptz NOT NULL DEFAULT now(),
         until_ts timestamptz NOT NULL
       )`,
      `CREATE TABLE IF NOT EXISTS admin_actions (
         id bigserial PRIMARY KEY,
         actor text NOT NULL,
         action text NOT NULL,
         target text,
         detail jsonb NOT NULL DEFAULT '{}'::jsonb,
         created_at timestamptz NOT NULL DEFAULT now()
       )`,
    ],
  },
];

export async function migrate(db: Db): Promise<number> {
  await db.query('CREATE TABLE IF NOT EXISTS schema_version (version int PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())');
  // One transaction holding a transaction-scoped advisory lock: works with a pool (same connection
  // throughout) and releases itself on commit or rollback.
  return db.tx(async (t) => {
    await t.query('SELECT pg_advisory_xact_lock(424242)');
    const done = new Set((await t.query<{ version: number }>('SELECT version FROM schema_version')).rows.map((r) => Number(r.version)));
    for (const m of MIGRATIONS) {
      if (done.has(m.v)) continue;
      for (const sql of m.sql) await t.query(sql);
      await t.query('INSERT INTO schema_version (version) VALUES ($1) ON CONFLICT DO NOTHING', [m.v]);
    }
    return MIGRATIONS[MIGRATIONS.length - 1]!.v;
  });
}
