# Network notes (Gate 1)

## What exists

- **Dedicated server** (`--server`, run headless) owns the `CombatAuthority`: movement, casting, cooldowns,
  projectiles, damage, death, respawn. Clients never send positions or damage, only `UnitCommand`s.
- **Transport**: Godot's ENet multiplayer peer (UDP) with RPCs on one `Net` node.
  - Client to server: one command per physics tick, unreliable ordered. The server keeps the newest by client
    tick and stops the champion if commands stop for 0.5 s.
  - Server to client: a snapshot of every unit at 20 Hz, unreliable ordered (about 840 bytes for 6 units, sent
    as Godot `var_to_bytes` dictionaries, not optimised). Reliable events for spawn, despawn, projectiles,
    ground areas, damage, death and respawn.
- **Input sanitising**: wrong types, NaN and infinity are dropped, move is clamped to length 1, unknown buttons
  are masked off. Range, cooldowns and teams are enforced by the same unit rules as offline. A server-side guard
  also stops any unit from being carried faster than its move speed in one tick.
- **Seats and reconnect**: each client sends a token. A dropped player's champion is held for 20 s; the same
  token gets the same champion back. Clients retry every 2 s after a failed or lost connection, and leave
  gracefully on quit.
- **Client view**: remote and local units are interpolated between snapshots 100 ms behind the server clock
  (smoothed offset). Projectiles and glyphs are drawn from events and moved locally for visuals only.
- **Simulated conditions**: `--lag=MS --jitter=MS --loss=0..1` apply to everything a process sends (loss only
  to unreliable messages). Both sides can set them.

## How it was tested

`python3 tests/net_test.py` starts a server and four client processes on one machine (Linux, cloud container),
all headless, drives them with `NetTestDriver`, and checks the logs. 24 checks:

- three clients join and get their own champions; no engine or script errors in any process
- A's bolts and glyphs damage B on the server (only legal values 42 and 85); B's client sees the hits
- B dies, A is credited, A's client sees the death, B respawns
- A's champion moves about 18 m under server authority and A's view matches the server
- client C sends move vectors of length 70, aim points 7 km away and every button bit: it never moves faster
  than 6.2 m/s and its glyphs land at most 14 m away
- B quits, the server holds its champion, B reconnects with the same token and controls the same unit; A sees
  no duplicate

Results on 2026-10-20:

| Conditions (each direction) | Checks | Own movement visible after input |
|---|---|---|
| none | 24 / 24 | about 100 ms (one 483 ms outlier at join) |
| 50 ms +/- 10, 2% loss | 24 / 24 | 217 to 233 ms |
| 100 ms +/- 30, 5% loss | 24 / 24 | 300 to 350 ms |

A networked client was also rendered (software OpenGL) against a live server and showed both champions,
health bars, bolts and telegraphs.

## What this does not prove

- Everything ran on one machine over localhost with simulated conditions. Real internet paths (NAT, Wi-Fi
  bursts, packet reordering beyond the simulation, MTU) are untested. **Not internet ready.**
- No human has played a networked session. Control feel over the network is unknown.
- Only 3 to 4 clients were tested, on one map, for about 30 s.

## Still needed before networked play feels right

1. **Client-side prediction and reconciliation for the local champion.** Today the player's own movement shows
   up one round trip plus 100 ms later (about 230 ms at 50 ms each way). That will feel sluggish. Plan: run
   `Unit.sim_step` locally on the client's own commands, keep a history by client tick, and correct when the
   server's acknowledged state differs.
2. **Predicted casts.** Start the windup animation and telegraph locally on press; the server stays the
   authority for release and hits.
3. **Lag compensation for hits** (or accept "server sees it" rules and keep projectiles slow and wide enough).
   Needs design before skillshots feel fair at 100 ms.
4. **Interpolation tuning**: adaptive delay from measured jitter; extrapolation limits when snapshots stop.
5. **Bandwidth**: quantised positions and angles, delta snapshots, interest management once there are minions.
6. **Security**: rate limiting, token authentication, server-side checks that commands come at a sane rate.
7. **Session flow**: lobby, match start and end over the network, and host migration (or none, with a
   dedicated server only).

The offline game is unchanged and still the default.
