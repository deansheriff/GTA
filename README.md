# Naija Street Life

A Nigerian open-world life-sim and comedy-crime game for Android.
Story mode: **"Naija Street Life: Up NEPA!"** Android game, 2D, hand-painted, seen from
above at an angle.

## Status
- **Platform:** Android only, built with **Godot 4.6.3** (decision D-005).
- **Look:** top-down 3/4 camera with painted, ink-outlined art in The Omins' style (decision D-004).
- **Milestone 0 is in progress.** Playable now, with **placeholder art drawn in code**, in one
  Yaba junction:
  - painted ground, zinc-roofed shops, POS umbrellas, poles and wires, generators, trees
  - walk Tunde
  - drive the danfo "Baba God Dey" in any direction
  - a small crowd of pedestrians
  - night, and NEPA cuts ("UP NEPA!")
  - graphics presets suggested per device
  - runs at 60 fps
  - **multiplayer:** connect to your server (Settings → Online) and see other players walk and drive
- **Next:** painted art generated with Gemini (needs billing enabled on the Gemini API
  project), then Milestone 1, the Prologue.

## Layout
| Path | What |
|---|---|
| `game/` | Godot project (GDScript): `core/` settings and helpers, `world/` layout, `actors/`, `shaders/`, `ui/`, `tests/` |
| `apps/server/` | TypeScript (Fastify) server: realtime multiplayer (`/ws`), API, PostgreSQL; deploys to Coolify via `compose.yaml` ([guide](docs/COOLIFY.md)) |
| `tools/art/` | Gemini art generator with a spend ledger and budget stop |
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
