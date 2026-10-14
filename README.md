# Naija Street Life

A Nigerian open-world life-sim and comedy-crime game for web and mobile web.
Story mode: **"Naija Street Life: Up NEPA!"** The art is 2D and hand-painted, seen
from above at an angle.

## Status
- **Milestone 0 (foundations and art test) is in progress.** The Phase 3 proposal was approved on 2026-10-14.
- What's playable: one painted Yaba junction (placeholder art drawn in code). You can:
  - walk Tunde
  - drive the danfo "Baba God Dey"
  - switch to night and back
  - trigger NEPA cuts ("UP NEPA!")
  - change graphics settings (auto-suggested per device)
  - watch the data meter

## Run it
```bash
npm install
npm run dev          # client on http://localhost:5173 (also on your LAN for phone testing)
npm run dev:server   # API on http://localhost:8787 (reads GEMINI_API_KEY from .env; never commit .env)
npm test             # unit tests
npm run build && npm run budget   # production build + data-budget check
```

## Docs
- [Phase 3 proposal](docs/phase3-proposal.md)
- [Mission list (story deliverable 2)](docs/story/02-mission-list.md)
- [Abilities and progression (story deliverable 3)](docs/story/03-abilities-progression.md)
- [Phase 2 findings report](docs/phase2-findings-report.md)
- [Story Bible: Up NEPA!](docs/story/story-bible.md)
- [Reference game research notes](docs/research/01-reference-game-notes.md)
- [Decision log](docs/decisions.md)
