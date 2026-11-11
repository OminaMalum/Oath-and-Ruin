# Oath & Ruin (working title)

Third-person fantasy MOBA for Windows. Original setting and champions. Godot **4.7.2-stable**, typed GDScript
(see `ENGINE_VERSION`). The name is provisional.

## Run it

1. Install Godot 4.7.2-stable (standard build, not .NET): https://github.com/godotengine/godot/releases/tag/4.7.2-stable
2. Open `project.godot` and press Play (F5). Or run a Windows build: `OathAndRuin.exe` (from the PR or release).

The menu shows every champion with a turning model, its story and its kit (what each ability does and how to
beat it), then **Play 3v3 Bot Match**, **Three Lane Map**, **Training Court**, **Settings** and **Quit**.
Settings holds volume, mouse sensitivity, fullscreen and graphics quality (Low, Standard, High, Ultra).

Controls: **WASD** move, **mouse** turn and aim (the reticle is the aim), **hold left mouse** basic attack,
**Q** or **right mouse** the first ability (ground spells: hold Q to preview and release to cast), **E** the
second ability, **F** the third, **R** the ultimate (from level 4), **1 / 2** pick an upgrade when offered,
**B** shop at the fountain or while dead, **T** recall home, **Tab** (hold) scoreboard, **Alt** (hold) your items
and what each ability does, **F1** dummies fight back on/off (court), **F2** controls help, **Esc** menu. After a
match: **F5** play again, **M** menu.

In a match the top right holds the minimap (enemy champions show only while your team can see them) with the
kill feed under it; callouts announce first blood, multi kills, a fallen tower and a base under attack.

## Bot match (Gate 2)

```
godot --path . -- --mode=match                        you plus two bots against three bots
godot --path . -- --mode=match --spectate             six bots
tools/soak.sh 8                                       eight headless bot matches, one summary line each
```

Each match prints a `MATCHLOG` JSON line and saves it under `user://telemetry/`. Rules and numbers are in
`docs/DESIGN.md`.

## Network test (Gate 1)

```
godot --headless --path . -- --server                 dedicated server on UDP 24680
godot --path . -- --connect=127.0.0.1                 a client (repeat for a second player)
godot --path . -- --connect=HOST:24680 --lag=50 --jitter=10 --loss=0.02   with simulated conditions
tools/net_test.sh                                     automated multi-process test
godot --path . -- --connect=127.0.0.1 --no-predict    a client without own-champion prediction (comparison)
```

See `docs/NETWORK.md` for what is proven and what is not.

## Milestone 1 contents

One champion (Ruinscribe, ranged spellcaster) with a basic attack and one ability, three training dummies that
can fight back, in a small ruined courtyard built from primitives. See `docs/DESIGN.md` for the kit.

## Layout

| Path | What |
|---|---|
| `scripts/sim/` | Gameplay state and rules. `CombatAuthority` steps every unit on the 60 Hz physics tick and is the only thing that changes health. `Unit` is per-combatant state. `UnitCommand` is one tick of intent. |
| `scripts/control/` | Command producers: `HumanController` (keyboard and mouse), `ChampionBot`, `MinionController`, `TowerController`, `NeutralController`, `SparringBot`, `ScriptedController` (tests). All go through the same `UnitCommand` path. |
| `scripts/view/` | Camera rig, unit models, projectiles, telegraphs. Read state only. |
| `scripts/ui/` | HUD (drawn in code, large type). |
| `scripts/data/` + `data/` | `ChampionDef` and `AbilityDef` resources; tuning lives in the `.tres` files. |
| `scripts/arena/` | Proving Court and the lane map, built from primitives. |
| `scripts/match/` | `MatchController` (waves, structures, objective, respawns, victory, telemetry) and `MatchInfo` (what bots may know). |
| `scripts/net/` | `NetSession` (server and client), `SnapshotCodec` (compact snapshots). |
| `scripts/assets/` | `AssetContract`: what a champion model must match (see `docs/ASSET_CONTRACT.md`). |
| `assets/` | `specs/` (numbers per champion), `templates/` (Blender template rigs), `champions/` (real models, later). |
| `tests/` | Headless gameplay tests. |
| `tools/` | Test, export and data bootstrap scripts. |

## Tools

```
tools/run_tests.sh          headless gameplay tests (exit code = failures)
tools/export_windows.sh     Windows x86_64 export to build/windows/OathAndRuin.exe
tools/net_test.sh           multi-process network test (server plus four clients)
godot --headless --path . -s tools/check_assets.gd    check champion models in assets/champions/ (docs/ASSET_CONTRACT.md)
tools/blender/make_fixtures.sh [python]               rebuild template rigs and test fixtures (needs pip install bpy)
godot --path . -- --autoplay --bot --shot=out.png --shot-frames=200   self-playing capture
godot --fixed-fps 60 --path . -- --mode=match --spectate --warp=190 --shot=out.png --shot-frames=20   capture mid match
godot --path . -- --mode=match --graphics=3 --bench    force a graphics level (0 Low to 3 Ultra) and write bench.txt
python3 tools/mksounds.py; python3 tools/mksounds2.py  rebuild every sound from its formula (needs numpy)
```

## Assets and licenses

`ASSET_MANIFEST.csv` lists every asset with source and license. `licenses/` holds license texts. No generative AI
art in the game.
