import { buildApp } from './app.ts';

const app = buildApp({
  version: process.env.npm_package_version ?? '0.0.1',
  geminiConfigured: Boolean(process.env.GEMINI_API_KEY),
});

const port = Number(process.env.PORT ?? 8787);
app.listen({ port, host: '0.0.0.0' }).catch((err) => {
  app.log.error(err);
  process.exit(1);
});
