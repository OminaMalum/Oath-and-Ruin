# Art direction (working notes)

Source: three concept boards Anthony shared on 2026-10-20. They are **direction only**. No generative AI art goes
into the game, and nothing is cropped, traced or extracted from the boards.

## Goals

- Stylized fantasy with rich, believable materials: weathered stone, worn leather, painted metal, restrained jewel
  colours. Ancient places with history, vegetation and believable construction.
- Combat readability first: clear ground, visible windups, restrained spell effects, compact UI with subtle
  fantasy detail. Large, well spaced type.
- Our own identity. Not a copy of any existing franchise.

## Cues worth keeping from the boards

- Champions with strong silhouettes: a shield-and-mace frontliner (round shield with a tree motif), a robed caster
  with a lantern and a raven, a hooded twin-blade skirmisher.
- Structures: towers as crystal shrines on stepped stone bases with hanging banners.
- Neutral objective idea: a huge armoured beast carrying a ruined shrine on its shell.
- Two moods: autumn daylight and rain-wet night with warm lanterns.
- Evolution path for one small arena: graybox, complete match, network proof, art foundation, playable alpha,
  polished target. Networking experiments stay in graybox.

## Current placeholder palette (`scripts/view/palette.gd`)

Stone greys and warm sandstone, moss, leather browns, brass, autumn orange, lapis, teal accent. Telegraphs: allies
teal, enemies amber (not red beside blue).

## Asset rules

Primitives until an asset is original or clearly licensed (prefer CC0 / CC-BY / commercial-compatible). Keep
replacement-friendly: 1 unit = 1 m, models face -Z, feet at origin, champion height about 1.8 m, capsule radius
0.45 m. Future rigs need consistent socket names (`hand_r`, `hand_l`, `focus`, `head`, `back`) and animation names
(`idle`, `run`, `cast_windup`, `cast_release`, `hit`, `death`).
