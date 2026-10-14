# Naija Street Life

A Nigerian open-world life-sim and comedy-crime game for Android.
Story mode: **"Naija Street Life: Up NEPA!"** Android game, 2D, hand-painted, seen from
above at an angle.

## Status
- **Platform:** Android only, built with **Godot 4.6.3** (decision D-005).
- **Look:** top-down 3/4 camera with painted, ink-outlined art in The Omins' style (D-004),
  AI-painted (GPT Image; see [provenance](docs/art/PROVENANCE.md)).
- **Setting:** a tropical-island Lagos with the real place names: Ikeja, Oshodi, Mushin, Yaba,
  Surulere, Agbado-Ketu, Lagos Island, Ikoyi, Victoria Island, Lekki (D-008). Every business,
  agency and person is fictional.
- **Milestones done** (see the [production plan](docs/PRODUCTION_PLAN.md)):
  - **M0/M1 · open world:** the whole city streams in chunks; traffic drives on the right;
    crowds; the Third Mainland Bridge; day/night; NEPA blackouts; minimap and GPS; 60 fps
  - **M2 · life-sim:** needs, money, shops, danfo/delivery/POS hustles, skills, sleep, phone,
    local + cloud saves
  - **M3 · story:** "Up NEPA!" Prologue and Act 1 (9 missions) with dialogue and portraits,
    painted cutscenes, the owambe hall, chases, six mini-games, three switchable heroes and
    their abilities, named characters on daily routines
  - **Server:** realtime multiplayer rooms per district and cloud saves, deployable to Coolify
- **Next:** M4, Acts 2 and 3 and the four endings.

## Run and test
```powershell
$g = ".tools\godot\Godot_v4.6.3-stable_win64_console.exe"
& $g --path game                                   # play (desktop preview)
& $g --headless --path game --script res://tests/run_tests.gd   # unit tests
& $g --path game -- --story-auto --shots=build/shots   # plays the whole story by itself
& $g --path game -- --demo --shots=build/shots         # free-roam tour + perf numbers
```

## Layout
| Path | What |
|---|---|
| `game/` | Godot project (GDScript): `core/` settings and helpers, `world/` layout, `actors/`, `shaders/`, `ui/`, `tests/` |
| `apps/server/` | TypeScript (Fastify) server: realtime multiplayer (`/ws`), API, PostgreSQL; deploys to Coolify via `compose.yaml` ([guide](docs/COOLIFY.md)) |
| `tools/art/` | Art generator (OpenAI GPT Image, or Gemini) with a spend ledger and $10 budget stop, plus `process.mjs` to slice sprites |
| `scripts/build.ps1` | Tests and debug APK |
| `docs/` | Research, proposal, decisions, story |

## Build
See [docs/BUILD.md](docs/BUILD.md).
```powershell
.\scripts\build.ps1         # tests + debug APK in the build folder
npm run dev:server          # API on http://localhost:8787 (reads GEMINI_API_KEY from .env; never commit .env)
```

## Docs
- [Phase 3 proposal](docs/phase3-proposal.md)
- [Mission list (story deliverable 2)](docs/story/02-mission-list.md)
- [Abilities and progression (story deliverable 3)](docs/story/03-abilities-progression.md)
- [Phase 2 findings report](docs/phase2-findings-report.md)
- [Story Bible: Up NEPA!](docs/story/story-bible.md)
- [Reference game research notes](docs/research/01-reference-game-notes.md)
- [Decision log](docs/decisions.md)
- [Build notes](docs/BUILD.md)
- [Deploy the server on Coolify + Cloudflare](docs/COOLIFY.md)
