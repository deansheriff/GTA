#!/usr/bin/env node
/**
 * Rebuilds docs/art/PROVENANCE.md from the spend ledger (art-src/spend-ledger.json).
 *   node tools/art/provenance.mjs
 */
import { readFileSync, writeFileSync } from 'node:fs';

const ledger = JSON.parse(readFileSync('art-src/spend-ledger.json', 'utf8'));
const spent = ledger.calls.reduce((a, c) => a + c.estUsd, 0);
const ok = ledger.calls.filter((c) => c.ok);
const rows = ok.map((c) => `| \`${c.asset}\` | ${c.provider ?? 'gemini'} / ${c.model} | ${c.size}${c.quality ? ', ' + c.quality : ''} | ${c.estUsd.toFixed(3)} | ${c.at.slice(0, 16).replace('T', ' ')} |`);

const md = `# Art provenance (Naija Street Life)

Every image in \`game/art/\` was generated for this project. The original outputs are in
\`art-src/raw/\` (git-ignored); \`tools/art/process.mjs\` trims, slices and resizes them.
This file is rebuilt by \`node tools/art/provenance.mjs\`.

**Rules we follow:**
- No assets from The Omins or any other game are used.
- Their screenshots were never given to a generator.
- Style is described in plain terms: hand-painted gouache, ink outlines, top-down 3/4 view.
- The only reference image is our own generated \`style-anchor-yaba\`.
- Every person depicted is a fictional character; no real people, brands or logos.

**Spend:** $${spent.toFixed(2)} of the owner-approved $${ledger.budgetUsd ?? 10} cap (${ok.length} images). The full ledger, with token usage and prompts, is \`art-src/spend-ledger.json\`.

| Asset | Provider / model | Size, quality | Cost (USD) | Generated |
|---|---|---|---|---|
${rows.join('\n')}

## Prompts

Every asset prompt is wrapped with the shared style prefix and suffix in the spec files
(\`tools/art/spec-*.json\`). Per-asset prompts are in those files and in the ledger.

## Edits after generation
- \`panel-splash\` and \`ui-app-icon\`: the generator painted a real car maker's badge on the danfo's
  grille. It was painted out (grille cloned over it) so the game shows no real brands.
`;
writeFileSync('docs/art/PROVENANCE.md', md);
console.log(`PROVENANCE.md: ${ok.length} images, $${spent.toFixed(2)}`);
