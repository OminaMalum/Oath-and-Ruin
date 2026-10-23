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

Spacing (review batch 2, 2026-10-21): units do not collide with each other physically, so the bot steers off any
unit it overlaps (allied champions keep about 2 m). Ranged bots back away from an enemy champion inside 6 m unless
that steps into tower range. The lane formation and the fighting sidestep are mirror images per team, because the
map is a mirror across the lane. Match stats carry `spacing_pair_s`, `spacing_overlap_s` and
`spacing_ranged_close_s` (seconds, sampled once a second). Over 24 seeds per match minute: allied pairs on one
spot 1.3 s (was 8.9), champions overlapping a unit 7.7 s (was 25.9), ranged within 4 m of an enemy champion
3.7 s (was 7.9). Oath 12, Ruin 12, every match ended, 6.2 to 13.0 min. `OATH_NOSEP=1`, `OATH_NOKITE=1` and
`OATH_STRAFE0/1=-1|1` switch the pieces off or force a side, for diagnosis only. `OATH_CAMLOG=1` logs the
followed bot's target switches and facing jumps.

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
| Health | 560 | 820 | 470 |

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
| Effect | 30 damage in a 90 degree, 2.6 m arc | Leap 8 m the way you move (forward if standing); 36 damage to each enemy passed through, once |
| Timing | 0.12 s windup, 0.6 s interval | 0.08 s windup, 0.22 s leap, 7 s cooldown |
| Tell | Arc on the ground | A lane on the ground shows the leap during the windup |
| Counterplay | Keep distance, it has the shortest reach | Punish the cooldown; walls stop it |
| Movement / CC | 80% speed while cutting | Slows do not shorten the leap; walls do |

**Second abilities (E)**
| | Ruinscribe: Unmaking Lance | Oathwarden: Shield Slam | Ashrunner: Ember Knife |
|---|---|---|---|
| Purpose | Punish enemies lined up or held by the glyph | Stop a cast, hold a target for the team | Stick to a runner before the Vault, or finish one |
| Effect | 70 damage, 16 m line, passes through every enemy | 30 damage and a 0.8 s stun in a 70 degree, 2.6 m arc; interrupts casts and dashes | 30 damage and a 40% slow for 1.2 s on the first enemy hit, 10 m |
| Timing | 0.45 s windup, 0.25 s recovery, 9 s cooldown | 0.4 s windup, 0.3 s recovery, 10 s cooldown | 0.18 s windup, 5 s cooldown |
| Tell | A long thin lane on the ground | A narrow arc on the ground | A short lane |
| Counterplay | Step off the line; it is narrow | Step out of the arc in the windup; stay beyond 2.6 m | Sidestep the throw |
| Movement / CC | 30% speed in the windup; no CC | 20% speed; the only stun; longest stun wins, never on structures | 80% speed; slow, strongest wins |

Pressing two abilities at once: the ready one wins over one on cooldown. A stunned unit keeps its aim, cannot
move or buffer input, and its cast or dash is cut.

**Team interaction**: the Oathwarden's ward is where the Ruinscribe commits. Bots playing a ranged champion step
into a friendly ward during a champion fight and hold a little longer before retreating there.

**Ultimates (R, from level 4)**
| | Ruinscribe: Unmaking Word | Oathwarden: Unbroken Oath | Ashrunner: Ashfall |
|---|---|---|---|
| Purpose | Punish a group or a hurt champion from range | Hold a fight the team is losing | Open or close a fight on two targets at once |
| Effect | 4.5 m circle up to 14 m away: 170 damage and a 50% slow for 2 s | 4 m ward for 5 s: allied champions inside take 45% less and heal 30 a second | 11 m leap: 110 damage and a 0.6 s stun on every enemy crossed |
| Timing | 0.3 s windup, 1.1 s delay, 60 s cooldown | 0.25 s windup, 70 s cooldown | 0.12 s windup, 0.28 s leap, 60 s cooldown |
| Tell | A big circle drawn for over a second | A big ring and dome | A long lane along the move direction |
| Counterplay | Walk out of the circle | Leave the ring; it does not move | Step off the line |
| Movement / CC | 30% speed in the windup; slow | 50% speed; no CC | Walls stop it; the only stun in the kit |

Ultimates sit in slot 3 (`is_ultimate` on the AbilityDef) and unlock at level 4 (`Unit.ULT_LEVEL`); a press before
that is refused with a reason on the HUD. Bots save them for a hurt champion, two enemy champions together, or
(the Oath) a hurt team.

**Passives** (resolved in the CombatAuthority, data on the ChampionDef)
| Ruinscribe: Inscribed | Oathwarden: Resolve | Ashrunner: Ember |
|---|---|---|
| Every third Arcane Bolt on the same target hits for 50% more (count per target, resets on respawn; abilities do not count) | Below half health takes 15% less damage | A champion kill resets Vault and heals 12% of max health |

### Levels (minimal progression)

Champions level 1 to 5. Each level adds 7% health and 6% damage. Experience: 30 per enemy minion death (split among
nearby champions) plus 20 to the champion that lands the last hit, 150 to the killer of a champion and 50 to each nearby ally, 120 to the whole team per structure,
100 for the Shrinebearer, plus 1.5 per second. Levels need 220, 500, 850 and 1300 experience (lowered 2026-10-20
after Anthony's first play felt leveling slow: before, level 3 came at about 3.7 minutes for bots).

### The upgrade choice (one test)

At level 3 the ability offers two upgrades. Press **1** or **2** (bots pick through the same command).

| Ability | Option 1 | Option 2 |
|---|---|---|
| Binding Glyph | Wide Glyph: 3.4 m circle, 75 damage | Deep Glyph: 55% slow for 2 s |
| Warding Stand | Long Stand: lasts 5 s | Bulwark: 3.2 m, blocks 50% |
| Vault | Long Vault: 10.5 m | Quick Vault: 5 s cooldown, 28 damage |

In the soak the same champion on each team takes opposite options and the next seed swaps them, so every pick is
an A/B test.

### Gold and the shop (added 2026-10-22)

Anthony asked for last hits to pay more gold. Every number lives in `data/economy.tres` and `data/items/*.tres`.

Income: 300 to start, 2 a second for everyone (dead or alive), 6 per enemy minion split among nearby champions plus
**18 to the champion that lands the last hit** (3 times what standing near pays), Breakers 20 split plus 40 for the
last hit, 200 for a champion kill and 75 to each nearby ally, 150 to every champion of the team per structure, and
100 each for the Shrinebearer.

Shop: press **B** at your own fountain, or while dead, then **1 to 4**. Four slots, each item once:

| # | Item | Cost | Does |
|---|---|---|---|
| 1 | Oathbound Plate | 700 | +150 health |
| 2 | Ember Edge | 800 | +12% damage |
| 3 | Ash Hourglass | 750 | Q, E and R cooldowns 15% shorter (basic attacks unchanged) |
| 4 | Wayfarer Greaves | 600 | +8% walking speed (dashes unchanged) |

Buying is a field on the UnitCommand (`buy_item`), so players, bots, tests and network clients all go through the
same check in `Unit.buy_problem()`. Bots buy their champion's `item_build` order (ChampionDef) when they stand in
the fountain with the gold, and never walk home just to shop. Gold and items travel in the snapshot progress block
(protocol version 2), so a network client's prediction uses the same speed bonus.

Measured (24 seeds, 18 to 41, against the same seeds without gold): sides 12 to 12 both times, median match 8.5 min
(was 8.9), range 5.5 to 14.4 min, first bot purchase at 1.1 to 2.6 min, 2.9 items per champion by the end, about
290 gold a minute.

### Recall and scoreboard (added 2026-10-22)

**T** starts a recall: stand still for 4 s (`recall_time` in `data/economy.tres`) and you are back at your
fountain. Moving, pressing any ability, taking a hit or a stun cancels it, with a short reason on screen. It is a
button on the UnitCommand like any other, so bots recall the same way: when retreating hurt, or when the next item
is affordable and health is under 60%, but only 20 m or more from home, with no enemy champion within 14 m and no
hit in the last 2 s. Bots also shop while dead, as a player can. The recall timer travels in snapshots (protocol
version 3).

**Tab** (hold) shows the scoreboard: each champion's level, kills, deaths, items, and gold for your own team.

Measured (72 seeds, 18 to 89): about 6 recalls per bot per match, 3.2 items per champion, median match 9.3 to
10.1 min per batch of 24 (8.5 before recall), Oath 42 / Ruin 30. That lean is within noise for 72 matches
(earlier 60 seeds leaned the other way, 27 / 33) but is worth watching.

### Batch B: three more champions (added 2026-10-22)

Six champions now. Each match draws three of them and both teams field the same three (a mirror, so a lineup
can never favour a side). The human pick is always in; the rest come from the bot seed. `--lineup=a,b,c` fixes it.

| | Lanternkeeper | Thornwright | Gravebinder |
|---|---|---|---|
| Role | Support (cleric) | Marksman (ranger) | Controller (warlock) |
| Health, speed | 600, 6.1 | 520, 6.2 | 590, 6.0 |
| Basic | Censer Spark, 11 m, 36 | Longbow, 22 m, 40 | Grave Bolt, 15 m, 40 |
| Q | Lantern Light: 3.6 m ward for 4 s, heals allies 30/s | Charged Shot: 0.85 s draw, piercing, 115 | Binding Chains: 70 and a 1.2 s root |
| E | Raven's Mark: 18 m shot, 50, target takes 25% more for 4 s | Bramble: 40, leaves a 2.8 m thorn field for 4 s that slows enemies 35% | Grasping Earth: 3.2 m, 60, pulls 2.5 m to the centre |
| R | Dawnlight: 5 m, heals allies 200, 60 to enemies | Thornstorm: 4.2 m, 210, slow | Grave Pact: 4.5 m, 150, 1.5 s root |
| Passive | Kindled: allies within 7 m regain 4 health a second | Steady Aim: basic attacks beyond 12 m deal 15% more | Soul Tithe: 20% more to stunned, rooted or slowed targets |

New rules, all in the one combat authority and carried in snapshots (protocol version 4):
- **Root**: cannot move or dash (a dash pressed while rooted is spent), can still attack and cast.
- **Mark**: the target takes extra damage from every source until it runs out.
- **Pull**: a ground area moves enemies toward its centre over 0.25 s, on the dash path, so walls still stop them.
- **Ally heal**: a ground area can heal allies as well as hurt enemies.
- **Leaves**: a ground area can leave a ward behind (the bramble field).

Bots aim heals at the most hurt ally in range under 45% health, and fire roots and marks at champions in range.
The HUD tags rooted and marked units over their heads and tells you in plain words when it is you.

Measured (24 seeds, 18 to 41, random mirror lineups): all 24 ended by a core falling, median 10.2 min, range 5.8
to 14.7. First pass had the Thornwright taking 61% of its team's kills, so the longbow went 44 to 40, Steady Aim
25% to 15%, Charged Shot 130 to 115 (upgrades 150 and 100). After: team kill share Ashrunner 49%, Ruinscribe 47%,
Thornwright 42%, Gravebinder 34%, Lanternkeeper 19%, Oathwarden 11% (the two supports are meant to sit low). Ruin
won 15 of 24, the same count both passes; with mirror lineups that is side or seed noise, still worth watching.
Zero script errors.

### Batch C: Barrowking, Veilsinger, Stormscald (added 2026-10-22)

Nine champions now; each match still draws three, the same three on both teams.

| | Barrowking | Veilsinger | Stormscald |
|---|---|---|---|
| Role | Frontline (barbarian) | Support (bard) | Spellcaster (evoker) |
| Health, speed | 860, 5.85 | 540, 6.4 | 530, 6.1 |
| Basic | Barrow Axe, 3 m arc, 46 | Lute Note, 14 m, 38 | Spark Bolt, 17 m, 42 |
| Q | Grave Roar: enemies within 4.5 m take 30 and are taunted 1.25 s | War Song: 5 m circle for 5 s, allies attack 35% faster | Called Lightning: 2.2 m circle, strikes after 1.2 s for 140 |
| E | Barrow Charge: 7 m dash, 55 and a 30% slow | Lure: slow note, 30 and a 1 s charm | Storm Wall: 7 m wall for 3 s that stops enemy shots |
| R | King's Wrath: 4.5 m all round after 0.55 s, 190 and a 0.8 s stun | Rally Chorus: 6.5 m circle for 5 s, allies attack 40% and move 25% faster, take 15% less | Tempest: 4 m storm strikes three times 0.6 s apart, 90 and a slow each |
| Passive | Barrow Blood: below half health regains 14 a second | Encore: allies within 8 m move 8% faster | Eye of the Storm: ground strikes deal 20% more near their centre |

New rules, in the one combat authority and carried in snapshots (protocol version 5):
- **Taunt**: the unit's own command is replaced: it faces the caster, walks into basic attack reach and holds the
  basic attack. **Charm**: it walks straight away from the caster and cannot act. Both end at once if the caster
  dies, interrupt the current cast, and hit champions and minions only (never structures or the neutral camp).
  The client predicts the same walk from the caster position sent in the snapshot.
- **Haste** (basic attacks come sooner; abilities are not sped up) and **quick** (move speed), from wards and the
  Encore aura.
- **Wall**: a new delivery. A line across the aim at a ground point; projectiles from the caster's enemies stop at
  it (homing tower shots do not). Anyone can walk through.
- A ground area can chain into another (`leaves`), which is how the Tempest strikes three times.
- A melee arc of 360 degrees hits all round (King's Wrath).

Bots roar when a champion is in reach, lure champions in range, sing as a champion fight starts within 12 m, and
raise the storm wall when a ranged champion is out-trading them.

Measured (24 seeds, 18 to 41, random mirror lineups from nine): all 24 ended by a core falling, median 11.3 min,
range 6.1 to 16.5. Oath 12, Ruin 12. Team kill share: Gravebinder 46%, Ruinscribe 41%, Thornwright 40%,
Barrowking 38%, Ashrunner 35%, Stormscald 32%, Veilsinger 20%, Lanternkeeper 19%, Oathwarden 17% (supports and
the warden are meant to sit low). No tuning needed this pass. Zero script errors.

### Measured (headless soak, 48 seeds, after ultimates and passives)

Two runs of 24 seeds. All 48 ended by a core falling, 6.5 to 14.3 min (median about 11). The objective was
claimed in 41 of 48. Oath won 21 of 48 and Ruin 27: no side bias (the earlier 8 of 12 was luck). Seeds 25 to 48
(after the Ashrunner trim: 470 health, Twin Cut 30, Vault 36 damage on a 7 s cooldown, Ember Knife 30): Ashrunner
199 kills, Ruinscribe 138, Oathwarden 75. The Ashrunner's share fell from 61% to 48% over the three passes; it still
takes the most kills because it finishes hurt targets, while it deals the least champion damage of the three.
Upgrades (each picked 24 times): Wide Glyph won 14, Deep Glyph 10; Long Stand 14, Bulwark 10; Long Vault 12, Quick
Vault 12. The first 24 seeds showed every team fielding one of the same two upgrade trios, because the pick was a
function of seed plus slot; each slot now reads its own bit of the seed. Zero script errors.

### Measured (headless soak, 12 seeds, after the second abilities)

All 12 ended by a core falling, 7.6 to 12.2 min (median about 9.7). Objective claimed in 10 of 12. Oath won 8 of
12 (the same as before the second abilities; 12 matches cannot separate a bias from luck). Each upgrade option
won exactly 6 of 12. Ashrunner 92 kills, Ruinscribe 45, Oathwarden 34; the Ruinscribe still deals the most champion
damage. Before the second abilities (12 seeds):

All 12 ended by a core falling, 8.4 to 13.0 min (median about 11.4). The objective was claimed in 10 of 12. Oath
won 8 of 12: possibly still a small side bias (an earlier fixed unit order gave Oath 6 of 8 and was fixed by
alternating who acts first each tick), but 12 matches cannot tell. Upgrades: option 1 won 7 of 12 for each
champion, option 2 won 5 of 12. That is no real difference in 12 matches. Role spread across the 12 matches:
Ashrunner 113 kills, Ruinscribe 44, Oathwarden 28. Ruinscribe dealt the most champion damage and nearly all the
structure damage. Deaths were 62 to 86 per champion. Zero script errors.

## The match loop (added 2026-10-23)

- **Menu**: pick one of nine champions on the left; on the right choose the enemy bots (Easy, Normal, Hard), then
  3v3 Bot Match, Training Court, Settings or Quit. Under the buttons: your win and loss record on the chosen
  difficulty.
- **Difficulty** changes only the enemy bots' reaction time and aim error (Easy 0.6 s and 1.5 m, Normal 0.3 s and
  0.7 m, Hard 0.18 s and 0.35 m). Never damage, health or what they can see. Allied bots always play Normal.
- **Every match from the menu draws a new seed**, so the lineup and your teammates change each time (`--seed=N`
  still fixes it for tests and recordings).
- **Lineup intro**: the first 7 seconds show the three champions both teams field, who you play and the bot
  difficulty.
- **Esc** opens the pause menu: Resume, Settings, Surrender (press twice), Main menu, Quit game. Offline the game
  pauses underneath; a network client keeps running.
- **Settings** (menu and pause menu): volume, mouse sensitivity, fullscreen. Saved in `user://settings.cfg` with the
  difficulty and the record.
- **Results**: Victory or Defeat, how and when it ended, then a table per team (level, kills and deaths, damage to
  champions, gold), structures and Shrinebearer claims, and Play again / Main menu buttons (F5 and M still work).

## Presentation and sound (review batches 1 to 3)

Everything here is view only and reads public sim state; timing stays in the sim.
- Champions lean with movement, bob at a step rhythm and fall over on death. The Ruinscribe's staff hangs from a
  shoulder pivot: it swings forward through a cast windup and recoils on release. Bolts are drawn from the focus
  stone and blend onto the sim path over 0.25 s.
- The Oath tower stretch (z 18 to 36) is the first dressed lane section: flagstones, wall caps and buttresses,
  moss and grass at the wall feet, team banners and two braziers. Decoration only, no collision.
- Sounds are original, synthesised by `tools/mksounds.py` (sine waves and filtered noise): bolt cast and hit,
  melee hit, ground area, ward, tower shot, champion and minion death, four footsteps. Played in 3D at the event.
- Camera: walls and structures shorten the arm, and a second ray to the hips pulls it in when a low wall would
  hide the body (never below 1.6 m).

## Not in this build (on purpose)

Third regular abilities, champions 10 to 20, item recipes or actives. See `docs/ROADMAP.md`.
