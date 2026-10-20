# Oath & Ruin (working title)

Third-person fantasy MOBA for Windows. Original setting and champions. Godot **4.7.2-stable**, typed GDScript
(see `ENGINE_VERSION`). The name is provisional.

## Run it

1. Install Godot 4.7.2-stable (standard build, not .NET): https://github.com/godotengine/godot/releases/tag/4.7.2-stable
2. Open `project.godot` and press Play (F5). Or run a Windows build: `OathAndRuin.exe` (from the PR or release).

The menu offers a champion pick (**Ruinscribe**, **Oathwarden**, **Ashrunner**), then **3v3 Bot Match**,
**Training Court** and **Quit**.

Controls: **WASD** move, **mouse** turn and aim (the reticle is the aim), **hold left mouse** basic attack,
**Q** or **right mouse** the first ability (for Binding Glyph, hold Q to preview and release to cast), **E** the
second ability, **R** the ultimate (from level 4), **1 / 2** pick an upgrade at level 3, **F1** dummies
fight back on/off (court), **F2** hide help, **Esc** free the mouse (click to recapture). After a match: **F5**
play again, **M** menu.

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
| `tests/` | Headless gameplay tests. |
| `tools/` | Test, export and data bootstrap scripts. |

## Tools

```
tools/run_tests.sh          headless gameplay tests (exit code = failures)
tools/export_windows.sh     Windows x86_64 export to build/windows/OathAndRuin.exe
tools/net_test.sh           multi-process network test (server plus four clients)
godot --path . -- --autoplay --bot --shot=out.png --shot-frames=200   self-playing capture
godot --fixed-fps 60 --path . -- --mode=match --spectate --warp=190 --shot=out.png --shot-frames=20   capture mid match
```

## Assets and licenses

`ASSET_MANIFEST.csv` lists every asset with source and license. `licenses/` holds license texts. No generative AI
art in the game.
