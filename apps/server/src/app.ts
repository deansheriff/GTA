import Fastify, { type FastifyInstance } from 'fastify';

/**
 * Naija Street Life API (M0 skeleton). Realtime rooms (Colyseus), auth, saves and the
 * marketplace arrive in M1–M2 per the Phase 3 proposal.
 */
export interface AppConfig {
  version: string;
  /** Whether a Gemini key is configured. The key itself never leaves the server. */
  geminiConfigured: boolean;
}

export function buildApp(cfg: AppConfig): FastifyInstance {
  const app = Fastify({ logger: process.env.NODE_ENV !== 'test' });

  app.get('/health', async () => ({ ok: true }));

  // Small, cacheable, and never polled in a loop (the reference game's polling leak is what we avoid).
  app.get('/api/version', async (_req, reply) => {
    reply.header('cache-control', 'public, max-age=60');
    return { name: 'Naija Street Life', version: cfg.version };
  });

  app.get('/api/status', async () => ({ ai: { gemini: cfg.geminiConfigured ? 'configured' : 'missing' } }));

  return app;
}
