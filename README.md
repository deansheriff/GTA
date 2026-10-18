# Naija Street Life: Èkó Ò Ní Bàjẹ́

A 3D open-world crime drama set in Lagos, for Android. Fifteen years after his father was gunned
down in Oshodi motor park, Dayo "Sabi" Balogun, an ex-soldier turned danfo driver, is framed for
a kidnapping ring's crimes. He fights his way from Mushin to Banana Island, and learns who really
gave the order. The story is in [docs/story/eko-oni-baje.md](docs/story/eko-oni-baje.md).

## Status
- **Platform:** Android, Godot 4.6.3 with the Compatibility renderer.
- **World:** the whole of Lagos in 3D, built from the map data. Traffic, townspeople, danfo
  fares, checkpoints, day and night, rain (D-020).
- **Art:** about 60 Meshy models: people, vehicles, buildings and props (see
  [provenance](docs/art/PROVENANCE.md)).
- **Story:** the prologue and Act I's first two missions are playable, and all 27 missions are
  listed. The roadmap is in the [production plan](docs/PRODUCTION_PLAN.md) (D-021).
- **Server:** realtime rooms and cloud saves (`apps/server`). It was built for the retired 2D
  game, and what returns is an open decision.

## Run and test
```powershell
$g = ".tools\godot\Godot_v4.6.3-stable_win64_console.exe"
& $g --path game                                              # play (desktop preview)
& $g --headless --path game --script res://tests/run_tests.gd  # unit tests
& $g --path game -- --shots=build/shots                        # plays the opening missions by itself
node --env-file=.env tools/art/meshy.mjs --status              # 3D asset pipeline (Meshy API)
```

## Layout
| Path | What |
|---|---|
| `game/` | Godot project (GDScript): `world3d/` the 3D game (city, actors, story runner, HUD), `core/` autoloads, `world/` map data, `data/story/eko/` the campaign, `art3d/` Meshy models, `ui/`, `tests/` |
| `apps/server/` | TypeScript (Fastify) server: realtime multiplayer (`/ws`), API, PostgreSQL; deploys to Coolify via `compose.yaml` ([guide](docs/COOLIFY.md)) |
| `tools/art/` | `meshy.mjs` + `meshy-spec.json` (3D models through the Meshy API) and `glb_slim.mjs`; the older 2D image tools |
| `scripts/build.ps1` | Tests and debug APK |
| `docs/` | Research, proposal, decisions, story |

## Build
See [docs/BUILD.md](docs/BUILD.md).
```powershell
.\scripts\build.ps1         # tests + debug APK in the build folder
npm run dev:server          # API on http://localhost:8787 (reads GEMINI_API_KEY from .env; never commit .env)
```

## Docs
- [Story: Èkó Ò Ní Bàjẹ́](docs/story/eko-oni-baje.md)
- [Production plan](docs/PRODUCTION_PLAN.md)
- [Decision log](docs/decisions.md)
- [Art provenance](docs/art/PROVENANCE.md)
- [Build notes](docs/BUILD.md)
- [Deploy the server on Coolify + Cloudflare](docs/COOLIFY.md)
- Earlier research (2D era): [Phase 3 proposal](docs/phase3-proposal.md), [Phase 2 findings](docs/phase2-findings-report.md), [reference game notes](docs/research/01-reference-game-notes.md)
