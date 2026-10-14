# Art provenance (Naija Street Life)

Every image in `game/art/` was generated for this project. The original outputs are in
`art-src/raw/` (git-ignored); `tools/art/process.mjs` trims, slices and resizes them.

**Rules we follow:**
- No assets from The Omins or any other game are used.
- Their screenshots were never given to a generator.
- Style is described in plain terms: hand-painted gouache, ink outlines, top-down 3/4 view.
- The only reference image is our own generated `style-anchor-yaba`.

**Spend:** $0.47 of the owner-approved $10 cap. The full ledger, with token usage, is `art-src/spend-ledger.json`.

| Asset | Provider / model | Size, quality | Cost (USD) | Generated |
|---|---|---|---|---|
| `style-anchor-yaba` | openai / gpt-image-2.5-flare | 1536x1024, medium | 0.012 | 2026-10-14 12:47 |
| `tex-ground-dirt` | openai / gpt-image-2.5-flare | 1024x1024, medium | 0.014 | 2026-10-14 12:48 |
| `tex-ground-grass` | openai / gpt-image-2.5-flare | 1024x1024, medium | 0.014 | 2026-10-14 12:48 |
| `tex-ground-asphalt` | openai / gpt-image-2.5-flare | 1024x1024, medium | 0.014 | 2026-10-14 12:49 |
| `tex-ground-interlock` | openai / gpt-image-2.5-flare | 1024x1024, medium | 0.014 | 2026-10-14 12:49 |
| `bld-canteen` | openai / gpt-image-2.5-flare | 1024x1024, medium | 0.027 | 2026-10-14 12:49 |
| `bld-pos-shop` | openai / gpt-image-2.5-flare | 1024x1024, medium | 0.027 | 2026-10-14 12:50 |
| `bld-bungalow` | openai / gpt-image-2.5-flare | 1536x1024, medium | 0.024 | 2026-10-14 12:50 |
| `bld-two-storey` | openai / gpt-image-2.5-flare | 1536x1024, medium | 0.024 | 2026-10-14 12:50 |
| `bld-provision-store` | openai / gpt-image-2.5-flare | 1024x1024, medium | 0.027 | 2026-10-14 12:51 |
| `prop-sheet-street` | openai / gpt-image-2.5-flare | 1536x1024, medium | 0.024 | 2026-10-14 12:51 |
| `prop-sheet-trees` | openai / gpt-image-2.5-flare | 1536x1024, medium | 0.024 | 2026-10-14 12:51 |
| `veh-danfo-top` | openai / gpt-image-2.5-flare | 1536x1024, medium | 0.024 | 2026-10-14 12:52 |
| `chr-tunde-walk` | openai / gpt-image-2.5-flare | 1536x1024, medium | 0.024 | 2026-10-14 12:52 |
| `chr-pedestrians-a` | openai / gpt-image-2.5-flare | 1536x1024, medium | 0.024 | 2026-10-14 12:52 |
| `chr-pedestrians-b` | openai / gpt-image-2.5-flare | 1536x1024, medium | 0.024 | 2026-10-14 12:53 |
| `tex-ground-sand` | openai / gpt-image-2.5-flare | 1024x1024, medium | 0.014 | 2026-10-14 14:42 |
| `tex-ground-island-grass` | openai / gpt-image-2.5-flare | 1024x1024, medium | 0.014 | 2026-10-14 14:43 |
| `bld-beach-bar` | openai / gpt-image-2.5-flare | 1536x1024, medium | 0.024 | 2026-10-14 14:43 |
| `bld-fisher-hut` | openai / gpt-image-2.5-flare | 1024x1024, medium | 0.027 | 2026-10-14 14:43 |
| `bld-island-cottage` | openai / gpt-image-2.5-flare | 1024x1024, medium | 0.027 | 2026-10-14 14:44 |
| `prop-sheet-island` | openai / gpt-image-2.5-flare | 1536x1024, medium | 0.024 | 2026-10-14 14:44 |

## Shared style prompt

Every asset prompt is wrapped with the shared style prefix and suffix from `tools/art/spec-m0.json` and `tools/art/spec-island.json`.
Per-asset prompts are in those spec files and in the ledger.
