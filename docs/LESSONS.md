# Lessons from earlier projects

Reviewed 2026-10-20 (Spires of Ruin in Unreal 5.8, Runners in three.js, the KOTOR remaster kit).

1. Spires shipped cloud-written code that could not be compiled in the cloud. Here every change runs in headless
   Godot and the test suite before it is committed.
2. Spires' packaged build broke on an editor-only API. Here the exported build is run too, not only the editor.
3. Spires left replication for later. Here gameplay state lives in one authority and every action is a command,
   so a server can own it in Gate 1.
4. Two sessions edited the same files and needed patch documents. Keep one owner per area.
5. The cloud box has no GPU and asset sites were blocked for Runners. No FPS claims from cloud runs; primitives
   until assets are cleared.
6. Spires spent many rounds on visual polish before the loop was fun, and Runners did branding before gameplay.
   Gameplay first.
7. Never drive the engine on Anthony's PC while he has the editor open.

## Found in this project

8. Gate 2: a one-off data bootstrap script saved the unit files with private copies of their attacks, so later
   edits to `data/abilities/*.tres` (the minions' x2 structure damage) silently did nothing. Matches stalled and
   tuning chased the wrong cause. Now a test fails if any unit file carries an ability that is not an ability
   file, and the bootstrap scripts are gone.
9. Gate 3: `Engine.time_scale` does not add physics steps, it stretches each one (x32 made every tick 0.53 s), so
   a sped-up capture played a different match. Captures now skip drawing instead and match the plain run.
10. Gate 3: stepping units in a fixed order gave the first team the first hit in every even trade (Oath won 6 of
    8 mirrored matches). The authority now alternates the order each tick.
11. Gate 3: a script holding a typed array of its own class (`Array[AbilityDef]` inside AbilityDef) leaked at exit
    and the network test caught the error line. Such arrays are typed `Array[Resource]`.
