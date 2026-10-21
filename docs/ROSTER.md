# PactFall roster plan: the first 20 champions

Working names only. Every name gets a screening pass (stores, marks, other games) before it is final, the same
way the game name is being screened. Three champions exist in the build; the other 17 are planned.

## Rules every champion follows

- **Kit shape**: basic attack, three abilities, one ultimate, one passive. Built gradually: basic plus one ability
  first, then the second, then the rest. Today's three have two abilities each.
- **Every ability** states its purpose, tell, counterplay, and how it interacts with movement and crowd control.
  All numbers live in `data/abilities/*.tres`, never in code.
- **Three axes** separate roles: distance (how far it fights from), commitment (how hard it is to leave a fight),
  mobility (how it gets in and out). No two champions in a role share the same point on all three.
- **D&D seat**: the party role it covers. **Synergy tag**: the one team interaction it is built around, the way a
  card is built for a deck. Each tag appears on at least two champions so teams can be drafted around it.
- **Crowd control budget**: one hard CC per kit at most (stun, root, knock, pull). Slows are soft and free.
- **No hidden information** the bots cannot also respect: stealth is "harder to see" (range), never invisible.
- **Art**: placeholder primitives first, then original models. No generative AI art.

## Lore brief

The shape of this section follows the Spires of Ruin lore handoff (hard rules, factions, one colour and one
silhouette hook per hero, open questions). The content is PactFall's own. Nothing here is shared with Spires of
Ruin: no place, faction or character name crosses over, and the two worlds are not connected.

**The world in one paragraph.** PactFall is set on the Causeway, a ruined stone road between two shrines where
five Houses once swore a single pact that bound the land's magic to its keepers. The pact broke in one night (the
Pactfall) and the Houses have fought over the shrine stones since. A match is two companies of three, Oath and
Ruin, each trying to break the other's shrine core. Minions are the Houses' bound levies; the Shrinebearer is a
stone warden that still walks the old route and can be claimed by whoever puts it down. Tone: grounded heroic
fantasy, weathered stone, worn leather, painted metal, restrained jewel colours. No modern slang, no archaic
"thee and thou", combat barks under eight words. Teen rating: blood, no dismemberment of humanoids.

**Hard rules**
- Original only. No gods or figures from real mythology (this is not a SMITE style roster), no Tolkien names or
  phrasing, no champion that reads as another MOBA's champion in name, colour and silhouette together. Check every
  new name against Middle-earth, SMITE, League and Dota before it is used.
- The D&D seats in the role grid are internal shorthand. No "Dungeons & Dragons" wording in the product, no
  product identity monsters, and the roster never shows a class name to the player.
- No name shared with Spires of Ruin. Cindermaw was that game's dragon, so champion 14 is Brindlemaw. Lanternkeeper
  and Thornwright stand (Spires has a Lantern King and a Thornwood, which are places, not characters), but if either
  world ships first the other renames.
- Names: every working name gets one screening pass (stores, marks, other games) before it is final, like the game
  name was. Plain compound words (Bellwether, Saltwarden) are preferred over coined ones.
- Readability over lore. A champion owns one colour that reads at 12 m and one silhouette hook that reads at
  48 m. Team colour (teal for Oath, orange for Ruin) always wins over the champion colour on rings, bars and
  tells. Never red directly beside blue.
- No generative AI art. Lore art is hand made or licensed, and reference boards are reference only.

**The five Houses** (one per synergy tag, so a draft tells a story)
| House | Tag | What it kept | How it fights | Mark |
|---|---|---|---|---|
| Wardens | Oath | The pact itself: shields, wards, vows | Stand, protect, commit | Round shield with a broken seal |
| Scribes | Line | The pact's words: glyphs, chains, lines | Set up, then punish | An open scroll with one burnt line |
| Unbound | Ember | Nothing. They burnt their copy | Kill, reset, go again | A snapped chain link |
| Causeway | Tide | The road and the levies that march it | Push, buff the wave, break walls | A milestone with a tally |
| Reeves | Hunt | The hunt for the forsworn | Find, mark, chase | A hound's head in profile |

A champion with two tags belongs to one House and has a tie to the other (Lanternkeeper is a Warden who keeps a
Reeve's raven).

**Colour and silhouette hooks** for the three in the build, as the model for the rest:
| Champion | House | Colour | Silhouette hook | Voice in one line |
|---|---|---|---|---|
| Ruinscribe | Scribes | Oxblood | A tall staff with a hanging scroll case, a hooded cowl | Dry, precise, counts aloud |
| Oathwarden | Wardens | Slate and brass | A round shield wider than the shoulders, a squared helm | Few words, all of them "hold" |
| Ashrunner | Unbound | Soot brown with a green ember | Twin short blades and a long loose scarf | Quick, mocking, never finishes a sentence |

Each of the other seventeen gets this table row when its batch starts, and the row is written before any model.

**Open questions**
1. Why did the pact fall? A betrayal by one House (the Unbound) is the obvious default. The Scribes' version and
   the Wardens' version should disagree, so the story has two tellings.
2. Who holds the shrines between matches? Suggest: nobody. The match is one night of a war that has lasted a
   generation.
3. Does the Shrinebearer have a name? Suggest not yet; it earns one when a player community gives it one.
4. Does PactFall share a world with any other game of Anthony's? Default: no.

## Role grid

| Role | D&D seat | Count | Distance | Commitment | Mobility |
|---|---|---|---|---|---|
| Frontline | fighter, barbarian, paladin | 4 | melee | high | low |
| Spellcaster | wizard, sorcerer, warlock | 4 | long | low | low |
| Skirmisher | rogue, monk, ranger (melee) | 4 | melee to short | medium | high |
| Support | cleric, bard, druid | 4 | short to mid | medium | low to medium |
| Marksman | ranger (bow), artificer | 2 | long | low | medium |
| Controller | enchanter, trapper | 2 | mid | medium | low |

## Synergy tags

- **Oath** (protect and commit): wards, shields, taunts; the frontline and support core.
- **Line** (set up and punish): slows, roots and walls that line enemies up for pierces and arcs.
- **Ember** (burst and reset): kill a target, get something back (cooldown, dash, heal).
- **Tide** (push the lane): minion buffs, structure damage, wave control; ties into rising tide and Breakers.
- **Hunt** (find and chase): marks, reveals, long chases; counters flanks and the objective route.

## The twenty

| # | Name | Role | D&D seat | Distance / commitment / mobility | Signature | Tag | Counter | Status |
|---|---|---|---|---|---|---|---|---|
| 1 | Ruinscribe | Spellcaster | wizard | long / low / low | Binding Glyph (delayed circle, slow); Unmaking Lance (piercing line) | Line | dive it, spread out | In build |
| 2 | Oathwarden | Frontline | fighter | melee / high / low | Warding Stand (allies inside take less); Shield Slam (short stun) | Oath | kite it, fight outside the ward | In build |
| 3 | Ashrunner | Skirmisher | rogue | melee / medium / high | Vault (leap through enemies); Ember Knife (thrown slow) | Ember | stun the leap, stand by your frontline | In build |
| 4 | Lanternkeeper | Support | cleric | short / medium / low | Lantern light heals allies who stand in it; a raven that reveals a flank for 4 s | Oath, Hunt | kill it first, fight outside the light | Batch B |
| 5 | Thornwright | Marksman | ranger | long / low / medium | Longbow with a charged shot; a bramble that slows a path | Line | flank it, close the distance | Batch B |
| 6 | Gravebinder | Controller | warlock | mid / medium / low | Chains that root the first enemy hit; a grasping ground that pulls to its centre | Line | bait the chain, hold your dash | Batch B |
| 7 | Barrowking | Frontline | barbarian | melee / high / low | Taunting roar (enemies near must attack it for 1.5 s); grows tougher while below half health | Oath | ignore it, burn it from range | Batch C |
| 8 | Veilsinger | Support | bard | mid / low / medium | Song that speeds allied attacks; a charm that turns an enemy to walk away for 1 s | Ember | silence the song by stunning it | Batch C |
| 9 | Stormscald | Spellcaster | evoker | long / low / low | Called lightning on a point after 1.2 s; a storm wall that blocks shots for 3 s | Line | move early, wait out the wall | Batch C |
| 10 | Quillhand | Skirmisher | assassin | melee / medium / high | Fade: harder to see beyond 6 m for 3 s; backstab bonus from behind | Hunt, Ember | stay in a group, face it | Batch C |
| 11 | Ironvow | Frontline | paladin | melee / high / low | Vow with one ally: both take less damage while within 6 m; Smite on a stunned target | Oath | split the pair, stun it first | Batch D |
| 12 | Bellwether | Support | commander | mid / medium / low | Rally: nearby minions push faster and hit harder; horn that calls the next wave early | Tide | kill the wave, catch it alone | Batch D |
| 13 | Mirewalker | Controller | druid | mid / medium / medium | Pools that slow and leave a trail; a root on anyone who stays in a pool 1.5 s | Line | walk round, not through | Batch D |
| 14 | Brindlemaw | Skirmisher | beast | melee / medium / high | Pounce; a bite that heals it on a kill | Ember, Hunt | ward the carry, no free kills | Batch D |
| 15 | Hearthmother | Support | tank cleric | short / high / low | Shield on an ally that bursts when it breaks; a stone wall for 3 s | Oath | break the shield on a minion first | Batch E |
| 16 | Riftcaller | Spellcaster | conjurer | long / low / high | Short blink; a gate that lets allies walk through once (counters the objective route) | Hunt | hold a stun for the blink | Batch E |
| 17 | Saltwarden | Controller | trapper | mid / low / low | Visible salt lines that slow; a snare that roots after a 1 s arm time | Line, Tide | see the lines, step over them | Batch E |
| 18 | Emberhand | Frontline | duelist | melee / medium / medium | Parry: blocks the next hit in 0.5 s and ripostes; a short lunge | Ember | wait out the parry, hit it with a ground area | Batch E |
| 19 | Duskreeve | Marksman | kiter | mid / low / high | Short hops after each shot; a net that slows | Hunt | gap close with a stun, corner it | Batch F |
| 20 | Oathbreaker | Spellcaster | ruin warlock | mid / medium / low | Drains health from a champion over 2 s; steals the next buff cast near it | Tide, Line | break the drain with a stun, do not buff near it | Batch F |

Counts: frontline 4 (2, 7, 11, 18), spellcaster 4 (1, 9, 16, 20), skirmisher 4 (3, 10, 14, and 19 leans
there), support 4 (4, 8, 12, 15), marksman 2 (5, 19), controller 3 (6, 13, 17).

## Build order

Each batch is a runnable checkpoint with tests, a soak and a Windows build, like the gates so far.

| Batch | Champions | What it proves | New sim rules needed |
|---|---|---|---|
| A (done) | 1, 2, 3 | Roles differ on the three axes; one team interaction | melee arc, dash, ward, pierce, stun |
| B | 4, 5, 6 | A full 3v3 of six different picks; healing, reveals, roots | heal over time in an area, reveal (sight range for bots), root, pull, charged cast |
| C | 7, 8, 9, 10 | Taunt, buffs, a blocking wall, soft stealth | taunt (forced target), allied buffs, projectile-blocking walls, "hard to see" ranges |
| D | 11, 12, 13, 14 | Paired vows, minion command, trails, on-kill resets | linked units, minion stat buffs, trail areas, on-kill triggers |
| E | 15, 16, 17, 18 | Shields, blinks, gates, parry | shields (temporary health), teleport, armed traps, parry windows |
| F | 19, 20 | Kiting, drains, buff stealing | channel, buff ownership |

Between batches: ultimates and passives for the champions already in, one batch behind. So batch B also brings
the third ability for 1, 2 and 3.

## Bots

Every rule above is written as a bot rule at the same time (use when, step out when). A champion is not done
until bots play it well enough that a 12 seed soak ends every match and no champion goes above 55% of all kills
across the soak.

## Risks

- Twenty kits is 20 x 5 abilities plus passives. The build order keeps the game playable at every step, but the
  full roster is a long way off; the next gate (readability and presentation) comes before batch C.
- Names: all working names, screened in one pass later. Several are plain words (Bellwether) and may be easier
  to clear than coined ones.
- Taunt, charm and stealth are the rules most likely to feel bad; each gets a test on the Proving Court with a
  human before it goes into a match.
