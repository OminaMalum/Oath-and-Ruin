# Oath & Ruin (working title)

Third-person fantasy MOBA for Windows. Original setting and champions. Godot **4.7.2-stable**, typed GDScript
(see `ENGINE_VERSION`). The name is provisional.

## Run it

1. Install Godot 4.7.2-stable (standard build, not .NET): https://github.com/godotengine/godot/releases/tag/4.7.2-stable
2. Open `project.godot` and press Play (F5). Or run a Windows build: `OathAndRuin.exe` (from the PR or release).

Controls: **WASD** move, **mouse** turn and aim (the reticle is the aim), **hold left mouse** Arcane Bolt,
**Q or right mouse** Binding Glyph, **F1** dummies fight back on/off, **F2** hide help, **Esc** free the mouse
(click to recapture).

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
| `scripts/control/` | Command producers: `HumanController` (keyboard and mouse), `SparringBot`, `DemoController`, `ScriptedController` (tests). All go through the same `UnitCommand` path. |
| `scripts/view/` | Camera rig, unit models, projectiles, telegraphs. Read state only. |
| `scripts/ui/` | HUD (drawn in code, large type). |
| `scripts/data/` + `data/` | `ChampionDef` and `AbilityDef` resources; tuning lives in the `.tres` files. |
| `scripts/arena/` | Arena built from primitives. |
| `tests/` | Headless gameplay tests. |
| `tools/` | Test, export and data bootstrap scripts. |

## Tools

```
tools/run_tests.sh          headless gameplay tests (exit code = failures)
tools/export_windows.sh     Windows x86_64 export to build/windows/OathAndRuin.exe
tools/net_test.sh           multi-process network test (server plus four clients)
godot --path . -- --autoplay --bot --shot=out.png --shot-frames=200   self-playing capture
```

## Assets and licenses

`ASSET_MANIFEST.csv` lists every asset with source and license. `licenses/` holds license texts. No generative AI
art in the game.
