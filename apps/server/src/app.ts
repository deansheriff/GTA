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
import { Flags } from './flags.ts';
import { AiService, geminiTransport, type Transport } from './ai.ts';
import { NewsService, feedsFromEnv, registerNews } from './news.ts';
import { registerBrains } from './brains.ts';
import { registerChallenges } from './challenges.ts';
import { enforceRetention, registerCompliance } from './compliance.ts';

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
  /** Gemini transport (tests pass a fake). Defaults to the real API when GEMINI_API_KEY is set. */
  ai?: Transport | null;
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
  // M6 AI and news: kill switches, metered Gemini, news ingest and banter, NPC brains.
  const flags = new Flags(store.db);
  const transport = cfg.ai !== undefined ? cfg.ai : process.env.GEMINI_API_KEY ? geminiTransport(process.env.GEMINI_API_KEY) : null;
  const ai = new AiService(store.db, flags, transport);
  const news = new NewsService(store.db, ai, flags);
  const feeds = () => feedsFromEnv(process.env);
  registerNews(app, store.db, flags);
  registerBrains(app, store.db, ai, flags);
  registerAdmin(app, store.db, (id) => rt.hub.forget(id), { flags, ai, news, feeds });
  app.decorate('news', news);
  // M7: skill challenges (prizes behind flags), compliance pages, data rights, telemetry.
  registerChallenges(app, store.db, flags);
  registerCompliance(app, store.db, flags);
  let retention: NodeJS.Timeout | null = null;
  if (process.env.NODE_ENV !== 'test') {
    const run = () => enforceRetention(store.db).catch((e) => app.log.warn({ err: e }, 'retention failed'));
    setTimeout(run, 60_000);
    retention = setInterval(run, 6 * 3600_000);
  }
  let newsTimer: NodeJS.Timeout | null = null;
  if (process.env.NODE_ENV !== 'test' && feeds().length > 0) {
    const every = Math.max(10, Number(process.env.NEWS_POLL_MINUTES ?? 20)) * 60_000;
    const run = () => news.runOnce(feeds()).then((r) => app.log.info(r, 'news run')).catch((e) => app.log.warn({ err: e }, 'news run failed'));
    setTimeout(run, 15_000);
    newsTimer = setInterval(run, every);
  }
  app.addHook('onClose', async () => {
    if (newsTimer) clearInterval(newsTimer);
    if (retention) clearInterval(retention);
  });
  app.addHook('onClose', async () => {
    rt.stop();
    await store.close();
  });
  return app;
}
