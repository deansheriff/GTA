#!/usr/bin/env node
/**
 * Fails the build if the client exceeds the data budgets in packages/shared/src/budgets.ts.
 * Measures gzip size (what a phone actually downloads; Brotli is smaller still).
 * Usage: node tools/check-budget.mjs apps/client/dist
 */
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, extname } from 'node:path';
import { gzipSync } from 'node:zlib';

const KB = 1024, MB = 1024 * KB;
// Keep in sync with packages/shared/src/budgets.ts.
const BUDGETS = { initialJsGzip: 600 * KB, firstInstallLow: 3 * MB };

const dist = process.argv[2] ?? 'apps/client/dist';
const files = [];
(function walk(dir) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p);
    else if (!name.endsWith('.map')) files.push(p);
  }
})(dist);

const fmt = (n) => (n < MB ? `${(n / KB).toFixed(1)} KB` : `${(n / MB).toFixed(2)} MB`);
let js = 0, total = 0;
const rows = files.map((f) => {
  const gz = gzipSync(readFileSync(f), { level: 9 }).length;
  total += gz;
  if (['.js', '.mjs'].includes(extname(f)) && !/sw\.js|workbox/.test(f)) js += gz;
  return [relative(dist, f), gz];
}).sort((a, b) => b[1] - a[1]);

for (const [f, gz] of rows) console.log(`${fmt(gz).padStart(10)}  ${f}`);
console.log(`\nApp JS (gzip): ${fmt(js)} / budget ${fmt(BUDGETS.initialJsGzip)}`);
console.log(`First install (gzip): ${fmt(total)} / budget ${fmt(BUDGETS.firstInstallLow)}`);

let failed = false;
if (js > BUDGETS.initialJsGzip) { console.error('✗ App JS over budget'); failed = true; }
if (total > BUDGETS.firstInstallLow) { console.error('✗ First install over budget'); failed = true; }
if (!failed) console.log('✓ Within data budgets');
process.exit(failed ? 1 : 0);
