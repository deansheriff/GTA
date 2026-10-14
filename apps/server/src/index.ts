import { buildApp } from './app.ts';
import { storeFromEnv } from './store.ts';

const app = await buildApp({
  version: process.env.APP_VERSION ?? process.env.npm_package_version ?? '0.1.0',
  geminiConfigured: Boolean(process.env.GEMINI_API_KEY),
  store: await storeFromEnv(process.env),
  trustProxy: process.env.TRUSTED_PROXY_CIDRS,
});

const port = Number(process.env.PORT ?? 8787);
await app.listen({ port, host: process.env.HOST ?? '0.0.0.0' });

for (const sig of ['SIGINT', 'SIGTERM'] as const) {
  process.on(sig, () => {
    app.close().finally(() => process.exit(0));
  });
}
