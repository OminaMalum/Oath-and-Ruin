# Graphics plan

Started 2026-10-22, when the match loop was good enough that the next big step is making PactFall look like a
real game. Rules from the start of the project still hold: no generative AI art anywhere in the game, licensed or
original assets only, every external file recorded in `ASSET_MANIFEST.csv`, readability before decoration.

## The look in one line

Late afternoon in an old ruined valley: weathered stone, cobbles, fallen autumn leaves and warm lantern light
(the Baldur's Gate kind of material richness), with team colours, telegraphs and silhouettes kept as clean and
loud as SMITE.

## Readability rules (these win over decoration)

1. The lane floor is flat and calm. No clutter in the fighting space; props live against walls.
2. Floor dressing stays under `Palette.DECAL_LIFT` (8 cm). Never two coplanar floor faces. The floor is one
   surface with one shader, so there is nothing to flicker.
3. Team colours (teal Oath, amber Ruin) only on things that belong to a team: crystals, banners, rings,
   minions. The environment stays in stone, earth and autumn tones so team colour always pops.
4. Light sources are warm and low (lanterns, braziers). Crystals carry the team light.
5. Large type and contrast in UI stay as they are.

## Asset sources

- Poly Haven (CC0, photo scans and hand made models): stone, cobble, earth and leaf textures, the sky, rocks,
  plants, barrels, crates, lanterns, fire pit. Downloaded at 1k, VRAM compressed with mipmaps.
- Our own code built shapes and shaders: ground blend, leaves, grass, fire, trees, towers and cores.
- Later, original models made over `assets/templates` rigs (see `ASSET_CONTRACT.md`) for champions.

Paragon assets are Unreal only and not usable. Anything from a store gets checked for a license that allows a
commercial game and is written into the manifest before it enters the repo.

## Order of work

| Pass | What | Status |
|---|---|---|
| 1 | Ground (one blended surface), masonry walls with caps and plinths, sky and sun, fog, SSAO, trees, grass at wall feet, lanterns, braziers, props in flanks and bases, crystal shrine towers and cores | in this build |
| 2 | Minions and the Shrinebearer: shaped meshes and materials instead of primitives; hit and death effects with particles | next |
| 3 | Champions: first modelled and rigged champion over the Ruinscribe template, through the asset contract checker | after pass 2 |
| 4 | Spell effects: shaders for bolts, glyphs and the ward (trails, distortion, impact flashes) kept readable | |
| 5 | Mood two: rain-wet night with lanterns (a second lighting preset), and a graphics quality menu | |
| 6 | Performance pass on Anthony's PC: frame time, shadow distance, light count, LODs | needs his machine |

## How to check a pass

- `tools/art_shots.gd` takes fixed camera shots of the map (tower, lane, flank, base, camp, overview) after a
  short warp, with the HUD hidden. Run under xvfb in the cloud (Compatibility renderer, so SSAO and some light
  quality only show on a real PC).
- The cloud has no GPU, so frame rate is only measured on Anthony's PC.
- Tests and the soak must stay green: art is view only and never changes the sim.
