# Network notes (Gate 1)

## What exists

- **Dedicated server** (`--server`, run headless) owns the `CombatAuthority`: movement, casting, cooldowns,
  projectiles, damage, death, respawn. Clients never send positions or damage, only `UnitCommand`s.
- **Transport**: Godot's ENet multiplayer peer (UDP) with RPCs on one `Net` node.
  - Client to server: one packet per physics tick holding the last 4 commands, unreliable ordered. The server
    (`NetInputController`) queues them and applies one per tick in client tick order, so a lost packet costs
    nothing; a gap repeats movement but never an ability press; silence for 0.5 s stops the champion.
  - Server to client: a compact binary snapshot of every unit at 20 Hz (`SnapshotCodec`), unreliable ordered,
    with a per-player ack (the last client tick applied). About 140 bytes for the court test; 32 busy units fit
    in 1,171 bytes, under ENet's 1,392 byte MTU (the old `var_to_bytes` format was 4,816). Reliable events for
    spawn, despawn, projectiles, ground areas, damage, death and respawn.
- **Input sanitising**: wrong types, NaN and infinity are dropped, move is clamped to length 1, unknown buttons
  are masked off. Range, cooldowns and teams are enforced by the same unit rules as offline. A server-side guard
  also stops any unit from being carried faster than its move speed in one tick.
- **Seats and reconnect**: each client sends a token. A dropped player's champion is held for 20 s; the same
  token gets the same champion back. Clients retry every 2 s after a failed or lost connection, and leave
  gracefully on quit.
- **Client view**: the player's own champion is predicted (`Unit.predict_step`, the same `step_motion` the
  server runs) and reconciled on each snapshot: reset to the server state at the ack, replay the newer commands,
  fade out the leftover error (snap above 2.5 m). The replay runs at the start of a physics tick, because
  `move_and_slide()` outside one uses the render delta. Other units are interpolated 100 ms behind the server
  clock. Projectiles and glyphs are drawn from events and moved locally for visuals only. `--no-predict` turns
  prediction off for comparison.
- **Simulated conditions**: `--lag=MS --jitter=MS --loss=0..1` apply to everything a process sends (loss only
  to unreliable messages). Both sides can set them.

## How it was tested

`python3 tests/net_test.py` starts a server and four client processes on one machine (Linux, cloud container),
all headless, drives them with `NetTestDriver`, and checks the logs. 29 checks (25 with `--no-predict`):

- three clients join and get their own champions; no engine or script errors in any process
- A's bolts and glyphs damage B on the server (only legal values 42 and 85); B's client sees the hits
- B dies, A is credited, A's client sees the death, B respawns
- A's champion moves about 18 m under server authority and A's view matches the server
- client C sends move vectors of length 70, aim points 7 km away and every button bit: it never moves faster
  than 6.2 m/s and its glyphs land at most 14 m away
- B quits, the server holds its champion, B reconnects with the same token and controls the same unit; A sees
  no duplicate
- every snapshot fits one 1,392 byte packet
- with prediction: own movement shows within 50 ms (median), the mean correction is under 5 cm, corrections
  over 25 cm are under 1%, none over 1 m

Results on 2026-10-20 (before prediction):

| Conditions (each direction) | Checks | Own movement visible after input |
|---|---|---|
| none | 24 / 24 | about 100 ms (one 483 ms outlier at join) |
| 50 ms +/- 10, 2% loss | 24 / 24 | 217 to 233 ms |
| 100 ms +/- 30, 5% loss | 24 / 24 | 300 to 350 ms |

Results on 2026-10-21 (with prediction and compact snapshots):

| Conditions (each direction) | Checks | Own movement visible | Mean correction | Largest | Snapshot |
|---|---|---|---|---|---|
| none | 29 / 29 | 17 to 33 ms | 1 mm | 0.07 m | 131 to 149 B |
| 50 ms +/- 10, 2% loss | 29 / 29 | 17 to 33 ms | 1 mm | 0.21 m | 131 to 149 B |
| 100 ms +/- 30, 5% loss | 29 / 29 | 17 to 33 ms | 2 mm | 0.62 m (1 of 1,223 over 0.25 m) | 131 to 149 B |
| 50 ms, `--no-predict` | 25 / 25 | 233 to 267 ms | n/a | n/a | 131 to 149 B |
| 100 ms, `--no-predict` | 25 / 25 | 317 to 367 ms | n/a | n/a | 131 to 149 B |

The simulation draws each packet's delay independently, so +/- 30 ms jitter reorders packets far more than a
real path usually does; the rare larger corrections come from that.

A networked client was also rendered (software OpenGL) against a live server and showed both champions,
health bars, bolts and telegraphs.

## What this does not prove

- Everything ran on one machine over localhost with simulated conditions. Real internet paths (NAT, Wi-Fi
  bursts, packet reordering beyond the simulation, MTU) are untested. **Not internet ready.**
- No human has played a networked session. Control feel over the network is unknown.
- Only 3 to 4 clients were tested, on one map, for about 30 s.

## Still needed before networked play feels right

1. ~~Client-side prediction and reconciliation for the local champion.~~ Done 2026-10-21 (movement, cast
   slow, dash, stun). A human still has to play it.
2. **Predicted casts.** The cast start is predicted for movement already; next, start the windup animation,
   telegraph and a visual-only projectile locally on press; the server stays the authority for release and hits.
3. **Lag compensation for hits** (or accept "server sees it" rules and keep projectiles slow and wide enough).
   Needs design before skillshots feel fair at 100 ms.
4. **Interpolation tuning**: adaptive delay from measured jitter; extrapolation limits when snapshots stop.
5. **Bandwidth**: ~~quantised positions and angles~~ done 2026-10-21. Delta snapshots or interest management
   only if a bigger match passes the packet budget (about 220 bytes of headroom at 32 busy units).
6. **Security**: rate limiting, token authentication, server-side checks that commands come at a sane rate.
7. **Session flow**: lobby, match start and end over the network, and host migration (or none, with a
   dedicated server only).

The offline game is unchanged and still the default.
