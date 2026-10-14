# Art sources (Naija Street Life)

Painted source files live here (PSD, Krita, Blender files for vehicle renders, Spine projects).
Processed game textures go to `game/art/` (imported by Godot). See the Phase 3 proposal §4 and decisions D-004/D-005.

## Status (M0)
The game currently draws **placeholder art in code** (`game/actors/`, `game/shaders/terrain.gdshader`)
so the style test runs before painted art exists. Each placeholder will be replaced by painted art with the same name
and anchor point.

## Naming
```
nsl_{type}_{name}[_{variant}][_{dir}][_{frame}].{ext}
type = char | npc | veh | prop | tile | fx | ui | bg
dir  = s | se | e | ne   (mirror for sw, w, nw)
```
Atlases: `nsl_atlas_{set}_{tier}.webp` + `.json`, tier = `lo | md | hi` (0.5x / 1x / 2x).

## Tile and anchor rules
- **Camera:** top-down 3/4. The ground is drawn from above; anything standing shows its top
  plus its front.
- **Ground:** seamless painted tiling textures (dirt, laterite, grass, asphalt, interlock),
  blended by the terrain shader.
- **Buildings:** anchored at the footprint's back corner (tile 0,0 ground point).
- **Props and characters:** anchored at the ground contact point (feet / base).
- **Characters:** about 44 px tall at 1x, big heads (about one third of body height).
- **Lighting:** paint in daylight. Night and NEPA lighting is an overlay in the engine, so never
  paint shadows darker than value 20%.
- **Large binaries:** go through Git LFS once real art arrives.
