#!/usr/bin/env node
/**
 * Generates painted game art with Gemini image models (decision D-004).
 *
 *   node --env-file=.env tools/art/gen.mjs <spec.json> [assetName ...]
 *
 * - Every call is logged to art-src/spend-ledger.json with an estimated cost.
 * - Refuses to run past ART_BUDGET_USD (default 10, approved by the owner on 2026-10-14).
 * - Raw outputs go to art-src/raw/ (git-ignored); prompts are logged for docs/art/PROVENANCE.md.
 * - The API key is read from the environment and never printed.
 */
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';

const KEY = process.env.GEMINI_API_KEY;
if (!KEY) { console.error('GEMINI_API_KEY missing (put it in .env)'); process.exit(1); }
const BUDGET = Number(process.env.ART_BUDGET_USD ?? 10);
const LEDGER = 'art-src/spend-ledger.json';
const RAW = 'art-src/raw';

// Conservative per-image estimates (USD) from ai.google.dev pricing, 2026-10-14. Rounded up.
const PRICE = {
  'gemini-nano-banana-2.1': { '1K': 0.04, '2K': 0.08, '4K': 0.16 },
  'gemini-3.1-flash-lite-image': { '1K': 0.04, '2K': 0.08, '4K': 0.16 },
  'gemini-3.1-flash-image': { '1K': 0.07, '2K': 0.14, '4K': 0.28 },
  'gemini-3-pro-image': { '1K': 0.14, '2K': 0.14, '4K': 0.25 },
};

const [specPath, ...only] = process.argv.slice(2);
if (!specPath) { console.error('usage: gen.mjs <spec.json> [assetName ...]'); process.exit(1); }
const spec = JSON.parse(readFileSync(specPath, 'utf8'));
const ledger = existsSync(LEDGER) ? JSON.parse(readFileSync(LEDGER, 'utf8')) : { budgetUsd: BUDGET, calls: [] };
const spent = () => ledger.calls.reduce((a, c) => a + c.estUsd, 0);
mkdirSync(RAW, { recursive: true });

/** Find every base64 image block anywhere in the response (the interactions API nests them in steps). */
function findImages(node, out = []) {
  if (Array.isArray(node)) node.forEach((n) => findImages(n, out));
  else if (node && typeof node === 'object') {
    if ((node.type === 'image' || node.mime_type?.startsWith?.('image/') || node.mimeType?.startsWith?.('image/')) && typeof node.data === 'string') out.push(node);
    else if (node.inlineData?.data) out.push({ data: node.inlineData.data, mime_type: node.inlineData.mimeType });
    else Object.values(node).forEach((v) => findImages(v, out));
  }
  return out;
}

const assets = spec.assets.filter((a) => only.length === 0 || only.includes(a.name));
for (const a of assets) {
  const model = a.model ?? spec.model ?? 'gemini-nano-banana-2.1';
  const size = a.imageSize ?? spec.imageSize ?? '1K';
  const est = PRICE[model]?.[size] ?? 0.3;
  if (spent() + est > BUDGET) {
    console.error(`✗ Budget stop: spent ~$${spent().toFixed(2)} of $${BUDGET}; ${a.name} would add ~$${est}.`);
    process.exit(2);
  }
  const prompt = [spec.stylePrefix, a.prompt, spec.styleSuffix].filter(Boolean).join('\n\n');
  const input = [{ type: 'text', text: prompt }];
  for (const ref of a.refs ?? []) {
    const data = readFileSync(ref).toString('base64');
    input.push({ type: 'image', mime_type: ref.endsWith('.png') ? 'image/png' : ref.endsWith('.webp') ? 'image/webp' : 'image/jpeg', data });
  }
  const body = {
    model,
    input,
    response_format: { type: 'image', mime_type: 'image/jpeg', aspect_ratio: a.aspect ?? '1:1', image_size: size },
  };
  process.stdout.write(`→ ${a.name} (${model}, ${size}, ${a.aspect ?? '1:1'}) ... `);
  const t0 = Date.now();
  const res = await fetch('https://generativelanguage.googleapis.com/v1beta/interactions', {
    method: 'POST',
    headers: { 'x-goog-api-key': KEY, 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  const json = await res.json().catch(() => ({}));
  const images = findImages(json);
  const call = { at: new Date().toISOString(), asset: a.name, model, size, aspect: a.aspect ?? '1:1', ok: res.ok && images.length > 0, http: res.status, estUsd: res.ok ? est : 0, seconds: Math.round((Date.now() - t0) / 1000), usage: json.usage ?? json.usageMetadata ?? null, prompt: a.prompt, refs: a.refs ?? [] };
  ledger.calls.push(call);
  writeFileSync(LEDGER, JSON.stringify(ledger, null, 2) + '\n');
  if (!call.ok) {
    const shape = JSON.stringify(json, (k, v) => (k === 'data' && typeof v === 'string' ? `<${v.length} b64>` : v)).slice(0, 1200);
    console.log(`FAILED (http ${res.status})\n${shape}`);
    continue;
  }
  images.forEach((img, i) => {
    const file = join(RAW, `${a.name}${images.length > 1 ? `-${i}` : ''}.jpg`);
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, Buffer.from(img.data, 'base64'));
    console.log(`ok → ${file}`);
  });
  console.log(`   spent so far ~$${spent().toFixed(2)} / $${BUDGET}`);
}
