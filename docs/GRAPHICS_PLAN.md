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
   minions. Wild magic is amethyst and old gold. The environment stays in stone, earth and autumn tones so team colour always pops.
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
| 2 | Fantasy layer (Anthony 2026-10-22: "make it magical"): glowing rune bands on the lane walls and tower steps, a ward circle in mid lane, floating and growing amethyst crystals, spirit trees, floating islands over the valley, light motes. Minions, Breaker and Shrinebearer rebuilt. Hit sparks, death dust and wisps, structure collapse | in build art2 |
| 3 | Champions: first modelled and rigged champion over the Ruinscribe template, through the asset contract checker | after pass 2 |
| 4 | Spell effects: shaders for bolts, glyphs and the ward (trails, distortion, impact flashes) kept readable | |
| 5 | Mood two: rain-wet night with lanterns (a second lighting preset), and a graphics quality menu | quality menu done in gate5a (Settings: Low, Standard, High, Ultra, `Art.apply_quality`, also `--graphics=N`); High and Ultra need a look on a real PC. Night mood still open |
| 6 | Performance pass on Anthony's PC: frame time, shadow distance, light count, LODs | needs his machine |

## How to check a pass

- `tools/art_shots.gd` takes fixed camera shots of the map (tower, lane, flank, base, camp, overview) after a
  short warp, with the HUD hidden. Run under xvfb in the cloud (Compatibility renderer, so SSAO and some light
  quality only show on a real PC).
- The cloud has no GPU, so frame rate is only measured on Anthony's PC.
- Tests and the soak must stay green: art is view only and never changes the sim.

## Champion figures (2026-11-10, Thornwright first)

The first champions were lathes and tubes: a hood with two lights for a face, mittens, a stick for a bow. The
Thornwright is the pilot for a better figure, still built from code and still with no generated or bought art.

- `tools/blender/figure_kit.py` fits the CC0 Blender Studio body to the rig and keeps its head, arms and hands.
  It reshapes the base mesh's cartoon head toward an adult's (smaller eyes, longer jaw, lower crown, smaller
  overall), points the ears, curls the fingers round a grip, and adds eyeballs, lids, a lash line, brows, a hair
  cap and locks. Clothes are the body's own faces pushed out (`Figure.add`), so they fit; straps and belts are
  wrapped on by ray casts (`Figure.strap`).
- `figure_kit.bake()` paints every vertex with what a texture artist would bake: ambient occlusion from the
  whole figure, wear on raised edges, grime in creases and near the ground, and painted detail (lips, a blush,
  the iris, streaks in hair, a dark hem). It rides in the glTF colour attribute `Col`.
- `ChampionModel.dress()` multiplies those colours into the same tiling CC0 materials as before, only for a
  model that carries them. Nothing changes for the other champions until each is rebuilt.
- The rig, the clip names and the timings are unchanged, so the sim and the tests do not see the difference.
  New bones: `plait` (the plait that falls out of her hood onto her chest, swung by `ClothSim` with its own thin setting) and the bow now lies along the fist at rest. She wears her hood up (`build_hood`): Anthony preferred that to the hood down.
- Look at a model with `tools/model_shots.gd`. The first shots in the set are from the real game camera
  (`play_idle`, `play_run`, `play_attack`, `play_ability_1`) and from an enemy 9 m away (`enemy_idle`, `enemy_attack`).
  **Judge those first.** She is about 175 pixels tall with her back to the player; a change that only shows in a
  close up has not improved the game.

### After the critique (2026-11-11)

An independent review (`/mnt/project-files/oath-and-ruin/critique-thornwright/CRITIQUE.md`) found that the pilot
polished the view the player never has. What changed because of it:

- Arm poses are solved, not typed: `figure_kit.Reach` is a two bone arm solver in the kit's own rotation
  convention. Give it a wrist target, an elbow direction and a hand orientation.
- The shot (`aim` and `shot` in `build_thornwright.py`): side on stance, bow arm straight down the aim line, draw
  hand under the chin, a release and a follow through. New bones `string` (child of `bow`, the string mesh is
  weighted so moving it makes a V) and `arrow` (child of `string`). The arrow is scaled to 0.001 in every clip
  that does not nock it (`hide_arrow`), because an unkeyed pose scale does not reach the export.
- Back view: hood with a band in her accent colour and a tail, half cloak off the bow shoulder so the quiver,
  belt and legs show, fletching in the accent colour (material `Accent`, dyed in `ChampionModel.dress`), bow
  carried low and out to the side, thicker bow, lighter legs, one green for hood and cowl.

Second round (gate5e):

- `figure_kit.drape` weights a skirt to the thighs below the hip joint, each side to its own leg, so the cloth rides
  over a lifted leg instead of letting it through. A share stays on `skirt_f` and `skirt_b` for sway.
- `Figure.add(..., relax=N)` smooths a shell made from body faces so stiff clothes span the body's small hollows
  instead of showing every muscle, kept between `clear` and its starting lift plus `slack`. `figure_kit.shell(kit)`
  gives a ray cast onto the garment, so seams, laces and trims sit on it. The jerkin uses both.
- Idle, run and the bramble toss are solved with `Reach` like the shot: weight on one leg at rest; a leaning run with
  the free arm pumping and the bow held low.
- Keyed cloth signs: a hanging bone swings FORWARD with a positive X turn. The older builders key `cape` and
  `skirt_b` positive in the run, which pulls them into the body (the cloth sim hides it in play, stills show it).
  Thornwright's are negative now. Worth fixing on the others when each is rebuilt.

Still open from that review: no texture set of her own (stitching, trim, wear are still tiling textures times
vertex colour); sleeves and skirt have few folds; the face (waiting on a direction from Anthony: shadowed hoods or
real faces); hair; mesh cost (72k triangles, 50 surfaces).

Oathwarden and Ruinscribe wait until Thornwright is right.
