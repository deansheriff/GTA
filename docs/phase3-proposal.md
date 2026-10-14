# Naija Street Life — Phase 3 Proposal

*Draft v0.2, 2026-10-14 (Jev removed; Gemini for NPC AI, D-003). For owner approval. **No code is written until this is approved.***

**Inputs:**
- [Phase 2 report](phase2-findings-report.md)
- [Story Bible](story/story-bible.md)
- [Decision log](decisions.md)

**Labels:**
- **[V]** verified source
- **[I]** inference or estimate
- **[A]** assumption standing in for an unanswered open question (listed in §14)
- **⚖️** must be confirmed by a Nigerian lawyer before launch

---

## 1. Concept and differentiation pitch
**Naija Street Life** is a hand-painted 2D Lagos you can actually walk, drive and
argue your way through. It's a shared life-sim with a laugh-out-loud three-hero
story mode, NPCs who gist about today's real headlines, elections that change the
city, a gig board that pays real people, and mini-games that pay real data.

| | Reference game | Naija Street Life |
|---|---|---|
| Story | Three-choice pop-up vignettes | **"Up NEPA!"**: 3 switchable heroes, 4 acts, 4 endings |
| Lagos | Stock-kit 3D diorama; travel is a fade | Painted districts; **danfo rides, go-slow, conductors are gameplay** |
| NPCs | Labels and toasts | **Persona-driven NPCs** (rules + Gemini) with guard-railed dialogue that reacts to real news, plus optional live chat |
| Safety | Feed and gig board flooded with scams and solicitation | Verified tiers, pre-moderation, escrow-only gigs, scam detection |
| Economy | Hyper-inflated and black-market traded | Non-transferable game money, real sinks, stable prices |
| Rewards | Game money only | **Real data and airtime** from free-entry skill games ⚖️ |
| Gigs | Game-money gigs | Game-money gigs at MVP; **real-naira gigs with licensed escrow** later ⚖️ |
| Data use | ~0.7 MB/h idle (good), plus a polling leak | **≤ 1 MB/h idle budget**, push deltas only, no leaks |

**Who it's for:**
- Nigerian 18–35s on mid- and low-end Android phones over prepaid data.
- The diaspora, who want the jokes.
- Anyone who grew up with GTA and Sims and has never seen *their* city in one.

---

## 2. MVP scope vs. later
| Feature | MVP (public beta) | Later |
|---|---|---|
| 9. Story mode | **Prologue and Act 1** (4 missions + convergence) | Act 2, Act 3, endings |
| Life-sim core | Needs, eat, sleep, work, travel by **driven danfo**, 2 districts (Yaba, Lekki) | More districts, housing, businesses |
| 3. Graphics settings | **Full**: presets, toggles, data saver, auto-detect | Per-device tuning from telemetry |
| 2. Profiles and skills | **Full** in-game profile, skills, CV, portfolio text | External portfolio links and verification |
| 1. Gig marketplace | **Game-money** gig board with ratings, filters and anti-spam | **Real-naira** gigs with licensed escrow ⚖️ |
| 4. Polls and elections | **Community polls** and **fictional ward elections** (weekly) | Story Act 3 election; state-level offices |
| 6. NPC brains (rules + Gemini) | Rules-based NPC decisions in 2 districts, plus cached Gemini archetype calls | All districts, side-mission improvisation, live "Talk to NPC" chat (F8-B) |
| 7. News service | Ingest, classify and summarise pipeline **running internally**, with a review dashboard | Live in-game radio and gist after a review period |
| 8. NPC news talk | Off in the MVP; internal review only | On, with guardrails and a player toggle |
| 5. Data/airtime games | Mini-games playable **for points only** | Real prizes **after legal sign-off** and FCCPC registration ⚖️ |

**Why this order:**
1. **Story and feel first.** That's the gap the competitor can't close quickly.
2. **Safety and economy foundations before anything involving money or votes.**
3. **Legally gated features last,** so they're never blocked behind earlier work.

---

## 3. Tech stack
### 3.1 Client (2D, per decision D-001)
| Option | What it is | Pros | Cons |
|---|---|---|---|
| **A. Phaser (v4; v3.x fallback)** + Preact UI ✅ **Pick** | Full 2D game framework: scenes, tilemaps (Tiled), input, audio, arcade physics; WebGL with Canvas fallback | Fastest path to a playable game, large community, built-in tilemaps for districts and simple physics for danfo driving | Heavier than raw Pixi; less render control. Phaser 4's release status is [I] and must be confirmed in M0 |
| **B. PixiJS v8** + custom game layer + Preact | Pure renderer (WebGL/WebGPU), fastest sprite batching | Maximum performance and control; WebGPU path | We'd write scenes, tilemaps, input, audio and physics ourselves (+6–8 weeks) |
| **C. Godot 4, HTML5 export** | Full engine exported to WebAssembly | Great editor and tooling | Large wasm download (tens of MB [I]), slow start on low-end Android, poor fit for data budgets |

**Pick A:**
- Phaser gets us to a playable slice fastest.
- DOM UI in **Preact** (~4 KB) for menus, the phone, chat and the marketplace, so
  text is accessible and translatable.
- If M0 benchmarks on a low-end Android show the renderer is the bottleneck, we
  swap the renderer layer for Pixi.

**Animation:**
- **Spine** skeletal animation for the three heroes and key villains (smooth,
  small files).
  - ⚠ Paid editor licence per animator; Enterprise licence above a revenue threshold. [V terms, I price]
- **Frame sprite sheets** (6–8 frames) for crowds and NPCs.
- Free alternative to Spine: DragonBones; we evaluate in M0.

**Other client pieces:**
- **PWA:** Workbox service worker, cache-first for art, offline title screen, and
  resume from a local save.
- **Build:** Vite, TypeScript, ESLint, Vitest, Playwright (smoke tests in a
  low-end-Android emulator profile).

### 3.2 Backend
| Option | What it is | Pros | Cons |
|---|---|---|---|
| **1. TypeScript monolith** ✅ **Pick** | Node (Fastify) REST + **Colyseus** WebSocket rooms + PostgreSQL + Redis | One language end to end. Server-authoritative for money, votes and prizes. Colyseus is built for room-based browser games | We run more infrastructure |
| 2. Supabase + edge functions + small Colyseus box | Managed Postgres, auth, realtime and storage | Quickest to start; row-level security | Money, escrow and voting logic is spread across policies and functions; vendor lock-in |
| 3. Nakama | Open-source game server (auth, storage, realtime, leaderboards) | Lots of game features out of the box | Go/Lua/TS runtime split; smaller hiring pool; marketplace and news are custom anyway |

**Services inside the pick:**
- `api`: auth, profiles, marketplace, polls, saves.
- `realtime`: Colyseus rooms per venue/district; presence and chat.
- `workers`, on a BullMQ (Redis) queue:
  - news ingest
  - Gemini archetype-decision batches
  - Gemini batch dialogue generation
  - prize fulfilment
  - moderation
- `admin`: a moderation queue, a news review dashboard, election audit, and kill switches.

**Data and hosting:**
- **Database:** managed PostgreSQL, with **append-only ledgers** for money, votes
  and prizes (double-entry, never updated in place).
- **Hosting** [I, to benchmark in M0]:
  - Compute in the nearest well-served region (EU-West vs. Africa regions; Lagos
    latency will be measured).
  - **Cloudflare** CDN for static art (it has Nigerian points of presence [I]).
- **Realtime design:**
  - WebSocket deltas only. No polling of large lists.
  - Lists such as candidates and gigs are paginated, ETag-cached and fetched on demand.
  - This fixes the competitor's leak by design.

### 3.3 Third-party services (each needs a key or account; I'll ask before signing up or spending)
| Need | Proposed | Notes |
|---|---|---|
| NPC dialogue, live NPC chat, archetype decisions, news summaries, classification | **Google Gemini API, paid tier** (D-003): `gemini-3.1-flash-lite` default, `gemini-3.8-flash` optional | Batch API 50% off; context caching. The free tier isn't used because of its data-use terms [V] |
| Payments (later) | **Paystack** or **Flutterwave** | Requires a CAC-registered company [V] |
| Airtime/data | **VTpass** / **Reloadly** / Flutterwave Bills | Prices not public; get rate cards [V/I] |
| OTP / phone verification | **Termii** or similar, with WhatsApp OTP fallback | ~$0.0055–0.008 per SMS on clean routes [V vendor blog] |
| News | Publisher RSS + NewsData.io (commercial tier) | §8 |
| Error/perf telemetry | Sentry (self-hosted or SaaS) | Data-protection review needed |

---

## 4. Art pipeline (2D, The Omins style)
### 4.1 Style guide (summary; the full guide comes in M0)
- **Camera:** top-down 3/4 view (about a 30° tilt) with a fixed orthographic feel.
  Same style family as The Omins, but our own art.
- **Painting:** soft painted ground textures, chunky readable silhouettes, slightly
  oversized heads and hands for expression, warm saturated palette.
  - **Danfo yellow** and **NEPA night-blue** are key colours.
  - Strong value contrast, so the game reads on dim phone screens.
- **Lighting states:** every district has **Day / Dusk / Night-with-light /
  Night-NEPA-off**.
  - NEPA-off is a tint and light-mask overlay plus generator-lit pockets, not
    repainted art.
- **Cultural accuracy:**
  - Fabrics (Ankara, Adire, Aso-oke).
  - Signage in a mix of English and Pidgin, with fictional brands only.
  - Real Lagos textures: gutters, kerbside umbrellas, painted "No Parking"
    walls, kerosene stoves.

### 4.2 How assets are made (Blender is optional)
1. **Characters:**
   - Concept, then a painted **Spine** rig (parts painted separately).
   - Directions: 4 drawn (S, SE, E, NE) plus mirrored, giving 8.
   - Hero animations: idle, walk, run, talk, emote (3), signature action.
2. **Vehicles (danfo, keke, okada, cars):**
   - **Blender is optional here.** Model low-poly once, render 8 directions with a
     painterly shader, then paint over.
   - This gives perfect rotation consistency for driving.
   - Blender is only an *authoring* tool; nothing 3D ships.
3. **Environments:** painted **tilesets** (128×64 isometric tiles at 1×) plus
   painted props. Districts are assembled in **Tiled**.
4. **Export:**
   - TexturePacker (or free-tex-packer) builds atlases.
   - Formats: **WebP** (universal) plus optional **AVIF**.
   - Optional **KTX2/Basis** compressed textures for GPU memory on capable devices [I].

### 4.3 Budgets (mobile web)
| Item | Low | Medium | High |
|---|---|---|---|
| Atlas resolution scale | 0.5× | 1× | 2× (desktop/tablet) |
| Max atlas size | 1024² | 2048² | 2048² (multiple) |
| District download (first visit) | ≤ 250 KB | ≤ 500 KB | ≤ 1.2 MB |
| Hero Spine (skeleton + atlas) | ≤ 120 KB | ≤ 250 KB | ≤ 500 KB |
| Frame rate | 30 cap | 60 cap (30 on battery saver) | 60 / uncapped |
| On-screen NPCs | 12 | 30 | 60 |

**First install (title + Prologue): ≤ 3 MB on Low, ≤ 6 MB on Medium.**
**Idle data budget: ≤ 1 MB/hour.**

### 4.4 Naming conventions
```
nsl_{type}_{name}[_{variant}][_{dir}][_{frame}].{ext}
type  = char | npc | veh | prop | tile | fx | ui | bg
dir   = s | se | e | ne   (mirroring gives sw, w, nw)
e.g.  nsl_veh_danfo-babagoddey_damaged_se_00.png
      nsl_char_auntyboss_stare_s_04.png
atlases: nsl_atlas_{district|set}_{tier}.webp + .json   (tier = lo | md | hi)
spine:   nsl_spine_{name}.skel + nsl_spine_{name}_{tier}.atlas
```
- Source files (PSD/Krita/Blender) go in `art-src/`; exported files go in `assets/`.
- Large binaries use **Git LFS**.

### 4.5 Loading tied to graphics settings
- **Asset manifest:** each asset lists its **tier variants** and byte size.
- **Selection:** the client picks a tier from the graphics preset, data saver and
  network type.
- **Streaming:** the district is split into **chunks**. "Draw distance" sets how
  many chunks around the player load (1 / 2 / 3).
- **Data saver:**
  - forces Low tier
  - turns off ambient particles
  - swaps animated cutscenes for **painted stills plus text**
  - delays voice clips until tapped

### 4.6 First 20 assets
1. **Tunde** hero rig: idle, walk, drive-pose, argue, BP tantrum.
2. **Aunty Boss** hero rig: walk, serve, The Stare, haggle.
3. **KC** hero rig: walk, run-while-filming, Go Live, phone-dying.
4. **Danfo "Baba God Dey"**: 8 directions, 3 damage states, door open/closed, passenger silhouettes.
5. **Ghana-must-go bag**: prop, icon and a "glowing loot" variant.
6. **Aunty Boss Kitchen**: canteen front, **POS umbrella**, benches, pots.
7. **KC's kit**: ring light, tripod, power bank, cracked phone UI.
8. **Generators**: small petrol "I-pass-my-neighbour" and big diesel, with running animation, smoke FX and sound.
9. **Owambe hall**: interior tileset, canopy, round tables, stage, speakers, MC stand.
10. **Owambe guest kit**: paper-doll NPC layers in aso-ebi colours, gele and agbada.
11. **Yaba street tileset**: roads, gutters, kerbs, walls, kiosks.
12. **Lekki estate tileset**: gates, security post, interlocking tiles.
13. **Market stall kit**: umbrellas, tables, produce, sacks.
14. **Keke and okada**: 8 directions each.
15. **NPC base bodies**: 4 body types × 6 outfits (paper-doll system).
16. **Chief "Double Chop"**: rig plus campaign billboard and poster art.
17. **Pepper and Salt** henchmen: rig with shared animations.
18. **Electric pole and transformer**: light-on/off states and the NEPA "snap" FX.
19. **LARDO road warden and checkpoint**: Officer Gbenga.
20. **UI kit**: phone frame, "Family Meeting 🔥" chat, needs icons, HUD, graphics-settings screen.

---

## 5. Feature designs
### F1. Job/gig marketplace
**Two lanes, kept strictly separate:**
- **In-game gigs (MVP):**
  - Players and NPCs post game-money jobs (decorate, cook for a party, drive a
    convoy, film an event).
  - Completing a gig is **gameplay**: you play a cooking, driving or filming
    mini-game, so pay can't be farmed by clicking.
- **Real-world gigs (later ⚖️):**
  - Real employers post real jobs (design, content, catering, tutoring, delivery).
  - They pay in naira.
  - This lane is never convertible to or from game money.

**Fees and money (real lane) [A, to confirm]:**
- **Posting fee:** ₦500–₦2,000 per job, scaled by budget. This meets the brief's
  "employers pay to post" and filters spam.
- **Service fee:** ~10% from the employer plus ~5% from the worker, on completion.
- **Payment flow:**
  - Employer pays → **escrow** → released on milestone approval → payout to the
    worker's verified bank account.
  - **Auto-release** after 5 days without dispute.
  - **Dispute window:** a moderator decides, with evidence upload.
- ⚖️ **Escrow is the legal crux.**
  - Holding third-party funds may need CBN licensing [V third-party guidance, not law].
  - Option (a): partner with a **licensed escrow or payment provider** that holds
    funds, so we never touch them.
  - Option (b): **split-on-capture** through Paystack/Flutterwave subaccounts with
    milestone-sized charges, which avoids holding funds.
  - Both need a **CAC-registered company**, TIN and corporate bank account [V].
  - Payouts need worker KYC (BVN/NIN via the provider).
  - Our fees attract VAT [I].
- **Ratings and reviews:**
  - Both sides rate each other, **only after an escrow-completed job**.
  - Reviews are visible.
  - Reviews on cancelled jobs are moderator-gated.
- **Discovery:**
  - Categories, search, filters (budget, location/district, remote, rating,
    verified only, deadline) and saved searches.
  - **Gig matching uses the profile's skills.**
- **Anti-spam and fraud:**
  - Verified phone required to post or apply.
  - New-account limits.
  - Classifiers (keyword rules + Gemini) for solicitation, scams and off-platform payment requests
    (bank numbers, "send to my Opay").
  - Duplicate-post detection; price sanity checks.
  - Report → moderator queue.
  - **Off-platform payment attempts are blocked and logged.**

### F2. Profiles and skills
**What a profile holds:**
- display name, avatar, bio, location (district/state)
- languages
- skills, each with level and evidence
- experience entries, education/courses
- portfolio (images, links; moderated)
- availability, rate range
- verified badges (phone, ID for payouts)
- in-game CV (auto-built from game records, as the competitor does, but with
  player-entered fields too)

**Two skill layers, linked:**
- **Real skills:** self-declared, upgraded to *"Verified"* by completing paid gigs
  or skill tests.
- **In-game skills:** Driving, Cooking, Haggling, Filming, Charisma, Coding, Hustle,
  Music, Comedy.
- **How they link:**
  - Declaring "Photography" gives a small in-game Filming head start and unlocks
    photography gigs.
  - NPCs react to you: the market woman asks the "photographer" to snap her stall.
  - Careers check in-game skills.

**Privacy:** per-section visibility (public / members / only me). NDPA consent
for showing a profile in public search ⚖️.

### F3. Graphics settings
- **Presets:** Low / Medium / High / Custom.
- **Toggles:**
  - shadows (none, blob, painted)
  - effects and particles (off, low, full)
  - weather FX
  - NEPA lighting overlay quality
  - draw distance (1–3 chunks)
  - texture tier (0.5×, 1×, 2×)
  - frame-rate cap (30 / 60 / uncapped)
  - animation smoothness (12 or 24 fps for NPC frame animations)
  - UI scale and text size
  - colour-blind palettes
  - reduced motion and screen shake off
  - subtitles size
- **Data saver mode:**
  - Low tier and no prefetch.
  - **Low-bandwidth cutscenes:** painted stills plus text, voice on tap.
  - News and radio off unless on Wi-Fi.
  - Session data meter visible in the HUD.
- **Auto-detect at first launch:**
  - Read `navigator.deviceMemory`, `hardwareConcurrency`, the WebGL renderer
    string and `navigator.connection.effectiveType`/`saveData` [I; not every
    browser exposes all of these].
  - Run a **2-second render benchmark**, then **suggest** a preset, which the
    player confirms.
  - **Re-suggest** if the frame rate stays below the cap for 60s.

### F4. Polls and elections
**Two separate systems:**
- **Community polls:** general-purpose questions (single choice, multi-choice,
  ranked), created by admins, or by players at level ≥ 10 with moderation.
  They have an open window, results visibility rules and a minimum turnout.
- **Elections:** recurring ward offices (Ward Councillor and Market Chairperson at
  MVP; LG Chairman later).

**Election timeline (weekly cycle):**

| Days | Phase |
|---|---|
| Mon–Tue | Nomination |
| Wed–Sat | Campaign (rallies, debates as in-game events, posters) |
| Sun 10:00–18:00 WAT | **Voting at in-game polling units** |
| Sun 18:00 | Live count |
| Mon | Inauguration |

**Candidates are players and NPCs:**
- **Players** must be phone-verified, account ≥ 14 days old, level ≥ 8 and clean
  of strikes, and pay a game-money nomination fee. Slogans are pre-moderated.
- **NPCs** are fictional candidates with platforms; a rules-based campaign planner, with cached Gemini judgement calls, decides their campaign
  moves.
  - This keeps ballots meaningful even in quiet wards.
  - It satisfies "fictional candidates by default".
  - **No real public figures**, and ⚖️ no real-world political ads anywhere.

**Who votes:**
- Players: **one vote per verified phone number per election.**
- NPC voters are simulated **in aggregate** (voting blocs scored by rules plus cached Gemini archetype opinions:
  traders, drivers, students) and shown as a separate "NPC turnout" bar.
  Their weight is capped at 50% of the total.

**Anti-fraud:**
- Phone OTP and account age.
- Device fingerprint plus IP/ASN heuristics, with **anomaly detection** (bursts of
  votes from new accounts, shared devices).
- Votes are recorded in an **append-only ledger**; an audit view shows hashed vote
  receipts.
- Vote-buying reports go to investigation, then disqualification and strikes.
- A suspicious election can be **frozen and re-run**.

**Effects on the world:**
- The winner picks **from a fixed policy menu with bounded effects**, e.g.:
  - "Market Day Discount" (−15% food)
  - "Transformer Fund" (fewer NEPA cuts in the ward)
  - "Danfo Fare Cap"
  - "Clean Gutters" (less flooding)
- Policies last one term and are shown on billboards.
- NPCs comment on them, and the NPC decision layer uses the policy as an input.

**Story Act 3:**
- The Agbado-Ketu Central election is a **single-player simulation** using the
  same UI, so the plot can't be broken.
- Outcomes depend on story choices and NPC voting blocs.
- Optionally, a community poll result is shown as "the people's mood" flavour.

### F5. Games that win data and airtime ⚖️
**Games:** skill-based reuses of story mini-games:
- Visa Interview (quick-answer timing)
- Ajo Collection (memory and haggling)
- Danfo Conversation (dialogue rhythm)
- Money Spraying (rhythm)
- Generator Wars (route puzzle)

**Model: free entry, no purchase necessary, skill-based.**
- No purchase, stake or paid currency is ever required to enter or win.
- [I] Removing "consideration" is the usual way to stay outside lottery/gaming
  definitions. ⚖️ Lawyer to confirm under Lagos and other state laws, since
  lotteries are **state-regulated** after the Nov 2024 Supreme Court ruling [V].
  How that applies to online platforms remains unclear [V].

**Prize structure:**
- Daily "challenges" with **score thresholds**: hit the target and earn a prize
  ticket.
- Weekly **leaderboard prizes** for the top N.
- Prizes come from a **fixed monthly budget pool** that closes when it's empty.
- Small denominations: ₦100–₦500 airtime, 500 MB–1 GB data.

**Per-player limits:**
- 1 prize per verified phone per day.
- A weekly naira cap per person.
- Prizes only to phone-verified players aged **18+**.
- Prizes go **only to the verified phone number** (no transfers).

**Fairness and anti-cheat:**
- The server generates seeds and validates inputs: the client sends the input log
  and the server **replays** it.
- Impossible-score detection; device and phone limits.
- Delayed fulfilment (minutes) for fraud checks.
- Random manual audits; published odds and prize counts.

**Fulfilment:**
- Provider API (**VTpass** / **Reloadly** / **Flutterwave Bills**).
- Idempotency keys; retries; a ledger entry for every prize.
- A reconciliation job against provider statements.
- [I] Cost is face value minus the provider discount (typically a few %; **get
  written rate cards**).

**Sustainability:**
- Budget is set as a % of revenue (ads, sponsor pools).
- A **sponsored prize pool** model: a brand funds a week's pool and gets in-world
  billboards.
- Cost per daily active user is tracked; pools auto-scale down when over budget.

**⚖️ Legal checklist for a lawyer:**
1. Is a free-entry skill game a "lottery"/"gaming" under each relevant state's law?
2. **FCCPC sales promotion registration.** A draft *Sales Promotion (Amended)
   Regulations 2026* was published 30 Sep 2026, with comments due **20 Oct 2026**
   [V]. It would require registering each promotion before launch, with fees and
   penalties up to ₦100m or 1% of turnover [V summaries]. It also requires
   **registering AI use in promotions** [V].
3. Age limits and verification method.
4. Consumer-protection T&Cs, complaints process, and prize-delivery obligations.
5. Tax on prizes.
6. **NDPA 2023 + GAID 2025:** data-protection duties [V]:
   - DPIA for profiling and children
   - DPO
   - possible registration as a major-importance data controller
   - consent records
7. NCC rules on SMS/OTP and DND [I].

### F6. NPC brains: rules + Gemini (no Jev, per D-003)
**Architecture: a three-layer "brain".**
1. **Reflex layer (client, free, every frame):** utility AI and state machines for
   walking, queueing, reacting to the player, and bumping. No API.
2. **Decision layer (server, rules first):** *meaningful* choices at low cadence:
   - what to buy, whether to haggle
   - which gig to accept, which candidate to back
   - how to react to a hero's Gist, Stare or Go Live
   - which side to take in an argument, which mood to adopt after news

   These use **weighted utility scoring** from each NPC's persona sheet, needs,
   money, relationship to the hero, recent memories, and local events and policies.
   It's deterministic and costs nothing to run.
   - **Gemini (structured output, enum answers)** only handles **archetype-level**
     judgement calls that rules can't express well. Examples: "how do traders feel
     about today's fuel-price topic?" or "which campaign promise lands with okada
     riders?"
   - The result is **cached** and shared by every NPC of that archetype for hours.
     There are no per-NPC live calls.
3. **Voice layer (Gemini):** lines matching the chosen action and mood. See F8.

**Why not call Gemini for every NPC decision** [V prices, I volumes]:
- At 600k decisions/day × ~1,500 input tokens on `gemini-3.1-flash-lite`
  ($0.25/M in, $1.50/M out), that's about **$250–300/day**.
- Latency would be several hundred ms or more.
- Archetype caching cuts this to roughly **5–20k calls/day, about $2–10/day**.
  Rules cover the rest.

**Latency:** Gemini calls are **asynchronous and anticipatory**: decisions are
precomputed per archetype and situation. The player never waits on an AI call.

**Fallbacks:**
- Every decision type has a rules path, so the game is fully playable with AI off.
- A circuit breaker and an admin "AI off" switch.

**Consistency:**
- **Persona sheets:** traits, values, catchphrases, political lean (fictional
  parties only), a **memory log** of key events, and a seeded RNG.
- Every AI output is **schema-validated**, and the chosen action must be legal and
  affordable.
- Maths and dates are computed in code, never asked of the model.

**What we lose by dropping Jev:**
- Jev's per-call cost (~$0.00006) and speed made **per-NPC live decisions**
  affordable. Gemini makes that roughly 10× more expensive, so the design moves to
  rules plus cached archetype decisions.
- Players won't notice much in ambient behaviour. If we ever want
  "every NPC thinks independently", Jev, or a small self-hosted model, can be
  reconsidered.

### F7. News service
**Sources (in order of preference):**
1. **Publisher RSS feeds** from Nigerian outlets: headline, link and lede only.
   Check each outlet's terms; prefer outlets that allow headline-and-link use. ⚖️
2. A **commercial news API** (e.g. NewsData.io paid tier, ~$200/month [V
   third-party]; its free tier allows commercial use at 200 credits/day [V
   third-party]) to fill gaps and handle de-duplication. We **verify its Nigerian
   source coverage** in M3.
3. **Official and data feeds:** NiMet weather, central bank exchange rates, fuel
   price data where public, licensed football results API (facts only) [I].

**Cadence and processing:**
- Poll every 15–30 minutes; conditional GET (ETag).
- **Dedupe:** canonical URL, then title shingles/simhash, then optional embedding
  clustering into "stories".
- **Categorise (Gemini, structured output):** economy, fuel/power, transport, weather, sports,
  entertainment, tech, politics, security, health, tragedy.

**Sensitivity scoring (Gemini, structured yes/no and 0–1 scores):**
- Involves death or injury?
- Elections or politicians?
- Religion or ethnicity?
- Unverified allegation?
- Minors?
- Names a private person?

**Summaries:**
- **Gemini** writes a **1–2 sentence neutral summary in our own words** from the
  headline and lede only.
- It always carries **source name, link and time**. No article text is stored or
  shown beyond the headline [brief rule].

**Storage and expiry:**
- Stories expire after 48–72 hours.
- An audit log keeps every item and every line generated from it.

**Attribution in the UI:** "📰 via [Outlet], 2h ago" with a tap-through link on
every news-driven line or radio item.

### F8. NPC conversations linked to the news
**From news to NPC lines:**
- The news service emits **topic cards**, not articles. For example:
  "fuel price up at pumps (economy, low sensitivity, source X)".
- NPCs **react to topics**, in character:
  - Tunde's passengers argue about fuel.
  - Aunty's customers complain about tomato prices.
  - Students joke about the football.

**Guardrails (enforced in code, not just prompts):**
1. **No real people named or quoted in NPC dialogue.** Lines refer to roles
   ("government", "the club") and never invent quotes.
2. **No defamation and no allegations.**
   - Topics flagged "allegation / crime / court" are **excluded** from banter.
   - Every NPC line about news is framed as opinion or hearsay ("I hear say…",
     "Na wetin radio talk"), never stated as fact.
   - The source link is always available.
3. **Sensitive-topic tone control:**
   - Tragedies, violence and disasters are **excluded from banter by default**.
   - Optionally a **"respect mode"**: a sombre acknowledgement, no jokes, no
     speculation.
   - **Elections and politicians: no opinions on real parties or candidates.**
     NPCs may mention *that* an event is happening (e.g. "voting is next week"),
     never who to support.
4. **Two conversation modes, both on Gemini (D-003):**
   - **A. Ambient banter (MVP):**
     - Passenger arguments, market gist, radio, and news reactions.
     - **Pre-generated in batches** (Gemini Batch API, 50% off).
     - Each batch is automatically checked (Gemini classifier pass, a
       banned-entity list, and a real-person-name detector), then **sampled by a
       person for review**, then published to the line bank.
     - **Nothing in this mode comes from a live model call.**
   - **B. "Talk to NPC" live chat (after M3, behind a flag):** the player types or
     picks prompts, and selected NPCs answer live in character.
     - **Who and how much:**
       - Verified players only.
       - A daily reply cap per player (e.g. 20).
       - Replies of 1–2 sentences.
     - **Prompt-injection guard:**
       - The persona and rules live in the system instruction.
       - Player text is passed as quoted data.
       - Players can't change who the NPC is.
     - **What the NPC can mention:** news **topic cards** from the approved list
       only, and no named real people.
     - **Every reply is checked:**
       - schema and length check
       - banned-entity and real-name filter
       - safety classifier (Gemini's own configurable safety filters plus ours [I])
       - A failed check falls back to a canned in-character line ("Abeg, make we
         talk another thing").
     - **Oversight:** all exchanges are logged for review, every NPC reply has a
       report button, and live chat has its own kill switch.
5. **Kill switches:** global, per topic, per category and per outlet.
   - A **player toggle** ("News chatter: on/off") lives in Settings.
   - A **review dashboard** shows every published line with its source.
6. **Story isolation:** story scenes never depend on news.

**Dialogue cost** (Gemini paid tier, prices from ai.google.dev, updated 2026-10-14 [V]; volumes [I]):

| Model | Standard price per M tokens (in / out) | Batch | Notes |
|---|---|---|---|
| **`gemini-3.1-flash-lite`** ✅ default | $0.25 / $1.50 | $0.125 / $0.75 | Cheapest current model; no announced price rise |
| `gemini-3.8-flash` | $0.75 / $3.75 → **$1.50 / $7.50 from 1 Jan 2027** | $0.375 / $1.875 → doubles | Better writing; use if Flash-Lite's Pidgin isn't good enough |

- **A. Ambient banter:**
  - Volume: 40 topics × 40 personas × 5 variants = 8,000 lines/day, each ~700 in
    + ~60 out tokens.
  - Cost: **≈ $1/day** on Flash-Lite batch; ≈ $3/day on 3.8 Flash batch (≈ $6
    after Jan 2027).
- **B. Live chat:**
  - Per reply: ~2,000 in (persona, memory and rules; mostly context-cached) + ~80 out.
  - Volume: 10k daily players × 20 replies = 200k replies/day.
  - Cost on Flash-Lite: ≈ **$40–125/day** depending on cache hits.
  - Cost on 3.8 Flash: ≈ $360/day, rising to ≈ $720 in 2027.
  - **This is why live chat is capped and flagged.**
- **Thinking tokens are billed as output** [V]. We use minimal thinking for line
  generation.
- **Use the paid tier only.** Google's free tier may use data "to improve our
  products" [V]. Player messages must not go there, and this matters under the
  NDPA ⚖️.
- **Model choice:** we'd evaluate Flash-Lite vs. 3.8 Flash on a
  Pidgin-reviewed sample, and you pick.
---

## 6. Story mode integration (with features 1–8)
See Story Bible §11. Engineering rules:
- **Story state** is a server-side save with a **flags + variables** model.
- **Hero state** is separate per hero: location, stats, inventory.
- **Off-screen simulation** runs on hero switch: a weighted event table (rules; Gemini may only write the flavour text).
- **Missions** are data-driven: JSON/YAML mission scripts plus a small visual
  scripting layer for designers.
- **Story-critical NPCs** have no AI hooks.

**Story deliverables 2–6** (mission list, ability spec, Prologue and Act 1 scripts,
dialogue banks, integration spec) will be written **during M0–M1**, before the
matching code.

---

## 7. Moderation, safety and anti-abuse
**Identity tiers:**

| Tier | Can | Requirement |
|---|---|---|
| Guest | Play story and single-player | none |
| Member | Venue chat (rate-limited), profile | account + email or phone |
| Verified | Public posts, gigs, voting, prizes, running for office | phone OTP |
| Payout-verified | Real-naira payouts | KYC via the payment provider ⚖️ |

**Chat and feed:**
- **Pre-send** classification (fast keyword and pattern rules on every message; Gemini for borderline cases):
  - sexual content or solicitation
  - scam patterns: "send real money", account numbers, crypto
  - hate (ethnic or religious slurs)
  - threats
  - personal data
- Blocked messages are never shown.
- Borderline messages are held for a moderator.
- Rate limits; links only from Verified users.
- New accounts can't post publicly for 24 hours or until level 3.
- **No game-money trading:** player-to-player transfers are capped and taxed, and
  "selling game money" is detected and banned.
- Block, mute and report everywhere.
- **Strikes:** warning → 24-hour mute → 7-day ban → permanent.
- Appeals.

**Marketplace:** see F1. Also: escrow-only payments, off-platform payment
detection, KYC for payouts, a dispute desk.

**Polls and elections:** see F4. Also: slogans pre-moderated, campaign posters
reviewed, no real-world political content, vote-buying enforcement.

**Ads (if any):**
- Every ad is reviewed by a person.
- No political, gambling, adult or crypto ads ⚖️.

**Tooling:**
- An admin console with queues, user history and bulk actions.
- An audit trail of moderator actions.
- **Transparency stats** published monthly.

**People:**
- ⚖️ / [A] Part-time Nigerian moderators who speak Pidgin, Yoruba, Igbo and Hausa
  are needed from public beta. AI flags, people decide.

**Age:** [A] **18+** at launch (matches the prize and real-money features).
A 13+ safe mode can be added later with chat restricted to presets.

---

## 8. Data budget and performance plan
- **Targets:**
  - first playable in ≤ 3 MB (Low)
  - idle ≤ 1 MB/hour
  - a typical 30-minute session ≤ 10 MB on Low
- **Network:**
  - WebSocket deltas with **msgpack**; no polling of lists.
  - Paginated APIs with ETags and Brotli.
  - The service worker caches art permanently (versioned).
- **Performance:**
  - 60 fps on a mid-range phone and 30 fps on a 2 GB-RAM Android, measured in M0
    on real devices. ⚠ We'll need 2–3 cheap test phones [A].
- **Data meter:** a live in-game data meter, and a "Daily data cap" setting that
  stops prefetching once it's reached.

---

## 9. AI usage summary (Gemini only, per D-003)
**What Gemini is used for:**
- Ambient line banks (batch).
- Live "Talk to NPC" chat (flagged and capped).
- Archetype-level NPC judgement calls (cached).
- News categorisation, sensitivity scoring and summaries.
- Second-pass moderation on borderline chat and posts.

**Pricing** (paid tier):

| Model | Standard (in / out per M tokens) | Batch |
|---|---|---|
| `gemini-3.1-flash-lite` (default) | $0.25 / $1.50 | half price |
| `gemini-3.8-flash` | $0.75 / $3.75 now, $1.50 / $7.50 from 1 Jan 2027 [V] | half price |

**Rules that apply everywhere:**
- Output is always schema-validated.
- Everything has a rules or canned fallback.
- **Only the paid tier is used.** The free tier may use data to improve Google's
  products [V].
- **Data protection:** ⚖️ an NDPA review covers sending player chat to Google,
  including the data-processing agreement and cross-border transfer.

---

## 10. Milestones (realistic order of work)
*Durations assume 1 lead engineer (me), plus **1 painter/illustrator**, plus
part-time native-speaker writers and reviewers [A]. Art is the critical path.*

### M0 — Foundations and art test (≈ 3 weeks)
- Repo layout, CI, Phaser + Preact skeleton, PWA shell, asset pipeline scripts.
- **Style test:** one painted Yaba street chunk, Tunde idle/walk in Spine, the
  danfo in 8 directions.
- Device benchmarks; data-budget harness.
- Story deliverables **2** (mission list) and **3** (abilities and progression).
- **Check-in:** you approve the look and feel on your own phone.

### M1 — Vertical slice: the Prologue (≈ 6 weeks)
- Owambe Prologue playable with all three heroes and the blackout set piece.
- "Family Meeting 🔥" switching; the life-sim core (needs, eat, sleep) in Yaba.
- **Graphics settings, data saver and auto-detect** (F3).
- Guest accounts and cloud save.
- Story deliverables **4** (Prologue and Act 1 scripts) and **5** (dialogue banks, v1).
- **Check-in:** a playtest build link for you and 10 testers.

### M2 — Act 1 and the living city (≈ 8 weeks)
- Act 1 (4 missions plus convergence).
- Driven danfo travel with go-slow.
- Lekki district; careers.
- **Profiles and skills (F2).**
- **In-game gig board (F1, game money).**
- Accounts, phone OTP, chat with moderation v1.
- **Check-in:** closed beta, about 200 players.

### M3 — Civic and brains (≈ 6 weeks)
- **Community polls and ward elections (F4)** with anti-fraud.
- **NPC brains (F6)** in two districts.
- A **live "Talk to NPC" chat (F8-B)** pilot behind a flag.
- **News pipeline (F7)** live internally with a review dashboard.
- Story deliverable **6** (integration spec).
- **Check-in:** public beta decision.

### M4 — Act 2 and rewards (≈ 8 weeks)
- Act 2 missions.
- **NPC news chatter (F8)** switched on after review.
- **Mini-games for points.**
- **Real prizes switched on only after** lawyer sign-off, FCCPC registration and
  a provider contract (F5).

### M5 — Act 3, endings and launch hardening (≈ 8 weeks)
- Act 3 election finale and 4 endings.
- Load tests, security review, NDPA compliance pack.
- **Real-naira gigs** if approved and licensed (F1).

**Total ≈ 39 weeks (~9 months) to full launch.** The public beta is around
**week 23**, with the Prologue, Act 1, the city, profiles, gigs, polls and NPC
decisions. Everything legally gated stays behind feature flags until cleared.

---

## 11. Budget (third-party running costs, rough, at 10k daily players) [I]
| Item | ~ per month |
|---|---|
| Hosting (API, realtime, Postgres, Redis, CDN) | $300–800 |
| Gemini: archetype decisions and classification | $60–300 |
| Gemini: line banks and summaries | $30–180 |
| Gemini: live NPC chat (if enabled, capped at 20 replies/player/day) | $1,200–3,750 on Flash-Lite |
| News API | $0–200 |
| OTP SMS (e.g. 3k verifications/day × ~$0.007) | ~$630 |
| Prizes | **Your budget**: a fixed pool, e.g. ₦500k–₦2m/month |
| Spine licences | per animator (one-off/annual) |
| Lawyer (pre-launch opinions and T&Cs) | quote needed |

---

## 12. Risks
| Risk | Mitigation |
|---|---|
| Painting throughput is the bottleneck | Paper-doll NPCs, tile reuse, Blender pre-renders for vehicles, contractors |
| Gemini price rises (3.8 Flash doubles on 1 Jan 2027 [V]) or model retirement | Model ID kept in config; Flash-Lite as default; provider abstraction layer; rules fallback for everything |
| Legal blocks prizes or the real-money marketplace | Both are behind flags; the game stands without them |
| Slang or cultural misfires | Native-speaker review gate (Story Bible §10); community feedback |
| Scam and solicitation waves | Verified tiers, pre-moderation, human moderators from beta |
| The competitor copies the story idea | We ship polish, characters and an ongoing story cadence; the IP is ours |

---

## 13. What I need from you to start M0
1. **Approval of this proposal** (or changes).
2. **Answers to the open questions** below, or OK to proceed on my [A] defaults.
3. Who paints (or approval to brief contractors), and a test phone or two.
4. Later, not now: a Gemini API paid account (Google AI Studio or Vertex AI), and a CAC company
   for payments. **I'll ask before any sign-up or spend.**

## 14. Defaults I'll use unless you say otherwise [A]
| Open question | Default |
|---|---|
| Real-naira marketplace | Game money only at MVP; real lane later after legal and licensing |
| Sell game currency? | **No** at MVP (avoids the competitor's black-market problem); revisit with cosmetics-only IAP |
| Age rating | 18+ |
| Phone verification | Required for public posting, gigs, voting, prizes |
| Prize budget | Prizes off until you set a budget and legal clears |
| Real places | Real neighbourhoods OK; all businesses, venues, agencies and people fictional |
| Platform | Web/PWA first; Android wrapper later |
| AI model | Gemini (D-003). Default `gemini-3.1-flash-lite`; test `gemini-3.8-flash` for Pidgin writing quality; you choose |
| Languages | English + Pidgin at launch; Yoruba/Igbo/Hausa UI later |

---

## Sources (checked 2026-10-14)
- **Gemini pricing:** [official page](https://ai.google.dev/gemini-api/docs/pricing) (updated 2026-10-14)
- **FCCPC:** [draft Sales Promotion (Amended) Regulations 2026](https://fccpc.gov.ng/draft-sales-promotion-amended-regulations-2026/), [law firm summary](https://manifieldsolicitors.com/fccpc-sales-promotion-regulation-2026/), [Nairametrics on the AI marketing rules](https://nairametrics.com/2026/10/03/fccpc-moves-to-regulate-ai-marketing-businesses-face-n100-million-penalty/)
- **Lottery ruling:** [Aluko & Oyebode on the Supreme Court lottery ruling](https://www.aluko-oyebode.com/insights/nigeria-lottery-act-supreme-court-ruling-2024/), [BusinessDay analysis](https://businessday.ng/news/legal-business/article/regulation-of-lotteries-in-nigeria-review-of-the-supreme-courts-decision-and-its-implications/)
- **Payments:** [Paystack compliance (Nigeria)](https://support.paystack.com/en/articles/2123970), [Paystack transaction splits](https://support.paystack.com/en/articles/2132802), [Flutterwave split payments](https://developer.flutterwave.com/docs/collecting-payments/split-payments)
- **Data protection:** [NDPA/GAID overview (LawPavilion)](https://blog.lawpavilion.com/ndp-act-2023-gaid-2025-a-comprehensive-guide-to-nigerias-new-data-protection-landscape), [GAID analysis (Mondaq)](https://www.mondaq.com/nigeria/privacy-protection/1700306/gaid-2025-unpacked-series-ii-data-protection-officers-mandatory-consents-and-emerging-technologies)
- **Airtime/data APIs:** [VTpass commission docs](https://vtpass.com/documentation/understanding-how-vtpass-commission-works/), [Reloadly airtime pricing](https://support.reloadly.com/airtime-pricing)
- **OTP SMS:** [Nigeria OTP SMS pricing (vendor blog)](https://www.messagecentral.com/blog/otp-sms-pricing-nigeria)
- **News APIs:** [news API comparison](https://www.socialcrawl.dev/blog/best-google-news-apis-2026)
- **Engines and animation:** [PixiJS vs Phaser](https://cortance.com/answers/phaser-js/phaser-js-vs-pixijs-which-is-better-for-2d-web-games), [Spine runtimes licence](https://jp.esotericsoftware.com/spine-runtimes-license)
