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
