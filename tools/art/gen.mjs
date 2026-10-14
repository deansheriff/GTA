#!/usr/bin/env node
/**
 * Generates painted game art with OpenAI GPT Image (default) or Gemini image models (decision D-004).
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
const OPENAI_KEY = process.env.OPENAI_API_KEY;
const BUDGET = Number(process.env.ART_BUDGET_USD ?? 10);
const LEDGER = 'art-src/spend-ledger.json';
const RAW = 'art-src/raw';

// OpenAI GPT Image token prices (USD per 1M), developers.openai.com/api/docs/pricing, 2026-10-14.
// Actual cost is computed from the usage the API returns; ESTIMATE is only for the pre-call budget check.
const OPENAI_RATES = {
  'gpt-image-2.5-flare': { text: 5, image: 8, out: 30 },
  'gpt-image-2.5-sunburst': { text: 5, image: 8, out: 30 },
  'gpt-image-2': { text: 5, image: 8, out: 30 },
  'gpt-image-1-mini': { text: 2, image: 2.5, out: 8 },
};
const OPENAI_ESTIMATE = { low: 0.02, medium: 0.07, high: 0.25, auto: 0.25 };

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

async function openaiGenerate(a) {
  const model = a.model ?? spec.model ?? 'gpt-image-2.5-flare';
  const quality = a.quality ?? spec.quality ?? 'medium';
  const est = OPENAI_ESTIMATE[quality] * (a.n ?? 1) * (a.size && a.size !== '1024x1024' ? 1.5 : 1);
  if (spent() + est > BUDGET) {
    console.error(`✗ Budget stop: spent ~$${spent().toFixed(2)} of $${BUDGET}; ${a.name} would add ~$${est.toFixed(2)}.`);
    process.exit(2);
  }
  const prompt = [spec.stylePrefix, a.prompt, spec.styleSuffix].filter(Boolean).join('\n\n');
  const common = { model, prompt, size: a.size ?? '1024x1024', quality, background: a.background ?? 'transparent', output_format: 'png', n: a.n ?? 1 };
  process.stdout.write(`→ ${a.name} (${model}, ${common.size}, ${quality}, ${common.background}${a.refs?.length ? ', refs ' + a.refs.length : ''}) ... `);
  const t0 = Date.now();
  let res;
  if (a.refs?.length) {
    const form = new FormData();
    for (const [k, v] of Object.entries(common)) form.append(k, String(v));
    for (const ref of a.refs) form.append('image[]', new Blob([readFileSync(ref)], { type: 'image/png' }), ref.split('/').pop());
    res = await fetch('https://api.openai.com/v1/images/edits', { method: 'POST', headers: { authorization: `Bearer ${OPENAI_KEY}` }, body: form });
  } else {
    res = await fetch('https://api.openai.com/v1/images/generations', { method: 'POST', headers: { authorization: `Bearer ${OPENAI_KEY}`, 'content-type': 'application/json' }, body: JSON.stringify(common) });
  }
  const json = await res.json().catch(() => ({}));
  const u = json.usage ?? {};
  const r = OPENAI_RATES[model] ?? OPENAI_RATES['gpt-image-2'];
  const textIn = u.input_tokens_details?.text_tokens ?? u.input_tokens ?? 0;
  const imageIn = u.input_tokens_details?.image_tokens ?? 0;
  const cost = res.ok ? (textIn * r.text + imageIn * r.image + (u.output_tokens ?? 0) * r.out) / 1e6 : 0;
  const images = (json.data ?? []).filter((d) => d.b64_json);
  ledger.calls.push({ at: new Date().toISOString(), provider: 'openai', asset: a.name, model, size: common.size, quality, background: common.background, ok: res.ok && images.length > 0, http: res.status, estUsd: Number(cost.toFixed(4)), seconds: Math.round((Date.now() - t0) / 1000), usage: u, prompt: a.prompt, refs: a.refs ?? [] });
  writeFileSync(LEDGER, JSON.stringify(ledger, null, 2) + '\n');
  if (!res.ok || images.length === 0) {
    console.log(`FAILED (http ${res.status}) ${JSON.stringify(json.error ?? json).slice(0, 600)}`);
    return;
  }
  images.forEach((img, i) => {
    const file = join(RAW, `${a.name}${images.length > 1 ? `-${i}` : ''}.png`);
    writeFileSync(file, Buffer.from(img.b64_json, 'base64'));
    console.log(`ok → ${file} ($${cost.toFixed(3)})`);
  });
  console.log(`   spent so far $${spent().toFixed(2)} / $${BUDGET}`);
}

const assets = spec.assets.filter((a) => only.length === 0 || only.includes(a.name));
for (const a of assets) {
  if ((a.provider ?? spec.provider ?? 'openai') === 'openai') {
    if (!OPENAI_KEY) { console.error('OPENAI_API_KEY missing (put it in .env)'); process.exit(1); }
    await openaiGenerate(a);
    continue;
  }
  if (!KEY) { console.error('GEMINI_API_KEY missing (put it in .env)'); process.exit(1); }
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
