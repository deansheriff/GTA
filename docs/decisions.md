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
