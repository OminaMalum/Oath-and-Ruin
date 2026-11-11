# Asset contract (champion models)

The game's rules decide hit size, height, where shots start and how long every windup lasts. Models adapt to
those numbers. A model that passes this contract can replace a primitive placeholder without any gameplay
change, and a model that fails says exactly what to fix.

## The numbers

`assets/specs/<champion>.json` holds them per champion, written from the `data/` files:

```
godot --headless --path . -s tools/check_assets.gd -- --spec=$PWD/assets/specs
```

| Rule | Value | Why |
|---|---|---|
| Units and axes | metres, scale 1, +Y up. Faces **-Z in Godot**, which is **+Y in Blender** | `Unit.forward()` is -Z; Blender +Y becomes Godot -Z through the glTF +Y up export |
| Origin | on the ground between the feet (lowest point within 6 cm of 0) | the sim places units by their feet |
| Height | the champion's `height` +-15% | the hit capsule is that tall |
| Width | warning past 2.5x the hit radius | a model much wider than its hit radius reads as a bigger target than it is |
| `Muzzle` socket | within 0.35 m of where the sim fires (`AssetContract.sim_muzzle`) | shots must look like they leave the hand or staff |
| `Overhead` socket | present | health bar and name anchor |
| Clips | `idle-loop`, `run-loop`, `death`, `attack`, `ability_1`, `ability_2`, `ability_3` (one NLA track each) | the view plays clips by these names |
| `release` pose marker | in every attack and ability clip, on the frame the effect happens | the windup is the readable tell; see below |
| Windup speed | clip release / sim cast time between 0.8x and 1.25x | the view plays the clip at that speed so the release lands on the sim's release |
| Run stride | move speed / clip ground speed between 0.85x and 1.15x | otherwise the feet slide |

Timing at 30 fps is coarse: a 0.15 s windup is 4.5 frames, so the marker lands on 0.133 s (0.89x). That is
inside the limit, but very fast attacks are easier to hit at 60 fps.

## The workflow

1. Start from `assets/templates/<champion>_template.blend`. It is a blockout built from the spec (capsule
   body, feet, armature, sockets, every clip with its marker on the right frame and a run cycle timed to the
   run speed). Model and animate over it, keep the names.
2. Export with the fixed settings:
   `blender -b my.blend --python tools/blender/export_champion.py -- assets/champions/ruinscribe.glb`
   This also writes `ruinscribe.timing.json` with each clip's release time, because glTF has no timeline
   markers.
3. Check it: `godot --headless --path . -s tools/check_assets.gd` (all of `assets/champions/`, exit code is
   the number of failing files). Name files after the champion id; `ruinscribe_v2.glb` also works.
4. Add the file to `ASSET_MANIFEST.csv` with its creator and license.

The checker loads files with Godot's own glTF importer (`GLTFDocument`), so it runs headless in the cloud and
in CI without the editor. The editor import can differ in settings you change in the import dock (root scale,
root type); keep those at their defaults.

## Tests

`tests/run_tests.gd` (`test_asset_contract`) checks five Blender 5.2 exports of the Ruinscribe template in
`tests/fixtures/assets/`: one valid, and one each with the wrong scale, facing backwards, a run stride 40% short,
and windups 60% late. `tools/blender/make_fixtures.sh` rebuilds them and the templates (needs `pip install bpy`).

## Licenses

The scripts in `tools/blender/` use Blender's Python API and are marked GPL-2.0-or-later. They are build tools
and are not shipped in the game. The templates and fixtures are geometry generated from our own numbers.
