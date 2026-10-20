# Design notes (Milestone 1 and Gate 2)

## Combat rules in this build

- Fixed 60 Hz simulation tick. `CombatAuthority` steps units, projectiles and areas in a fixed order. This is
  consistent on one machine; it is not assumed to be deterministic across machines.
- Every action is a `UnitCommand` (move, aim yaw, aim point, buttons). Humans, bots and tests produce the same
  commands, so bots cannot do anything a player cannot.
- Aim: projectiles fly flat at chest height toward the point under the reticle. Ground abilities land at that
  point, clamped to range. Points behind the shoulder fall back to straight ahead.
- Casting: windup (`cast_time`, the readable tell) then release then `recovery`. Cooldown starts when the cast
  commits, so a held basic attack fires once per `cooldown`. Casters move at `move_mult_while_casting`.
- Input buffer: a press during another action is kept for 0.25 s. An ability press on a long cooldown is dropped
  so it does not block the basic attack.
- Teams: damage only applies to enemies. Projectiles pass through allies and stop on the first enemy or a wall.
- Death: no collision, no commands, respawn at the spawn point after `respawn_time` with full health and
  cooldowns reset.
- Crowd control in this build: one slow. Strongest slow wins; durations do not stack.

## Ruinscribe (ranged spellcaster)

Role: ranged damage and zone control. Strength: safe poke and area denial. Weakness: low health (560), no escape
yet, slow while casting.

| | Arcane Bolt (basic, LMB) | Binding Glyph (Q / RMB) |
|---|---|---|
| Purpose | Reliable ranged damage | Zone denial, punishes standing still |
| Damage | 42 | 85 + 35% slow for 1.5 s |
| Range | 18 m | placed up to 14 m away, radius 2.6 m |
| Cast time / recovery | 0.15 s / 0.25 s | 0.30 s / 0.20 s |
| Cooldown | 0.85 s (attack interval) | 7 s |
| Projectile | 32 m/s, radius 0.3 | none (delayed area, 0.75 s) |
| Move while casting | 60% | 40% |
| Tell | staff stone flares; faint lane on the ground | ring at full size the moment it lands; inner fill shows time to burst |
| Counterplay | step sideways out of the lane, break line of sight with walls | walk out before the fill completes (tested) |
| Movement / CC | caster slowed while casting | its slow is the only CC; it cannot stack with itself |

## Training dummy

Stationary. When F1 is on it fires a slow, telegraphed shot (0.7 s windup with an amber ground lane, 16 m/s, 55
damage, every 2.2 s) at the nearest enemy within 16 m. It exists to practise dodging and to prove death and
respawn on the player.

## Gate 2: the 3v3 bot match

Mode: **3v3 Bot Match** from the menu (or `-- --mode=match`, `--spectate` for six bots). Mirrored picks: all six
champions are Ruinscribes. Team colours are teal (Oath) and amber (Ruin); the wild camp is amethyst.

### Map (Lanebreaker Ruins, graybox)

One straight lane along z, bases at both ends (fountain at z = +-72, core at +-56, tower at +-32). Lane walls
have two gaps per side (z = +-9 and +-39) into small flank corridors. The west flank opens into the camp pocket
at (-28, 0, 0), the only neutral objective.

### Units and structures

| Unit | Health | Attack | Notes |
|---|---|---|---|
| Warden Tower | 2600 | 110, homing, 15 m, every 1.2 s | Range ring on the ground |
| Oathstone (core) | 3000 | none | Cannot be damaged while its tower stands ("protected" notice) |
| Shieldbearer (melee minion) | 260 | 18, 2.2 m | x2 against structures |
| Slinger (caster minion) | 180 | 22, 9 m | x2 against structures |
| Breaker (siege minion) | 900 | 40, 2.6 m | x2.5 against structures, ignores everything but structures |
| Shrinebearer (wild) | 2000 | 120 ground slam, 0.9 s warning | Leashes at 10 m, regenerates 60/s after 8 s untouched |
| Shrinebearer (claimed) | 1800 | 60 ram | x4 against structures, ignores everything but structures, 75 s |

### Match rules

- Waves of 3 Shieldbearers and 2 Slingers every 25 s from 0:03.
- Tower targeting, in order: a champion who hit an allied champion near the tower in the last 2 s, the current
  target while it stays valid, the nearest minion, the nearest champion.
- **Rising tide** (the anti-stall rule): from 5:00 every new minion hits structures 35% harder per minute (up to
  x4), announced once. From 8:00 each wave brings a fourth Shieldbearer.
- **Breach**: once a team's tower falls, the other team's waves each bring a Breaker. Breakers walk past minions
  and champions to the structures, so defenders must turn and kill them.
- Champion respawn: 6 s plus 2 s per minute, at most 20 s. Fountains heal 80/s within 6 m.
- Victory: destroy the enemy core. A 25 minute limit ends a match as a draw (has not happened in the last soak).
- Results screen: winner, time, kills, structures, objective claims. R plays again, M returns to the menu.

### The objective (Shrinebearer)

| Requirement | How |
|---|---|
| Advance warning | Banner 30 s before it wakes; a marker on the HUD |
| Clear capture rule | Kill it, then stand alone in its 4 m circle for 3 s within 20 s. Any enemy in the circle pauses the claim |
| Visible ownership | Capture bar in the team's colour; the claimed beast wears that colour |
| Recognisable reward | The beast walks the lane for 75 s and rams structures for x4 damage |
| Duration / endpoint | 75 s or until killed; the next one wakes 150 s later |
| Counterplay | Contest the circle, or kill the marching beast (1800 health, it does not fight back) |
| Cost of leaving the lane | Two of three champions leave; the lane wave is left to one |
| Not mandatory | It never wins by itself; matches have been won with no claims |

### Bots

States: PUSH (follow their wave), FIGHT, RETREAT (below 25% with an enemy champion near, 15% otherwise; back at
90%), OBJECTIVE (slots 1 and 2 when the beast is up, above 50% health and two allies alive). They see 18 m, react
after 0.3 s, aim with 0.7 m of error and use the same commands, cooldowns and ranges as a player. With more
champions up than the enemy (public: deaths are announced) they walk level with their wave and hit structures.

### Measured (headless soak, 8 seeds, `tools/soak.sh 8`)

All 8 ended by a core falling: 8.5, 10.5, 11.8, 11.8, 13.1, 16.5, 19.3 and 23.0 min (median about 12.5).
Objective claimed in 7 of 8 matches. First champion fight at 15 to 16 s. Champion deaths 2 to 11 per match.
Zero script errors. The longest quiet spell without structure damage is still up to 9 minutes in some seeds.

## Not in this build (on purpose)

Second and third abilities, ultimate, passive, upgrade choice, items, more champions. See `docs/ROADMAP.md`.
