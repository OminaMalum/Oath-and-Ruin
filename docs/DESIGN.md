# Design notes (Milestone 1, Gate 2 and Gate 3)

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

Mode: **3v3 Bot Match** from the menu (or `-- --mode=match`, `--spectate` for six bots). Since Gate 3 each team
fields one of each champion (mirrored picks); the player's pick takes slot 0. Team colours are teal (Oath) and amber (Ruin); the wild camp is amethyst.

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

## Gate 3: three champions, levels and one upgrade choice

Pick a champion on the menu (or `--champion=ruinscribe|oathwarden|ashrunner`). Each has a basic attack and one
ability for now; kits grow gradually.

| | Ruinscribe | Oathwarden | Ashrunner |
|---|---|---|---|
| Role | Ranged spellcaster | Frontline fighter | Mobile skirmisher |
| Distance | 18 m bolts, 14 m glyph | 3.2 m | 2.6 m |
| Commitment | Low: pokes from range | High: has to stand in the fight | Medium: in and out |
| Mobility | 6.2 m/s, slowed while casting | 5.8 m/s | 6.8 m/s plus an 8 m leap |
| Health | 560 | 820 | 500 |

**Oathwarden**
| | Cleave (basic, LMB) | Warding Stand (Q / RMB) |
|---|---|---|
| Purpose | Hit everything in front | Let the team commit to a fight |
| Effect | 55 damage in a 120 degree, 3.2 m arc | 4 m ward for 3.5 s: allied champions inside take 35% less damage |
| Timing | 0.25 s windup, 1.0 s interval | 0.35 s plant (rooted), 12 s cooldown |
| Tell | The arc shows on the ground during the windup | Solid ring, faint dome, an inner disc that shrinks with time left |
| Counterplay | Stay out of 3 m, step out during the windup | Back off and wait it out, or fight outside the circle |
| Movement / CC | 50% speed while swinging | Champions only (not minions or structures); strongest ward wins, they do not stack |

**Ashrunner**
| | Twin Cut (basic, LMB) | Vault (Q / RMB) |
|---|---|---|
| Purpose | Fast close damage | Gap close or escape |
| Effect | 34 damage in a 90 degree, 2.6 m arc | Leap 8 m the way you move (forward if standing); 40 damage to each enemy passed through, once |
| Timing | 0.12 s windup, 0.6 s interval | 0.08 s windup, 0.22 s leap, 6 s cooldown |
| Tell | Arc on the ground | A lane on the ground shows the leap during the windup |
| Counterplay | Keep distance, it has the shortest reach | Punish the cooldown; walls stop it |
| Movement / CC | 80% speed while cutting | Slows do not shorten the leap; walls do |

**Team interaction**: the Oathwarden's ward is where the Ruinscribe commits. Bots playing a ranged champion step
into a friendly ward during a champion fight and hold a little longer before retreating there.

### Levels (minimal progression)

Champions level 1 to 5. Each level adds 7% health and 6% damage. Experience: 30 per enemy minion death (split among
nearby champions), 150 to the killer of a champion and 50 to each nearby ally, 120 to the whole team per structure,
100 for the Shrinebearer, plus 1 per second. Levels need 300, 700, 1200 and 1800 experience; level 3 comes at
about 3.5 minutes.

### The upgrade choice (one test)

At level 3 the ability offers two upgrades. Press **1** or **2** (bots pick through the same command).

| Ability | Option 1 | Option 2 |
|---|---|---|
| Binding Glyph | Wide Glyph: 3.4 m circle, 75 damage | Deep Glyph: 55% slow for 2 s |
| Warding Stand | Long Stand: lasts 5 s | Bulwark: 3.2 m, blocks 50% |
| Vault | Long Vault: 10.5 m | Quick Vault: 4 s cooldown, 30 damage |

In the soak the same champion on each team takes opposite options and the next seed swaps them, so every pick is
an A/B test.

### Measured (headless soak, 12 seeds)

All 12 ended by a core falling, 8.4 to 13.0 min (median about 11.4). The objective was claimed in 10 of 12. Oath
won 8 of 12: possibly still a small side bias (an earlier fixed unit order gave Oath 6 of 8 and was fixed by
alternating who acts first each tick), but 12 matches cannot tell. Upgrades: option 1 won 7 of 12 for each
champion, option 2 won 5 of 12. That is no real difference in 12 matches. Role spread across the 12 matches:
Ashrunner 113 kills, Ruinscribe 44, Oathwarden 28. Ruinscribe dealt the most champion damage and nearly all the
structure damage. Deaths were 62 to 86 per champion. Zero script errors.

## Not in this build (on purpose)

Second and third abilities, ultimates, passives, items, more champions. See `docs/ROADMAP.md`.
