# Art sources (Naija Street Life)

Painted source files live here (PSD, Krita, Blender files for vehicle renders, Spine projects).
Exported game files go to `apps/client/public/assets/`. See the Phase 3 proposal §4.

## Status (M0)
The game currently draws **placeholder art in code** (`apps/client/src/game/art/`) so the style
test runs without downloads. Each placeholder will be replaced by painted art with the same name
and anchor point.

## Naming
```
nsl_{type}_{name}[_{variant}][_{dir}][_{frame}].{ext}
type = char | npc | veh | prop | tile | fx | ui | bg
dir  = s | se | e | ne   (mirror for sw, w, nw)
```
Atlases: `nsl_atlas_{set}_{tier}.webp` + `.json`, tier = `lo | md | hi` (0.5x / 1x / 2x).

## Tile and anchor rules
- **Ground tiles:** 128×64 px diamonds at 1x.
- **Buildings:** anchored at the footprint's back corner (tile 0,0 ground point).
- **Props and characters:** anchored at the ground contact point (feet / base).
- **Characters:** 48×76 px frames at 1x.
- **Lighting:** paint in daylight. Night and NEPA lighting is an overlay in the engine, so never
  paint shadows darker than value 20%.
- **Large binaries:** go through Git LFS once real art arrives.
