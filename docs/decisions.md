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
