import Fastify, { type FastifyInstance } from 'fastify';
import websocket from '@fastify/websocket';
import { registerRealtime } from './realtime.ts';
import { memoryStore, type Store } from './store.ts';
import { registerAuth, smsFromEnv, type SmsProvider } from './auth.ts';
import { registerSocial } from './social.ts';
import { registerMarket } from './market.ts';
import { registerProfiles } from './profiles.ts';
import { registerCivic } from './civic.ts';
import { registerAdmin } from './admin.ts';

/**
 * Naija Street Life API + realtime server. Deployed on the owner's Coolify behind Cloudflare
 * (docs/COOLIFY.md). Android clients connect to wss://<game-domain>/ws.
 */
export interface AppConfig {
  version: string;
  /** Whether a Gemini key is configured. The key itself never leaves the server. */
  geminiConfigured: boolean;
  store?: Store;
  /** Comma-separated proxy IPs/CIDRs to trust for client IPs (Coolify/Cloudflare). */
  trustProxy?: string;
  /** SMS delivery for phone OTP; defaults to SMS_PROVIDER from the environment. */
  sms?: SmsProvider | null;
}

export async function buildApp(cfg: AppConfig): Promise<FastifyInstance> {
  const app = Fastify({
    logger: process.env.NODE_ENV !== 'test',
    trustProxy: cfg.trustProxy ? cfg.trustProxy.split(',').map((s) => s.trim()) : false,
  });
  const store = cfg.store ?? (await memoryStore());
  await store.init();
  await app.register(websocket, { options: { maxPayload: 4096 } });

  app.get('/health', async () => ({ ok: true }));
  app.get('/api/health', async (_req, reply) => {
    const db = await store.health();
    reply.header('cache-control', 'no-store');
    if (!db) reply.code(503);
    return { ok: db, db };
  });

  // Small, cacheable, and never polled in a loop (the reference game's polling leak is what we avoid).
  app.get('/api/version', async (_req, reply) => {
    reply.header('cache-control', 'public, max-age=60');
    return { name: 'Naija Street Life', version: cfg.version, protocol: 1 };
  });

  app.get('/api/status', async (_req, reply) => {
    reply.header('cache-control', 'no-store');
    const players = rt.rooms.all().reduce((n, r) => n + r.size, 0);
    return { ai: { gemini: cfg.geminiConfigured ? 'configured' : 'missing' }, players };
  });

  // Cloud saves: the guest token authenticates; a newer revision wins, so two phones can't
  // silently overwrite each other with older progress.
  const MAX_SAVE_BYTES = 256 * 1024;
  const auth = async (req: { headers: Record<string, unknown> }) => {
    const h = String(req.headers.authorization ?? '');
    if (!h.startsWith('Bearer ') || h.length > 300) return null;
    return store.findByToken(h.slice(7));
  };
  app.get('/api/save', async (req, reply) => {
    reply.header('cache-control', 'no-store');
    const player = await auth(req);
    if (!player) return reply.code(401).send({ error: 'unauthorized' });
    const save = await store.getSave(player.id);
    if (!save) return reply.code(404).send({ error: 'no_save' });
    return save;
  });
  app.put('/api/save', { bodyLimit: MAX_SAVE_BYTES }, async (req, reply) => {
    reply.header('cache-control', 'no-store');
    const player = await auth(req);
    if (!player) return reply.code(401).send({ error: 'unauthorized' });
    const body = req.body as { revision?: unknown; data?: unknown } | null;
    const revision = Number(body?.revision);
    if (!Number.isInteger(revision) || revision < 1 || typeof body?.data !== 'object' || body.data === null) {
      return reply.code(400).send({ error: 'bad_save' });
    }
    const res = await store.putSave(player.id, revision, body.data);
    if (!res.ok) return reply.code(409).send({ error: 'stale_revision', revision: res.revision });
    return { ok: true, revision: res.revision };
  });

  const rt = registerRealtime(app, store);
  // M5 online features (accounts/OTP, chat + moderation, gig board, profiles, polls/elections, admin).
  registerAuth(app, store.db, cfg.sms === undefined ? smsFromEnv(process.env) : cfg.sms);
  registerSocial(app, store.db, () => rt.hub);
  registerMarket(app, store.db);
  registerProfiles(app, store.db);
  registerCivic(app, store.db);
  registerAdmin(app, store.db, (id) => rt.hub.forget(id));
  app.addHook('onClose', async () => {
    rt.stop();
    await store.close();
  });
  return app;
}
