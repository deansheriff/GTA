# Naija Street Life — Production Plan

The source of truth for build progress (owner instruction, D-008): build continuously, mark
milestones, make no APK until the game is done, then do one release build.

**Legend:** ✅ done · 🔨 in progress · ⬜ to do · 🔒 blocked on the owner (decision, money, legal or accounts)

## M0 — Foundations ✅
- ✅ Godot 4.6 Android project, Compatibility renderer, settings, HUD, joystick
- ✅ AI art pipeline (GPT Image), painted terrain, buildings, props, characters
- ✅ Multiplayer server (Fastify + WebSockets + Postgres), Coolify/Cloudflare deploy, CI

## M1 — The world: tropical-island Lagos ✅ (2026-10-14)
- ✅ **Data-driven map** in `game/data/map/lagos.json`: coastline, lagoon, 10 districts, 21 roads, 10 story landmarks
- ✅ **Districts:** Ikeja, Agbado-Ketu, Oshodi, Mushin, Surulere, Yaba; the Third Mainland and Eko bridges; Lagos Island/Obalende, Ikoyi, Victoria Island, Lekki
- ✅ **MapData:** ~25k-cell surface grid, beaches by coast distance, about 280 buildings and 580 props placed deterministically (~0.3 s)
- ✅ **GPU mask bake** (land/lagoon/roads) driving one continuous painted terrain shader, with an animated sea and lagoon
- ✅ **Chunk streaming** of buildings, props, lights and wires, with work spread over frames
- ✅ **Navigation:** AStarGrid2D walk and drive grids, click-to-walk paths, GPS routes, waypoints
- ✅ **Traffic:** danfo, car, keke and okada driving on the right; queueing, junction go-slow, bumping the player
- ✅ **Crowd:** a pedestrian spawn/despawn ring of 16 painted townsfolk
- ✅ **Night lighting:** a light-mask overlay with constant cost (60 fps at night)
- ✅ **Minimap** (round, route, landmarks) and **full map screen** (districts, landmarks, tap-to-route)
- ✅ District name on entry; 50 headless tests; **60 fps** on Medium day and night on the dev PC

## M2 — Life-sim core ⬜
- ⬜ Game clock and calendar, day/night tied to time, NEPA schedule per district
- ⬜ Needs (hunger, energy, fun, social, hygiene) and moods
- ⬜ Money (₦), wallet, a transaction ledger, inventory, shops and food vendors
- ⬜ Jobs and side hustles (danfo fares, catering/POS, content gigs), skills with XP
- ⬜ Housing (home base, sleep, wardrobe)
- ⬜ In-game phone UI: Family Meeting chat, map, gigs, bank, settings, gist
- ⬜ Save/load locally plus server sync with conflict handling
- ⬜ NPC routines (home, work, leisure) and the rules-based decision layer

## M3 — Story engine, Prologue and Act 1 ⬜
- ⬜ Mission system: data-driven objectives, triggers, checkpoints, fail/retry, rewards
- ⬜ Dialogue system: portraits, choices, flags, typewriter text, skip
- ⬜ Hero switching via Family Meeting chat, with off-screen events
- ⬜ Hero stats and abilities: Blood Pressure / Go-Slow Whisperer / Conductor Combo;
  Aura / The Stare / Ajo Network; Hype + Battery / Go Live / Gist
- ⬜ Still-panel cutscenes (low-bandwidth mode is the default)
- ⬜ Prologue (P1–P4) and Act 1 (1.1–1.5): scripts plus mini-games (money spraying, jollof
  queue, POS network failure, power hunt)

## M4 — Acts 2 and 3, endings ⬜
- ⬜ Act 2 (2.1–2.8) including Generator Wars, Japa Interview, Danfo Chase, Aso-Ebi
  Infiltration, Following the Money, Fuel Queue, Viral, Midpoint
- ⬜ Act 3 (3.1–3.5): campaign blocs, debate, Light Man, finale, four endings

## M5 — Online features ⬜
- ⬜ Accounts: guest, then phone OTP (provider interface; SMS vendor 🔒 owner account)
- ⬜ Venue chat and DMs with moderation (filters that check before showing, report/block, strikes)
- ⬜ F1 gig marketplace (game money): post, apply, escrow in game money, ratings, filters, anti-spam
- ⬜ F2 profiles and skills: CV, portfolio, verified badges, links into gameplay
- ⬜ F4 polls and ward elections: candidates, voting rules, anti-fraud, policies that affect the world
- ⬜ Admin console: moderation queues, election audit, kill switches

## M6 — AI and news ⬜
- ⬜ F6 NPC brains: rules plus cached Gemini archetype decisions, with fallbacks
- ⬜ F7 news service: RSS/API ingest, dedupe, classify, summarise, attribution, review dashboard
- ⬜ F8 NPC news banter: batch-generated line banks, guardrails, kill switches, player toggle;
  optional live NPC chat

## M7 — Money, prizes, compliance (behind feature flags) ⬜
- ⬜ F5 data/airtime skill games (points now; real prizes 🔒 legal + provider)
- ⬜ Real-naira gigs and escrow (🔒 company + licensed provider)
- ⬜ Privacy policy, terms, data-safety answers, age gate, content rating answers
- ⬜ Crash reporting and privacy-respecting analytics

## M8 — Polish and release ⬜
- ⬜ Remaining art: 8-direction vehicles, three heroes, villains, portraits, UI art
- ⬜ Audio: sound effects, music slots (licensing 🔒 owner), voice
- ⬜ Accessibility, localisation pass, native-speaker slang review (🔒 reviewers)
- ⬜ Performance on low-end profiles, memory budget, load times
- ⬜ Android release: AAB, signing, Play Asset Delivery, store listing — **final build**
