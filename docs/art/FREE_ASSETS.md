# Free 3D assets (D-024)

Downloaded with `tools/art/free_assets.mjs` from Poly Pizza. CC0 needs no credit. CC-BY 3.0 needs
the credit below, which the game's credits screen repeats.

| File | Model | Author | Licence | Source | Used for |
|---|---|---|---|---|---|
| `horse` | Horse | Quaternius | CC0 | https://poly.pizza/m/qvTrSG9pZF | Kano Durbar horseback chase (Act III) |
| `helicopter` | Helicopter | kazuma | CC0 | https://poly.pizza/m/EQJ2MECUbx | The senator's helicopter, Obinna's escape (Acts IV-V) |
| `pistol` | Pistol | Quaternius | CC0 | https://poly.pizza/m/J3i9KDQ3kt | Dayo's pistol in hand |
| `rock_large` | Rock Large | Quaternius | CC0 | https://poly.pizza/m/li0YBlBEMz | Olumo Rock boulders, creek banks (Acts II-III) |
| `mountain` | Mountain | Quaternius | CC0 | https://poly.pizza/m/7HYR2s9JVi | Olumo Rock outcrop, Abeokuta (Act II) |
| `tent` | Tent | Quaternius | CC0 | https://poly.pizza/m/5Q7qIrfDxA | Festival and refinery camps |
| `gazebo` | Gazebo | Quaternius | CC0 | https://poly.pizza/m/xYZB1TmGMv | Owambe and Iri Ji seating |
| `barrel` | Barrel | Quaternius | CC0 | https://poly.pizza/m/MraIiFnpAY | Kpo-fire refinery drums (Act III) |
| `gas_tank` | Gas Tank | Quaternius | CC0 | https://poly.pizza/m/RoCvKBGkoC | Refinery tanks (Act III) |
| `speedboat` | Boat | Quaternius | CC0 | https://poly.pizza/m/5UEl54KsuC | Creek speedboats, lagoon chases (Acts II-V) |
| `yacht` | Yacht | Alex Safayan | CC-BY 3.0 | https://poly.pizza/m/9znU2c-dTSR | Obinna's yacht, the final fight (Act V) |
| `canopy` | Canopy | Poly by Google | CC-BY 3.0 | https://poly.pizza/m/40tUFNg2fu4 | Owambe event canopy (Act II) |
| `ambulance` | Ambulance Car | Zsky | CC-BY 3.0 | https://poly.pizza/m/4JxDoxLnRd | LUTH ambulance run (Act III) |
| `dayo` | Casual Character | Quaternius | CC0 | https://poly.pizza/m/kZ3DmIoGip | Dayo, the protagonist (recoloured: dark brown skin, olive T-shirt, black boots; 24 animations incl. gun idle/shoot) |
| `young_dayo` | Hoodie Character | Quaternius | CC0 | https://poly.pizza/m/gKLBoRsyKe | Young Dayo in the prologue (used exactly as published) |

## Downtown City MegaKit (Quaternius, CC0)
- **Source:** https://quaternius.com/packs/downtowncitymegakit.html, the free Standard version
  from itch.io at $0, downloaded 2026-10-19.
- **Licence:** CC0 1.0, per `License_Standard.txt` in the pack.
- **In the game** (`game/art3d/citykit/`): the three pre-built buildings (Building_Small_1,
  Building_Medium_2_001 and Building_Large_2), the props (AC unit, bollard, manhole cover, drain
  and planter), the crosswalk decal, and the concrete, asphalt and dirt materials with their
  normal and ORM maps.
- **Unchanged:** the files are as published. Textures import at 1024 px for phones.
- **Rendering note:** the kit keeps a wear mask in its vertex colours for its own shader, so we
  render it without vertex colour as albedo.
- The full zip is in the git-ignored `art-src/citykit/`.
