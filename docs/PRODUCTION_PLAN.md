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

## M2 — Life-sim core ✅ (2026-10-14)
- ✅ **Game clock** (1 real s = 1 game min), dusk/dawn blend, day/night lighting from the clock
- ✅ **NEPA:** a per-day outage schedule shared by all players, with fewer cuts in Ikoyi/VI/Lekki
- ✅ **Needs:** hunger, energy, fun, social, hygiene; mood labels; low energy slows you
- ✅ **Money:** ₦ wallet, ledger, inventory, items catalogue (street food, power bank, airtime…)
- ✅ **Vendors:** buildings and stalls are shops (mama-put, provision store, kiosks, beach bar, coconut seller); haggling skill discount
- ✅ **Hustles:** danfo runs with passengers, patience and the agbero cut; deliveries with deadlines; the POS shift mini-game
- ✅ **Skills:** XP curve 100×lv^1.5, level-up toasts
- ✅ **Housing:** sleep at your home landmark until morning
- ✅ **Phone:** Map, Hustle, Bank, Me, Settings (story apps plug in during M3)
- ✅ **Saving:** atomic local save, autosave every 60 s, on sleep and when Android pauses; cloud sync to `/api/save`, where the newer revision wins
- ⏩ NPC routines and the rules-based decision layer move to M3 (story NPCs) and M6 (F6 brains)
- ✅ 66 game tests and 9 server tests; CI fails on any SCRIPT ERROR

## M3 — Story engine, Prologue and Act 1 ✅ (2026-10-14)
- ✅ **Mission system** (`story/mission_runner.gd`, `data/story/missions.json`): data-driven steps
  (goto, collect, ability, film, minigame, chase, jam, say, panels, chat, switch, place, interior,
  npc, set), flag gates, timers, battery fail, checkpoints, fail → retry from checkpoint or quit,
  rewards, auto-chaining, resume from checkpoint after loading a save
- ✅ **Dialogue** (`ui/dialogue_box.gd`): painted portraits, name plates, typewriter text, choices
  with flags/effects/replies, Skip (stops at choices), tap/Space to advance
- ✅ **Still-panel cutscenes** (`ui/story_panels.gd`): painted comic frames, slow push-in (off with
  reduced motion), title card
- ✅ **Hero switching** (phone → Switch, renamed "Family Meeting 🔥" after 1.5): chat exchanges
  from a bank (a cold one when trust < 30), each hero keeps their own position and needs, weighted
  off-screen events after 2+ hours away (towed danfo, market dispute, viral gutter, small request)
- ✅ **Abilities** (`story/abilities.gd`, `ui/ability_bar.gd`): Tunde's BP meter (go-slow, crashes,
  smooth driving, Wahala Mode at 100, traffic proverbs), Go-Slow Whisperer (traffic slows, the
  danfo slips through), Conductor Combo (Sule's five calls); Aunty's Aura, The Stare (freezes
  story NPCs or townsfolk, longer with Aura), Ajo Network (free daily keke ride); KC's Battery
  (drains, charges at home when NEPA is on), Film, Go Live (crowd rallies), Hype. Gist is Act 2.
- ✅ **Interiors** (`world/interior.gd`): the painted Royal Pavilion owambe hall with guests,
  hotspots, blackout darkness, tap-to-walk
- ✅ **Chases** (`story/chase.gd`): on foot (1.3) and in the danfo (1.4) with a heat meter and
  passenger votes
- ✅ **Mini-games:** jollof queue, money spraying (rhythm), blackout quick-time, POS network
  failure (switch network / hold at the window), counting, generator standoff
- ✅ **Prologue P1–P4 and Act 1 1.1–1.5** fully scripted and playable, ~60 dialogue scenes
  (all Pidgin pending native-speaker review 🔒)
- ✅ **Named NPCs with daily routines** in free roam (Sule, Mama Nkem, Officer Gbenga, the barber,
  Alhaji Mechanic, Pepper and Salt, Engineer Bayo); talk to them
- ✅ **Phone apps:** Story (progress, quit, GPS to mission start), Switch, Keke (paid fast travel)
- ✅ Mission stars on the street, minimap and full map; only Tunde drives Baba God Dey (D-009)
- ✅ Landmark buildings are now always placed (the authored cell is a hint; nearest free lot)
- ✅ **Story QA autoplay:** `-- --story-auto --shots=DIR` plays the Prologue and Act 1 end to end
  (85 screenshots; 52–61 fps); 111 game tests incl. a full fake-host run of all 9 missions,
  retry from checkpoint, switching, abilities and save round-trip

## M4 — Acts 2 and 3, endings ✅ (2026-10-14)
- ✅ **Act 2 "Spread" (2.1–2.8):** Generator Wars (stealth push past rival lookouts; group Stare),
  Japa Interview (Northvale visa mini-game; confess-or-get-caught beat), Danfo Chase (passenger
  votes, wedding-convoy escape), Aso-Ebi Infiltration (gate dress-code check, the aunties, Mama
  Chief, KC's forced dance, Ledger's study in the compound-party interior), Following the Money
  (POS agents + investigation board; evidence only, no laundering), Fuel Queue Standoff (Stare +
  jerrycan-dodge brawl), Viral (rumour graph; false gists cost Hype and Trust), Midpoint: Old
  Money (the old-notes twist, the stitch-key pocket, Tunde's confession, keep-or-hand-over choice)
- ✅ Act 2 blocks open in any order (Block B after any two of Block A; Block C after 2.4 + 2.5)
- ✅ **Act 3 "Election Day" (3.1–3.5):** Campaign Season (drive Teacher to six voting blocs;
  honest pitches move them, bribes always backfire), The Debate (rebuttal-card battle, KC's live
  chat), Light Man (suya time trial for Engineer Bayo), Up NEPA! (stadium interior, timed hero
  switching, the "UP NEPA!" light-cue finale, the diary reveal, the WIEC result), Epilogue
- ✅ **Four endings** with painted epilogue panels: A Honest (full version when trust ≥ 60 etc.),
  B Hustle, C Japa, D Secret (all ten diary pages + the stitch key); rules in `Story.compute_ending()`
- ✅ **Election blocs** (traders, drivers, students, church women, okada union, youth) shown as a
  WIEC poll in the Story app; Teacher wins on the bloc average
- ✅ **Four hidden diary pages** glowing on the street after Act 1
- ✅ Ability tiers from the spec: Stare 2 (groups), Ajo 2, Conductor 2 (faster calls), Whisperer 3
  (8 s), Gist (KC, 3 a day, Hype scaled by Trust)
- ✅ Story money joins the wallet at the credits; "Start the story again" keeps money, skills and found pages
- ✅ Seven new mini-games: visa interview, dress code, evidence board, jerrycan dodge, rumour
  graph, debate, light cue; two new interiors (compound party, ward stadium); 15 new story panels
- ✅ 144 game tests: the full 22-mission story on the fake host, Act 2 block gating, all four ending rules
- 🔒 Native-speaker review of all Pidgin/Yoruba/Igbo lines (owner to arrange)

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
