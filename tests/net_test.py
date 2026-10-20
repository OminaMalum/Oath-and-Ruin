#!/usr/bin/env python3
"""Gate 1 multi-process network test.

Starts one dedicated server and several headless clients as separate Godot
processes on localhost, with simulated lag, jitter and loss on every process's
sends, then checks the NETLOG lines they print.

  python3 tests/net_test.py [--godot godot] [--lag 50] [--jitter 10] [--loss 0.02]

Exit code 0 when every check passes. This proves the protocol and the server
rules on one machine. It is not proof of internet play.
"""
import argparse, os, re, subprocess, sys, time, json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ap = argparse.ArgumentParser()
ap.add_argument("--godot", default="godot")
ap.add_argument("--lag", type=float, default=50)
ap.add_argument("--jitter", type=float, default=10)
ap.add_argument("--loss", type=float, default=0.02)
ap.add_argument("--port", type=int, default=24790)
ap.add_argument("--out", default="/tmp/oath_net")
a = ap.parse_args()
os.makedirs(a.out, exist_ok=True)
net = [f"--lag={a.lag}", f"--jitter={a.jitter}", f"--loss={a.loss}", "--netlog"]


def launch(name, extra, secs):
    log = open(os.path.join(a.out, name + ".log"), "w")
    cmd = [a.godot, "--headless", "--path", ROOT, "--", *extra, *net, f"--quit-after-secs={secs}"]
    return subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT), log


def client(token, mode, secs):
    return launch(token, [f"--connect=127.0.0.1:{a.port}", f"--token={token}", f"--netbot={mode}"], secs)


# Timeline (seconds from start):
#  0  server          1  A attacks, B stands still      3  C sends impossible input
# 15  B leaves (graceful)   18  B rejoins with the same token   28  everyone stops
procs = []
procs.append(launch("server", ["--server", f"--port={a.port}"], 30))
time.sleep(1.0)
procs.append(client("A", "attack", 27))   # first seat: team 0
time.sleep(0.7)
procs.append(client("B", "idle", 14))     # second seat: team 1
time.sleep(2.0)
procs.append(client("C", "cheat", 24))
time.sleep(14.5)
procs.append(launch("B2", [f"--connect=127.0.0.1:{a.port}", "--token=B", "--netbot=strafe"], 9))
for p, log in procs:
    try:
        p.wait(timeout=60)
    except subprocess.TimeoutExpired:
        p.kill()
    log.close()

logs = {}
for name in ["server", "A", "B", "C", "B2"]:
    with open(os.path.join(a.out, name + ".log")) as f:
        logs[name] = f.read()

failures = []
checks = 0


def check(cond, what):
    global checks
    checks += 1
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures.append(what)


S = logs["server"]
joined = dict(re.findall(r"joined token=(\w+) unit=(\d+)", S))
check(all(t in joined for t in "ABC"), f"three clients joined with their own champions {joined}")
uA, uB, uC = (int(joined.get(t, -1)) for t in "ABC")
for t in ["A", "B", "C"]:
    check(f"{t} welcome unit=" in logs[t], f"client {t} received its welcome")

# Server-side errors or script errors anywhere?
for name, txt in logs.items():
    bad = [l for l in txt.splitlines() if "SCRIPT ERROR" in l or l.startswith("ERROR")]
    check(not bad, f"{name}: no engine or script errors" + (f" (first: {bad[0]})" if bad else ""))

# Damage is decided by the server; the victim's client sees the same hits.
dmg_on_B = [float(x) for x in re.findall(rf"damage target={uB} amount=(\d+) source={uA}", S)]
check(len(dmg_on_B) >= 5, f"server applied A's hits to B ({len(dmg_on_B)} hits)")
# B's client is disconnected on purpose later in the run, so compare only the
# hits up to B's first death (B is still connected for all of those).
first_death = S.find(f"death target={uB}")
hits_before_death = len(re.findall(rf"damage target={uB} amount=(\d+) source={uA}", S[:first_death] if first_death >= 0 else S))
seen_B = len(re.findall(rf"saw damage target={uB}", logs["B"]))
check(seen_B >= hits_before_death * 0.8, f"B's client saw those hits ({seen_B} of {hits_before_death})")
# Arcane Bolt 42, its Inscribed third hit 63, Binding Glyph 85.
check(set(dmg_on_B) <= {42.0, 63.0, 85.0}, f"only legal damage values {sorted(set(dmg_on_B))}")

# Death and respawn.
check(re.search(rf"death target={uB} killer={uA}", S) is not None, "server killed B (A credited)")
check(re.search(rf"saw death target={uB}", logs["A"]) is not None, "A's client saw B die")
check(re.search(rf"respawn target={uB}", S) is not None, "server respawned B")

# Movement replication: final positions in A's view match the server's last
# state for the same units within half a metre, and A's own unit really moved.
def last_states(txt):
    lines = [l for l in txt.splitlines() if " state tick=" in l]
    out = {}
    if not lines:
        return out
    for m in re.finditer(r"(\d+):(-?[\d.]+),(-?[\d.]+),(\d+),([AD])", lines[-1]):
        out[int(m.group(1))] = (float(m.group(2)), float(m.group(3)), float(m.group(4)), m.group(5))
    return out

def first_state(txt, uid):
    for l in txt.splitlines():
        m = re.search(rf" {uid}:(-?[\d.]+),(-?[\d.]+),", l)
        if " state tick=" in l and m:
            return float(m.group(1)), float(m.group(2))
    return None

# Compare A's last view against the server line closest in time.
srv_lines = [l for l in S.splitlines() if " state tick=" in l]
a_lines = [l for l in logs["A"].splitlines() if " state tick=" in l]
def parse(l):
    t = float(l.split()[1])
    st = {int(m.group(1)): (float(m.group(2)), float(m.group(3))) for m in re.finditer(r"(\d+):(-?[\d.]+),(-?[\d.]+),", l)}
    return t, st
if srv_lines and a_lines:
    # A's clock started ~1 s after the server's; compare A's final state with the
    # last server state (A stands still at the end, so latency does not matter).
    _, a_last = parse(a_lines[-1])
    _, s_last = parse(srv_lines[-1])
    d = ((a_last.get(uA, (99, 99))[0] - s_last.get(uA, (0, 0))[0]) ** 2 + (a_last.get(uA, (99, 99))[1] - s_last.get(uA, (0, 0))[1]) ** 2) ** 0.5
    check(d < 0.5, f"A's view of its own champion matches the server ({d:.2f} m)")
    p0 = first_state(logs["A"], uA)
    moved = ((a_last[uA][0] - p0[0]) ** 2 + (a_last[uA][1] - p0[1]) ** 2) ** 0.5 if p0 and uA in a_last else 0
    check(moved > 5.0, f"A's champion moved under server authority ({moved:.1f} m)")
    # C (cheater) is seen by A at the same place the server has it.
    if uC in a_last and uC in s_last:
        dc = ((a_last[uC][0] - s_last[uC][0]) ** 2 + (a_last[uC][1] - s_last[uC][1]) ** 2) ** 0.5
        check(dc < 1.0, f"A sees C where the server has C ({dc:.2f} m; C may still be moving)")

# Input sanitising: C sent move vectors of length 70 and aim points 7 km away.
speeds = re.findall(r"maxspeed=(\{.*\})", S)
if speeds:
    ms = json.loads(speeds[-1])
    check(ms.get(str(uC), 99) <= 6.2 * 1.01, f"C never moved faster than run speed ({ms.get(str(uC))} m/s)")
areas_C = [float(x) for x in re.findall(rf"area source={uC} dist=([\d.]+)", S)]
check(len(areas_C) > 0 and max(areas_C) <= 14.0 + 0.01, f"C's glyphs were clamped to 14 m range ({max(areas_C) if areas_C else None})")

# Clean disconnect and reconnect to the same champion.
check(re.search(rf"peer left id=\d+ token=B unit={uB}", S) is not None, "server noticed B leave and held its champion")
check(re.search(rf"reattached token=B unit={uB}", S) is not None, "B rejoined and got the same champion back")
check("welcome unit=%d" % uB in logs["B2"], "rejoined client controls the same unit id")
n_spawn = len(re.findall(r"saw spawn unit=%d\b" % uB, logs["A"]))
check(n_spawn == 1 and "saw despawn unit=%d" % uB not in logs["A"], f"A saw B spawn once and never despawn ({n_spawn} spawns)")

# Latency evidence.
lat = [int(x) for n in ["A", "B", "C", "B2"] for x in re.findall(r"input_to_visible_ms=(\d+)", logs[n])]
snap = re.findall(r"snapshot_bytes=(\d+)", S)
print(f"\ninput to visible movement (own champion, no prediction): {lat} ms")
print(f"snapshot size: {snap[-1] if snap else '?'} bytes at 20 Hz")
print(f"conditions: lag {a.lag} ms +/- {a.jitter} ms each way, loss {a.loss:.0%} on unreliable sends")
print(f"\n{checks} checks, {len(failures)} failures")
sys.exit(1 if failures else 0)
