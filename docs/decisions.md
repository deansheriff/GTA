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
