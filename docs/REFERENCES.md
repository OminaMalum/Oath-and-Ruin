# References and decisions (2026-10-20)

Sources were checked on 2026-10-20. Official pages carry no publication dates except where noted, so they describe
current marketing and help text, not detailed mechanics. Nothing below is a firsthand gameplay observation.

## Lanebreaker (the screenshots)

- **Observed:** https://lanebreaker-game.vercel.app shows the title "LANEBREAKER, Battle for the Sundered Vale", a
  "Loading..." message, a Unity "Made with" logo and Unity WebGL `TemplateData` files, and a "Created by Ricco"
  credit linking to @riccoasi. The page did not load a playable game for the fetch tool.
- **Claimed by its creator (not verified):** a two-day build with Unity, Blender, generated models and generated audio.
- **Inferred:** it is a Unity WebGL build.
- **Unknown:** whether its 5v5 means humans or bots, its networking, depth and stability.
- **What we take:** automate repetitive asset preparation and integration. We do not take generated art or audio,
  and we do not set our schedule from it.

## Decision table

| Reference | Useful principle | Our adaptation | Cost / risk | Now or later |
|---|---|---|---|---|
| SMITE 2 (smite2.com, (c) 2023-2025) | Third-person action MOBA; the page names auto-build and auto-level to ease the start | Reticle shows in range, out of range and blocked; hold Q to preview the glyph, release to cast; a cast that fails says why; arrows show where damage came from. One recommended build when items exist. | Low; HUD and input only | **Now** (improvement 2) |
| Predecessor (how-to-play page, (c) 2025) | Lanes, towers, cores, minions as gold/XP, bosses | One lane with a tower and core per team, minions that give a reason to push; landmarks you can see from player height (tower beacons, core crystals) | Medium; new map | **Now** (improvement 1) |
| Battlerite (arena page, (c) 2019) | WASD, cursor aim, skillshots and dodging in 2v2/3v3 | Keep the Proving Court as an internal duel and dodge test; every ability lists purpose, tell, range, counterplay, cost, team value | Low; exists | Kept, extended per champion in Gate 3 |
| Heroes of the Storm (Battleground Basics, about 2017, date inferred from linked articles) | Objectives announced and shown on the map; mercenary camps push lanes; sometimes conceding is right | One neutral camp with a warning, capture rule, visible owner, a lane-pushing reward and a time limit | Medium | **Next batch** of Gate 2 |
| League of Legends (how-to-play page) | Clear roles; minions, turrets and the Nexus give reasons to act; turrets hit minions and champions | Tower targeting rules everyone can learn: minions first, but a champion who hits an allied champion near the tower becomes the target. Core cannot be hit while its tower stands. | Low | **Now** (inside improvement 1) |
| League / Predecessor roles | Champions differ in distance, commitment, mobility | Frontline, spellcaster and skirmisher differ on those four axes, plus one team interaction (protective area that lets the caster commit) | High; three kits | Gate 3 |
| Lanebreaker workflow claim | Automate asset prep | Blender is not installed in this container; scripted Blender to GLB pipeline with wrapper scenes | Medium; tooling | After the match loop works |

## The three improvements for this build, in order

1. **A complete match loop** (Gate 2 core): lane map, tower and core per team, minion waves, tower targeting,
   champion respawn, victory, results and restart, with match stats saved for later analysis. Why: nothing else
   can be judged without a match to judge it in.
2. **Targeting and danger feedback**: where the attack will go, whether it is in range or blocked, why a cast
   failed, and which way incoming damage came from. Why: the third-person camera hides information that a top-down
   MOBA shows for free, and it is cheap to fix now.
3. **Lane bots that obey the rules**: follow the wave, fight what they can see, use the ability, retreat when hurt,
   return after respawning. Why: a 3v3 against bots needs five bots, and they are also the test harness for match
   length and stalls.
