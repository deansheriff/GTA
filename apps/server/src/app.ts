import Fastify, { type FastifyInstance } from 'fastify';
import websocket from '@fastify/websocket';
import { registerRealtime } from './realtime.ts';
import { MemoryStore, type Store } from './store.ts';

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
}

export async function buildApp(cfg: AppConfig): Promise<FastifyInstance> {
  const app = Fastify({
    logger: process.env.NODE_ENV !== 'test',
    trustProxy: cfg.trustProxy ? cfg.trustProxy.split(',').map((s) => s.trim()) : false,
  });
  const store = cfg.store ?? new MemoryStore();
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

  const rt = registerRealtime(app, store);
  app.addHook('onClose', async () => {
    rt.stop();
    await store.close();
  });
  return app;
}
