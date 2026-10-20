# Design notes (Milestone 1)

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

## Not in this build (on purpose)

Second and third abilities, ultimate, passive, upgrade choice, items, minions, structures, networking. See
`docs/ROADMAP.md`.
