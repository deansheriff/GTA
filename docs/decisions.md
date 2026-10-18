# Naija Street Life — Decision Log

Owner decisions that change scope or direction. Newest last.

## D-001 · Art direction: 2D painted, The Omins style · 2026-10-14
**Decision:** The game is 2D, using hand-painted art in the style of The Omins
(Steam app 2397750). The view is top-down at a 3/4 angle, with chunky readable
silhouettes, a warm saturated palette and soft painted ground. It must feel
smooth. There is no real-time 3D in the browser.

**Why:** 3D is too heavy for browsers, especially on low-end phones and slow
Nigerian networks.

**What this changes in the brief:**
- The renderer is a 2D WebGL/canvas sprite renderer, not a 3D engine. The stack
  options in the Phase 3 proposal will be 2D-only.
- "Blender asset pipeline" becomes a 2D art pipeline. The Phase 3 proposal
  covers two ways to make the art:
  1. Paint everything directly as 2D.
  2. Model and pose in Blender, render to sprite sheets with a painterly
     shader, then paint over.

  Either way, the game ships texture atlases (WebP/AVIF) instead of glTF/GLB.
  Draco compression and polygon budgets no longer apply. They are replaced by
  atlas size, frame count and per-district download budgets.
- Graphics settings map to 2D equivalents:
  - shadows → baked or blob shadows on/off
  - effects → particles, weather and NEPA lighting overlay
  - draw distance → tile-chunk streaming radius
  - texture quality → atlas resolution (0.5x/1x/2x)
  - frame-rate cap and data-saver mode stay as specified
- "Smooth" means a 60 fps target on mid-range phones, sprite animation at
  12–24 fps on a smooth camera, skeletal animation such as Spine or DragonBones
  for the heroes (to evaluate), and no layout jank.

**Advantage over the reference game:** the reference is a 3D stock-kit city
(Three.js plus generic low-poly kits). Custom painted Lagos art is lighter and
more distinctive, and that difference is a selling point.

## D-002 · Phase 2 approved · 2026-10-14
**Decision:** The owner replied "proceed" to the Phase 2 report and Story Bible v0.1.

**What this approves:**
- Story Bible v0.1, including the §8 safety reworks.
  - The main rework turns "Small Small Money" into "Following the Money".
- Moving on to Phase 3, the proposal.

**What this does not cover:** the open questions in report §8 are still unanswered.
The Phase 3 proposal uses the defaults in its §14 until the owner answers them.

## D-003 · Drop Jev; use Gemini for NPC AI · 2026-10-14
**Decision:** The owner chose Google Gemini for NPC conversations and asked to
remove Jev (TypeSafe).

**How NPC AI works now:**
- **Decisions** run on rules and utility AI, plus cached Gemini calls at the
  archetype level.
- **Dialogue** comes from Gemini, in two modes:
  - Ambient banter is batch-generated and reviewed.
  - Optional live "Talk to NPC" chat is limited to Verified players, capped
    daily, and runs behind a flag.
- **News** categorisation, sensitivity scoring and summaries run on Gemini.
- **Moderation** uses rules first, with Gemini as the second pass.

**Default model:** `gemini-3.1-flash-lite`, $0.25 / $1.50 per M tokens, with
batch at half price. We evaluate `gemini-3.8-flash` for writing quality; its
price doubles on 1 Jan 2027.

**Data handling:** paid tier only. The free tier may use data to improve
Google's products. Sending player data to Google needs an NDPA review ⚖️.

**Trade-off:** per-NPC live decisions become about 10× more expensive than with
Jev. To keep costs down, the design moves to rules plus cached archetype
decisions, so ambient behaviour stays cheap. Every AI path has a rules or canned
fallback.

**This replaces** the brief's requirement 6 ("Jev AI for NPC decisions").

## D-004 · Match The Omins' look: top-down 3/4 camera and painted art · 2026-10-14
**Decision:** The owner rejected the M0 diamond-isometric, code-drawn look. They asked for
The Omins' style to be matched, and to take inspiration from their earlier prototype
(github.com/deansheriff/Naija-GTA).

**What changes:**
- **Camera:** diamond isometric becomes **top-down 3/4**. The ground is seen from
  above; buildings and people show their roof or top plus their front. Movement
  and driving map straight to screen directions.
- **Ground:** visible tiles become **one continuous painted terrain**, streamed in
  chunks with soft blended grass, laterite, dust and roads.
- **Art treatment:**
  - Painted gouache-style fills with **thick dark ink outlines**.
  - A muted, earthy, grimy palette and darker vignetted edges.
  - Small big-headed characters, and more of them on screen.
- **Art source:** AI-generated painted assets, the same approach the earlier
  prototype used, delivered as compressed WebP atlases. Code-drawn art stays
  only as a fallback.
  - **We never copy The Omins' assets** and never feed its screenshots to a generator.
  - Every prompt is recorded in `docs/art/PROVENANCE.md`.
- **Vehicles:** top-down painted sprites that rotate smoothly, so free driving
  works in any direction.

**What doesn't change:** the story, every feature (F1–F8), the backend, the
settings, the UI and the data budgets. The 3 MB first-install budget now has to
cover real art, so all art ships as WebP atlases at three quality tiers.

**Lessons from the earlier prototype:**
- Keep: AI-painted modular parts (separate building shells and roofs, so roofs
  fade to show interiors; separate tree trunks and canopies, so canopies can sway
  in the wind); recorded prompts; pedestrians who walk past instead of milling
  around.
- Avoid:
  - A side-on camera, which rules out free driving.
  - Flat code-drawn ground.
  - A ~21 MB first load (Godot engine plus game pack). We stay under 3 MB.

## D-005 · Android-only, built with Godot 4 · 2026-10-14
**Decision:** The owner chose to make Naija Street Life an **Android app only**, built
with **Godot 4.6.3** (GDScript) using the **Compatibility renderer** (OpenGL ES 3.0).
That renderer runs on low-end phones.

**Why Godot:**
- Strong 2D tools, and free with no royalties.
- Small APK.
- It runs well on 2 GB-RAM Android phones.
- The owner's earlier Godot prototype (deansheriff/Naija-GTA) and its local toolchain
  can be reused.

**What changes:**
- The Phaser/Preact web client (`apps/client`) and `packages/shared` are removed. Git
  history keeps them.
- The game lives in `game/`, a Godot project.
- **Kept:** the TypeScript server (`apps/server`), the docs, the Story Bible, the
  feature designs and the Gemini art pipeline (`tools/art`).
- Art ships as Godot-imported textures instead of web files. The terrain becomes a
  shader that blends painted textures through layout masks.
- **Data budget becomes an app-size budget:**
  - base APK ≤ 60 MB
  - extra districts delivered on demand (Play Asset Delivery)
  - idle network use stays ≤ 1 MB/hour
- **Google Play rules to plan for:**
  - Digital goods and game currency must use Play Billing (15–30% fee).
  - Real-world gig services can use Paystack or Flutterwave.
  - Data and airtime prize games must also comply with Play's real-money and
    contest policies ⚖️.
- **Build toolchain:**
  - Portable Godot in `.tools/godot` (git-ignored, copied from the owner's machine).
  - Android SDK at `%LOCALAPPDATA%\Android\Sdk`.
  - JDK 17 at `C:\Program Files\Java\jdk-17`.

**Supersedes:** the client options in the Phase 3 proposal §3.1 (Phaser + Preact),
and the web/PWA-specific parts of §4.3 and §8.

## D-006 · Self-hosted server on Coolify behind Cloudflare · 2026-10-14
**Decision:** The multiplayer server runs on the owner's self-hosted **Coolify**,
exposed through **Cloudflare**, the same setup used for the earlier prototype.

**The stack** (`compose.yaml`):
- `app`: Node 22, Fastify, a WebSocket endpoint at `/ws`, the API at `/api/*`.
- `postgres`: PostgreSQL 17 on a private volume.

**Secrets:** `POSTGRES_PASSWORD` and later `GEMINI_API_KEY` live only in Coolify. The
APK holds no secrets; each phone gets a guest token from the server.

**Realtime design:**
- Rooms per district, 80 players each, overflowing to `yaba-2` and onwards.
- Movement is validated against speed limits (anti-teleport).
- Each player receives only nearby players who changed (interest radius
  1,600 px, 10 Hz), so standing still costs about 0 bytes.
- The server pings every 30 s to stay inside Cloudflare's idle timeout.

**Verified:**
- Locally: unit and WebSocket integration tests, a smoke test, and the Godot game
  showing three bot players with name tags.
- CI builds the Docker image and smoke-tests it against Postgres.
- The real Coolify deploy is done by the owner (docs/COOLIFY.md).

## D-007 · New setting: a tropical island instead of Lagos · 2026-10-14
**Decision:** The owner asked for a new vibe: the game is set on a **tropical island**
instead of Lagos, with everything else unchanged.

**Interpretation (owner to confirm):**
- A **fictional Nigerian island off the coast**, with the same people, culture,
  Pidgin, danfos, POS stands, NEPA and the Up NEPA! story.
- Working name **"Ayo Island"** (Yoruba *ayọ̀*, "joy"; pending native-speaker review).
- Real Lagos neighbourhoods are no longer used as settings, which also removes open
  question 6 in the Phase 2 report.

**Location mapping** (the story is unchanged; only places move):

| Before (Lagos) | Now (Ayo Island) |
|---|---|
| Yaba junction (M0 map) | **Ayo Town**: the market junction in the island's centre |
| Lekki owambe event centre | **Paradise Gardens**, a beachfront event centre |
| Ikoyi / Banana Island wealth | **Hilltop Estate** |
| Oshodi, Obalende, Mushin danfo routes | The **ring road** around the island, the ferry jetty and the fish market |
| Agbado-Ketu Central LGA | **Ayo Island Local Council** (the Chief's election) |
| "The mainland" | Off-screen, across the water: the ferry, and KC's Japa dream |

**What changes:**
- **Map:** a coastline with animated sea, beaches and a jetty, inside the same
  40×30-cell world. The sea blocks walking and driving.
- **Art:** new island assets: sand, beach shacks, fishing huts, canoes, nets, beach
  bar, coconut palms. The existing town art stays, since island towns have zinc-roof
  shops too.
- **Story Bible and mission list:** place names follow the table above. Scenes and
  jokes stay. A full text pass happens with the deliverable-4 scripts.

**What doesn't change:** the features (F1–F8), the server, the camera and art style
(D-004), the platform (D-005), hosting (D-006), the characters and the plot.

## D-008 · Keep the original Lagos place names on the tropical island · 2026-10-14
**Decision:** The owner asked to keep all the original names (Yaba, Lekki, Ikoyi and
the rest). The world is a **tropical-island Lagos**: mainland districts in the north
and west, the lagoon and its bridges, and Lagos Island, Ikoyi, Victoria Island and
Lekki along the beaches.

**What changes:**
- "Ayo Island" and the D-007 renaming table are withdrawn.
- The story uses its original locations: the Lekki owambe, KC's Yaba room, Ikoyi
  wealth, the Oshodi and Obalende danfo routes, and the Agbado-Ketu Central LGA
  election.

**What stays:**
- Real neighbourhood names are used as settings.
- Every business, venue, agency and person stays fictional (Story Bible §5).

**Owner instruction:** build continuously to production-ready, mark each milestone,
ask only when input is needed, and make no APK builds until the game is done.

## D-009 · Story engine choices for M3 · 2026-10-14
**Decision (engineering, within the approved proposal; owner can override):**
- **Switching unlocks after the Prologue (P4),** not after 1.5, so each hero's Act 1 mission is
  reachable. The phone app is called "Switch" until 1.5, when KC creates the "Family Meeting 🔥"
  group and the app takes that name (the story beat in the mission list is kept).
- **Only Tunde drives Baba God Dey.** Aunty Boss and KC walk, hail a paid keke from the phone, or
  (Aunty) ride free once a day on the Ajo Network. This keeps the heroes distinct and the bus
  Tunde's.
- **Act 1 1.1 is shortened** from three full Oshodi–Obalende loops to one loop and a return over
  the bridge (the map is large; three loops tested at ~10 minutes of pure driving).
- **The whole map stays open after the Prologue** (the mission list's "free roam opens: Yaba,
  Lekki, Oshodi" is not used as a lock).
- **Story money (₦s) is separate** from the wallet until the credits (Bible §9.7).

## D-010 · Act 2–3 and ending choices for M4 · 2026-10-14
**Decision (engineering, within the approved proposal; owner can override):**
- **Ending priority:** B (old notes kept) → C (KC chose to go) → D (ten diary pages and the stitch
  key) → A (honest). A is the fallback; its "full" version needs tried-honest-or-5-evidence, notes
  handed over and family trust ≥ 60. Keeping the notes always means B, so the Hustle path never pays.
- **Diary pages:** 1 from counting in 1.5, 2 in 2.4, 3 in 2.8, and 4 hidden in the world after
  Act 1 = 10. The Secret ending therefore needs "count it first" in 1.5 and all four hidden pages.
- **2.3 Danfo Chase** ends in Surulere (the shortest route that still crosses busy roads).
- **3.1 Campaign Season** is played as Tunde driving Teacher's campaign bus to six bloc stops.
- **Bribes** are offered as choices in 3.1 and always lower the bloc (Bible §8.2).
- **Replay:** after the credits the story can be restarted while keeping wallet, skills and found
  pages, so all four endings are reachable without a new save.

## D-011 · Online-feature choices for M5 · 2026-10-14
**Decision (engineering, within the approved proposal; owner can override):**
- **One SQL codebase:** production uses PostgreSQL; development and tests use PGlite (Postgres
  compiled to WebAssembly). The in-memory store is gone, so tests exercise the real SQL.
- **Market wallet:** the save file is client-side and can't hold escrow, so gigs, nomination fees
  and payouts use a server-side "market ₦" balance. Players move game money in and out, capped at
  ₦50,000 a day, with 5% tax on the way out. That limits farming and trading.
- **Chat gate:** guests can chat 24 hours after their account is created, or immediately once
  phone-verified. Links need verification. This follows the proposal's identity tiers without
  requiring an SMS provider for basic play.
- **SMS:** a generic webhook (`SMS_WEBHOOK_URL`). The owner connects any Nigerian SMS gateway
  without code changes. Without a provider and `PHONE_PEPPER`, OTP is switched off rather than faked.
- **Elections at launch:** one office (ward councillor) per district, weekly, with two fictional
  NPC candidates rotating per week. Market Chairperson and LG Chairman come later.
- **Gig proof of work:** the server accepts a mini-game score no sooner than `GIG_MIN_SECONDS`
  (default 60) after taking the gig. This is a light anti-farming check; a server-side replay
  check would be a later upgrade.

## D-012 · AI and news choices for M6 · 2026-10-14
**Decision (engineering, within the approved proposal; owner can override):**
- **Gemini via the Interactions API** (`/v1beta/interactions`, structured JSON output), model
  `gemini-3.1-flash-lite` by default, with a $2/day hard cap until the owner sets another.
- **Banter is reviewed by a person** before publishing (proposal F8). Owners with a moderation
  team can turn on auto-publish; lines still pass every code guardrail first.
- **Politics, security, tragedy and health are excluded from banter by default** (proposal:
  tragedies excluded and no opinions on elections). Any story with a sensitivity flag from
  rules or the model is excluded too.
- **Live NPC chat ships switched off.** It's capped, verified-only and logged when enabled.
- **No news outlets are pre-configured.** Which outlets to use, and whether their terms allow
  headline-and-link use, is the owner's decision (⚖️).
- The batch API (50% cheaper) can replace per-story calls later; at a few dozen stories a day,
  the standard API costs cents.

## D-013 · Prizes, real money and telemetry for M7 · 2026-10-14
**Decision (engineering, within the approved proposal; owner can override):**
- **No real-money code paths ship.** Prize tickets exist, but the prize pool is ₦0 and prizes are
  off. Real-naira gigs are a hard 403. Both need legal sign-off and a provider (🔒 owner), which
  can't be done from code.
- **Anti-cheat by replay:** the server keeps the challenge's scoring key and scores the
  client's input log. This beats trusting a client score, and needs no shared RNG between
  Godot and Node.
- **Telemetry is opt-in** (default off), anonymous and whitelisted. The age gate is
  self-declared, with phone verification for prizes; a lawyer must confirm that's enough.

## D-014 · Street clashes and the living title · 2026-10-15
**Owner request:** "players can engage in a fist fight due to collisions… pick… not fighting and
apologise… this should not work against other online players who still choose to fight", and
"animate the first screen… do not change the scene".
**Decision (engineering):**
- **NPC clashes** happen outside missions only, with a 25 s cooldown.
  - Apologise always ends it: 65% accept; otherwise the driver asks ₦1,000 for the bumper, and you
    can pay or keep apologising.
  - Fight runs the slapstick `fist_fight` mini-game; there is no blood (Story Bible).
- **Online clashes:** the server checks the contact against its own positions.
  - Both players choose within 10 s; no answer counts as peace.
  - If either player picks Fight, both fight the same server-made sequence, and the server
    re-scores each input log.
  - Effects are cosmetic only (needs and stats); no money changes hands.
  - Limits:
    - 3 min per-pair cooldown.
    - 8 clashes an hour.
    - Blocks are respected.
    - Every clash is logged (`GET /api/admin/clashes` shows aggressors against peaceful players).
  - A player who is in a mission or a menu auto-apologises. If they're jumped anyway, they can't
    answer, so the fight costs them nothing.
- **Title animation:**
  - It is the same painting, with no new scene.
  - Moving figures are new painted cut-outs: `spec-title.json`, about $0.04, generated with our
    own splash as the only reference.
  - The keke's grille badge was painted out (`tools/art/title_sprites.mjs`).
- **Follow-up, same day (owner feedback):**
  - **Collisions are mostly quiet.**
    - A hard hit brings the other driver out only half the time, at most once a minute, and
      never mid-mission.
    - Wall-crash quips are occasional, not on every bump.
  - **Blocking the road gets you beaten.** If you stop in a lane with a clear road ahead
    (queuing in traffic doesn't count), the queue behind you starts honking after 4 s.
    - After 9 s, up to two drivers get out, walk to your door and drag you out into a forced fight.
    - This happens in story missions too. The exceptions are cut-scenes, mini-games, interiors,
      chases and Tunde's own Wahala Mode.
    - Driving off before they reach you means you escape.
    - A loss costs energy, hygiene and BP; a win gives fun.
  - **Players can drag players out.**
    - On foot next to another player's vehicle that has been still for at least 1.5 s, the action
      button reads "Drag NAME out!".
    - The server checks that you're on foot, they're driving, the vehicle has stopped, and you're
      within 170 px. The fight then starts straight away, with no choice card.
    - The same cooldowns, hourly cap, blocks and logging apply.
  - **Traffic steers around a parked danfo** instead of driving through it.

## D-015 · Aerial title, solid world, phone-friendly HUD · 2026-10-15
**Owner request:** "Make it an aerial view of the map with planes flying over the islands and
waves crashing on the shore with birds flying", plus four bug reports.
**Decision (engineering):**
- **Title:** the painted street title (D-014) is replaced by tropical-island Lagos from the air.
  - The island image is the game's own map, rendered from above: `main.gd --bake-aerial`
    writes `art/title/aerial.png`, a shore-distance map and the sights to visit. Re-bake it after
    map changes. It isn't generated art, so it isn't in the art ledger.
  - The water is all shader: swells, surf on every beach and glints.
  - Moving over it: airliners with contrails, a light plane, a news helicopter, seagull flocks,
    boats with wakes, clouds with shadows, and danfos and cars on the real roads.
  - The painted street cut-outs are removed from the game; they stay in the spend ledger.
- **Action button** ("Enter danfo"): it was mostly off-screen on phones (anchored with
  `position` before the screen had a size), so you couldn't get back in after a drag-out. HUD
  corners are now pinned with offsets (`ui/hud_layout.gd`).
- **Settings:**
  - Modal cards get a pinned Close button.
  - The Android back button and Escape close the top dialog, phone or map.
  - Back only quits when nothing is open; before, it quit the game.
- **Street poles:**
  - Solid props now have real collision circles. Before, each blocked its whole 64 px cell, an
    invisible wall that reached into the road.
  - The bus checks its whole body against walls and props.
  - A bus that's already touching something may always move away from it.
  - If the stick has been held for 1.5 s with no movement, it hops to the nearest clear spot.
- **Solid traffic and people:**
  - A traffic move that would create or deepen an overlap is undone. The old "squeeze through
    after 4 s" is gone; gridlocks clear by backing up.
  - Traffic stops for people in the road.
  - The crowd and the player are pushed out of vehicles and apart from each other
    (`world/bodies.gd`).
  - The demo measures the worst traffic overlap.

## D-016 · Street life, ownership and online play (M9–M11) · 2026-10-15
**Owner request:** the 23-item gameplay list (fuel to achievements).
**Decision (engineering):** all 23 are built as game systems in `game/street/` (client) and
`apps/server/src/street_online.ts` (server), with the saved state in the `Street` autoload and
every line, price and award in `game/data/street.json`. That file's Pidgin is pending native-speaker
review.

**Story first.** Anything that could derail a mission waits while one is running: checkpoints,
the Task Force, floods, running dry, damage slowing the bus, hustles and random crash wahala.
The same applies during cut-scenes, mini-games, interiors and chases. Story autoplay still
reaches an ending.

**Fictional everything.**
- The Road Marshals, the Motor Park Union, the Area Task Force, PetroNaija, Miracle FM,
  Gbedu 98.1, KekeGo, the Zenko and Glowphone phones and all the goods are invented.
- No real agency or brand names are used.

**Money and fairness.**
- Single-player money stays in the save.
- Online money is the existing "market ₦" server wallet:
  - co-op pay,
  - crew registration (₦5,000),
  - trading.
- The server never trusts a client's position or result:
  - **Races:** the finish order comes from server positions. Warping is a disqualification.
  - **Co-op:** both players are paid only if the server saw them travel together for at least 70%
    of the ride.
  - **Crew route points:** count only when the server sees you, driving, at the route's
    destination. One run every 2 minutes.
  - **Ranked bouts:** re-scored like clashes. Elo, K = 32.
  - **Trading:** you trade in the district the server has you in. 3% levy on sales; prices drift
    back 4% an hour.
  - **Gist posts:** fixed templates only, plus a short moderated detail. One post every 20 s,
    40 a day. Blocks are respected.

**Visible style.**
- Headwear, crew tag, bus paint and slogan travel in the player's look.
- A new `look` realtime message re-introduces you to nearby players.
- Painted hero sheets can't be recoloured safely except Tunde's red shirt
  (`tools/art/hue_stats.mjs`), so outfits show as headwear for everyone.

**Server-side game facts.** `tools/export_game_data.mjs` generates `apps/server/src/game_data.ts`
(landmarks, routes). Re-run it after map or route changes.

**Also fixed.** "New game" now really resets: autoloads used to survive the scene reload.

## D-017 · Graphics and UI polish (M13) · 2026-10-16
**Owner request:** implement the proposed graphics and UI list.

**Art** (`spec-m13-polish.json`, $0.16; total spend $2.41 of $10):
- Six more vehicle types: taxi, SUV, pickup, box truck, fuel tanker and city bus.
- Animals and street props: goats, hens, a dog, a cat, a clothesline and a suya grill.
- Four building looks: salon, chemist, bukka and a block of flats.
- Fight poses for the three heroes: guard, punch, duck and knocked down.

**Graphics:**
- **Walking:** townsfolk legs move (`shaders/walk.gdshader`).
- **Fights:** the heroes use the painted fight poses.
- **Night:** headlight beams and tail lights on vehicles near the camera
  (`street/vehicle_lights.gd`).
- **Street life** (`street/street_life_fx.gd`):
  - animals that wander and scatter from vehicles,
  - clotheslines, evening suya smoke and steam from food places,
  - lane lines, zebra crossings, potholes that hold puddles after rain, and litter.
- **Buildings:** fictional roadside signboards, and varied building looks on the same footprints.
- **Shadows:** soft contact shadows.
- **Colour:** a time-of-day colour grade (`shaders/grade.gdshader`, off when effects are off).
- **Camera:** pulls back with speed.

**UI:**
- **Layout:** a top-right row of Pause, Phone and Settings, clear of the ability buttons, with
  56 px touch targets.
- **Fonts:** one type family with a display face (`ui/ui_style.gd`). These are variations of the
  engine font; a licensed display font can replace it in one place.
- **Messages:** stacked and colour-coded by kind (`ui/toast_stack.gd`), with a centred banner
  for big moments.
- **Money:** the counter rolls to the new amount, and the change floats up beside it.
- **Celebrations:** an unlock ribbon with confetti (`ui/celebrate.gd`) for awards, buses,
  houses, generators, crews and race wins.
- **Phone:** a wallpaper, a dock of four apps and notification badges.
- **Minimap:** shows checkpoints, Task Force vans, floods and today's event.
- **Safe areas:** respected on phones with notches.
- **Loading:** rotating tips while the city loads.
- **Pause menu** (`ui/pause_menu.gd`): Android back pauses the game when nothing else is open.

## D-018 · Garage, car theft and control schemes (M14) · 2026-10-17
**Owner request:** "a Garage where they can park their cars… the GTA mechanism where users can
steal cars… choice of control… control sensitivity."

**Vehicles** (`street/garage.gd`):
- The main vehicle node wears whatever you drive (`Street.current`).
- Every vehicle you leave stays parked where you left it, solid and saved. Baba God Dey is
  always either what you're driving or parked somewhere, with a minimap marker.
- Up to three abandoned stolen cars stay parked; older ones are towed.

**Car theft:**
- Walk up to a traffic vehicle moving slower than 140 px/s and take it ("CARJACK!"). Okadas
  and kekes count too; your own fleet buses don't.
- What happens next:
  - The driver is dragged out.
  - 30% of the time he fights for the car (12% for an okada or keke). Lose and he drives it away.
  - Area heat +1.2, reputation −3, and a gist post.
- The car is flagged stolen:
  - At checkpoints, settling costs three times as much.
  - If it's impounded, it's confiscated rather than towed to the yard.
- Mushin chop shop: sell a stolen car (by type, minus damage) or respray it clean (₦3,000).

**Garage:**
- It's by your home and holds 1, 2, 3 or 5 cars depending on your house.
- Drive in to park. On foot, take one out.
- Baba God Dey parks outside, never in the garage.

**Story first:**
- A mission puts you back in Baba God Dey.
- Danfo runs need the bus.
- Other heroes can drive any car except Baba God Dey.
- Car theft is disabled during missions, cut-scenes and rentals.

**Controls** (`ui/controls.gd`, Settings → Controls):
- **Joystick:** as before.
- **Steering buttons:** ◀ ▶ on the left, GAS and BRAKE on the right. GAS and BRAKE work with
  several fingers at once.
- **Tilt to steer:** the accelerometer steers, with GAS and BRAKE.
- **Sliders:** stick sensitivity, dead zone, steering sensitivity, tilt sensitivity and
  pinch-zoom sensitivity.

**Art fix:** `veh-sheet-2` didn't fit a grid. It's re-cut by measured boxes
(`tools/art/crop_vehicles2.mjs`), and the SUV is made from the car art, darkened.


## D-019 · A 3D prototype of one district, with Meshy models · 2026-10-17
**Owner request:** "Can we make this into a 3D game with glossy graphics?… Let's use meshy to
build a 3D prototype of one district."

**What it is:** a drivable 3D Yaba (`game/proto3d/district3d.tscn`), built from the same map
data as the 2D game. It doesn't replace the 2D game: open it from the title screen
("3D prototype (Yaba)") or with `-- --proto3d`; "Back to the 2D game" or Esc returns.
- Ground: one MultiMesh per surface type (road, walkway, grass, water), using the game's
  painted ground textures, with lane lines drawn along the road graph.
- Buildings: each footprint gets a solid collision box and a row of Meshy shop houses or
  bungalows at their natural proportions. Without the models it falls back to boxes with roofs.
- The player drives the Meshy danfo (arcade handling, chase camera). Traffic alternates danfos
  and kekes on the road graph, and Tunde models stand on walkways.
- Look: procedural sky, filmic tonemap, glow, sun shadows, glossy car paint. It runs at 60 fps
  on the Compatibility renderer on the dev PC.

**Models:** five Meshy models (see docs/art/PROVENANCE.md). Free-plan models are CC BY 4.0,
so they're credited on the credits screen. They're slimmed for phones with
`tools/art/glb_slim.mjs` (6–12k triangles, 1024 px textures, under 1 MB each).

**Not done yet:**
- Not tested on a phone.
- Tunde isn't rigged (he stands still). Rigging needs a model in an A-pose.
- Only one district; outside it is open land behind invisible walls.
- None of the 2D game's systems (story, hustles, online) run in 3D.

**Going fully 3D would mean** porting each of those systems and the camera and controls, and
making many more models. Meshy text-to-3D retires on 31 October (it moves to Meshy's Agent),
and the free plan allows 10 downloads a month.


## D-020 · 3D Lagos: the whole island in 3D, with Meshy Pro assets · 2026-10-18
**Owner request:** "I just subscribed. Use this to create all the assets we'll need. Including
roads, maps, vehicles, NPCs and other things. Then continue building."

**Assets** (`tools/art/meshy.mjs` + `tools/art/meshy-spec.json`, Meshy API on the owner's Pro plan):
- 54 models in one resumable, budget-capped run, which cost 900 credits:
  - 12 rigged people. A-pose generation fixed the "hands and shirt stuck to the body" rig.
  - 10 vehicles, 14 building types and 18 props.
- Each model is Meshy 6 Lite remeshed to a phone budget, then textured, rigged if it's a person,
  downloaded and slimmed.
- Every person brings their own walk and run. One shared 10-clip action pack (idle, talk, argue,
  wave, punch, hit, dead, sit, phone, cheer) plays on all of them, because Meshy rigs share one
  24-bone skeleton.
- Prompts are unbranded and the agencies fictional. Pro-plan models are privately owned. The
  first free-plan models (danfo, shop, bungalow) stay CC BY and are credited.
- The key is `MESHY_API_KEY` in the git-ignored `.env`. Raw downloads and the run state stay in
  the git-ignored `art-src/meshy/`.

**Roads and the map** are built in code from the 2D map data rather than generated, because
Meshy makes objects, not road networks (`world3d/terrain3d.gd`):
- Roads are ribbons that follow the real road curves, with white edge lines and yellow centre
  dashes. The lines stop short of junctions.
- Pavements are raised 12 cm, which gives every street a kerb. Road shoulders are laterite.
- The lagoon and sea use a moving glossy water shader. The sea runs to the horizon.

**The 3D city** (`world3d/`, opened from the title screen as "3D Lagos (preview)"):
- **Map coverage:** the whole island, with 271 buildings and 600 props. Each building's model is
  chosen by its type, district and landmark:
  - Lekki and Ikoyi get duplexes and towers.
  - Mushin and Agbado-Ketu get shacks.
  - Landmarks get the church, motor park, market, station or office tower.
- **Building details:** each building faces its road, carries its painted shop sign and keeps
  its generator.
- **Draw distance:** far buildings and props switch off, hidden by haze.
- **On foot:** walk or run as Tunde.
- **Vehicles:** take any vehicle with E or ENTER; traffic drivers get dragged out. Eleven vehicle
  kinds each have their own handling. 26 AI vehicles keep to the right-hand lane and slow for
  whatever is ahead.
- **Townspeople:** 36 of them stroll the pavements, chat and phone, and dive out of the way of a
  speeding vehicle.
- **Danfo runs:** every district has a bus stop with people waiting.
  - Stop at one in the danfo to load 6 to 14 passengers.
  - Follow the beacon and the minimap to the next stop to get paid.
  - The money goes into the same wallet as the 2D game.
- **Time:** the clock is shared with the 2D game; sun, sky and haze follow it from day to night.
- **Saving:** while you're in 3D, saves keep the 2D world exactly as it was saved. Money and time
  carry both ways. The title saves first, and the 3D scene saves after each paid run and on exit.
- **Performance:** 60 fps on the dev PC with the Compatibility renderer.

**Not done yet:**
- No phone test.
- The story, missions, hustles and online features still run only in 2D.
- No interiors and no night lights.
- 3D art adds about 45 MB to the project; check the APK size next.

**M17 additions (2026-10-18):**
- **Graphics settings:** 3D follows the graphics preset.
  - Shadows are off on Low and short-range on Medium.
  - Glow follows the effects setting.
  - Draw distance, haze, traffic (14 to 28) and crowds (up to 36) scale with the preset.
- **Camera:** drag on the screen (or right-drag the mouse) to look around. The camera stops at
  walls instead of entering buildings.
- **Streetlights:** 66 solar streetlights stand along the main roads, batched per 48 m area.
  After dark their lamps glow, the six nearest you cast real light, and your vehicle gets
  headlights.
- **Yard details:** water tanks behind some houses, and plastic tables outside canteens, shops
  and bars.
- **Checkpoints:** four roadside checkpoints use the 2D game's crews, lines and prices, with
  barriers and officers.
  - Pull up slowly to settle the roger.
  - Blast through and you pay the fine, and Area Heat rises.
  - They move every game day.


## D-021 · 3D only, and the new story "Èkó Ò Ní Bàjẹ́" · 2026-10-18
**Owner request:** "remove the 2D mode. It's no longer needed. I want to change the story. Use
the story I provided instead. Disregard the first story. Start building to production."

**What changed:**
- **The 2D game is gone:** `main.gd`, the actors, the 2D world (streaming, crowds, traffic,
  interiors), the 2D HUD and phone, the 2D story engine and its missions, the street-host
  modules, the canvas shaders, the old minigames and about 27 MB of painted 2D art. Git history
  keeps all of it.
- **What 3D still uses:** the map data (`world/map_data.gd`, `world/layout.gd`), the autoloads
  (Life, Clock, SaveGame, Street, Settings, Sound, Net, Telemetry), the joystick, the dialogue
  box, the pause menu, notifications, UiStyle and the money-spray and quick-time minigames for
  later missions.
- **The new story:** the old "Up NEPA!" story and its docs were removed. The owner's document is
  [docs/story/eko-oni-baje.md](story/eko-oni-baje.md). The `Story` autoload was rewritten for
  this campaign: missions done, the big choices, items, Respect and Wanted.
- **The game boots into 3D** (`world3d/street3d.tscn`) at a main menu.

**Brands and agencies kept out of the game:**
- "Nokia 3310" becomes **Papa's old phone**.
- The Hiluxes become unbranded pickups, and Bigz's Benz will be an unbranded luxury saloon.
- LASTMA becomes **traffic officers**, and the BRT becomes a city bus.
- Real places stay as settings (UNILAG, LUTH, Oshodi and others).
- Tinubu Square isn't named in-game, because of the real politician's name.
- All other characters, parties and the newspaper are fictional.

**Native-speaker review:** every line of Pidgin, Yoruba, Igbo and Hausa is flagged for review.

**Credits:** "Story by Sheriff Usman", from the story document's byline.
