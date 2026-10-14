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

## M5 — Online features ✅ (2026-10-14)
- ✅ **Data layer:** one SQL implementation (`apps/server/src/db.ts`): PostgreSQL in production,
  embedded Postgres (PGlite) for development and tests; versioned migrations in one locked transaction
- ✅ **Accounts:** guest token → phone OTP (`auth.ts`): codes hashed, 10-minute expiry, 5 attempts,
  rate limits per phone/account/IP; the phone is stored only as an HMAC with `PHONE_PEPPER` plus its
  last two digits; verifying the same phone on a new device signs in to the old account. SMS goes
  through a webhook 🔒 (the owner picks the gateway); no provider = OTP switched off, never faked
- ✅ **Chat and moderation** (`social.ts`, `moderation.ts`): street chat over the WebSocket, DMs
  with history, blocks enforced on the server, reports with message context; every message is
  checked before anyone sees it (personal data, payment/scam patterns, links for unverified,
  abuse and hate lists, extendable by moderators); strike ladder warning → 24 h mute → 7-day ban →
  permanent; new accounts wait 24 h (or verify); repeated violations strike automatically
- ✅ **F1 gig board, game money** (`market.ts`): server-side market wallet (escrow can't be faked),
  ₦50,000/day transfer cap, 5% withdrawal tax; post (verified, 3 open max, duplicate and scam
  checks, 2% posting fee), take, **finish by playing the skill's mini-game** (score ≥ 50 pays,
  otherwise refund), close with refunds, ratings only after a completed gig; NPC gigs from
  fictional businesses keep every board alive
- ✅ **F2 profiles** (`profiles.ts`): bio, district, languages, real skills, experience, portfolio
  links (verified only), availability, rate, in-game CV synced from the save, gig-verified skill
  badges, star rating, per-section visibility, opt-in public search
- ✅ **F4 polls and ward elections** (`civic.ts`): weekly WAT cycle (nominate Mon–Tue, campaign,
  vote Sun 10–18, count 18:00); fictional NPC candidates in every ward; player candidates need a
  verified phone, 14 days, level 8, no strikes and a ₦5,000 fee; one vote per verified player;
  append-only hash-chain ledger with receipts and a public audit; burst-of-new-accounts detection
  freezes an election; NPC blocs capped at half the vote; the winner's policy changes the ward in
  the game (Market Day −15% food, Transformer Fund fewer cuts, Fare Cap calmer passengers, Clean
  Gutters slower hygiene loss); community polls (admin-created or level-10 proposals, approved)
- ✅ **Admin console** at `/admin` (`ADMIN_TOKEN`): transparency stats, report queue
  (dismiss/hide/strike), player search and history, mute/strike/ban/unban, poll approval,
  election freeze/unfreeze/re-run/count, audit trail of every moderator action
- ✅ **Game client:** `Net.api()` REST helper; phone apps **Chat**, **Gigs**, **Profile** (with
  phone verification) and **Vote**; ward policies applied as you move between districts
- ✅ Tests: 16 server tests (8 new M5 groups) + a Godot ↔ server end-to-end check
  (`tests/online_check.gd`, 12 checks) in CI; CI also checks the features on real Postgres 17
- 🔒 Owner: choose/pay for an SMS gateway; set `PHONE_PEPPER`, `ADMIN_TOKEN` in Coolify;
  recruit moderators (Pidgin, Yoruba, Igbo, Hausa) before the public beta

## M6 — AI and news ✅ (2026-10-14)
- ✅ **Gemini service** (`ai.ts`): Interactions API with structured JSON output; every call is
  metered (tokens and USD per day and purpose), held under a hard daily budget, and behind a
  circuit breaker (an hour's back-off on billing or quota errors) and an admin "AI off" switch.
  Rules fallbacks keep the game fully playable with AI off.
- ✅ **F6 NPC brains** (`brains.ts`): reflex layer in the game; decision layer = archetype moods
  (traders, drivers, students, church women, okada union, youth) from today's approved topics,
  by rules and refined by one cached Gemini judgement per topic (6 h, shared, never per NPC).
  The game applies moods: worried traders charge ~5% more, angry drivers' passengers snap
  faster, and the "Street mood" shows in the Chat app.
- ✅ **F7 news service** (`news.ts`): owner-chosen RSS/Atom feeds ⚖️; headline + link + short
  lede only; conditional GET; dedupe by canonical URL and title shingles; rules + Gemini
  classification (11 categories, 6 sensitivity flags; either signal marks a story sensitive);
  neutral summaries in our own words with no person names; 72 h expiry, plus a week of audit.
  The parser was checked on two real Nigerian feeds.
- ✅ **F8 news banter:** hearsay-framed lines per archetype, with code guardrails (moderation,
  real-person detector, length, banned categories: politics, security, tragedy, health).
  Lines wait for **human review** in the console unless auto-publish is on. Templates are used
  when AI is off. Every line carries "📰 via Outlet" and the link. In game: passenger debates,
  radio chatter while driving, and named NPCs. There's a **player toggle** in Settings.
- ✅ **Live "Talk to NPC"** (off by default): 7 fictional personas; verified players only;
  20 replies a day; player text passed as quoted data; replies checked and replaced by canned
  lines on failure; every exchange logged and reportable.
- ✅ **Kill switches:** AI, news, banter, live chat, auto-publish, per category and per outlet.
  They act immediately, also at read time. Console tabs **News** (stories, block/allow,
  banter review, fetch now) and **AI** (switches, spend, chat log).
- ✅ Tests: 22 server tests (5 new M6 groups with a fake Gemini and fake feeds); 144 game tests
- 🔒 Owner: the Gemini project's **prepaid credits are depleted** (HTTP 402 on 2026-10-14).
  Top up in AI Studio before turning AI on in production. Choose news outlets for `NEWS_FEEDS` ⚖️.

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
