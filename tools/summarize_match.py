import sys, json
seed = sys.argv[1] if len(sys.argv) > 1 else "?"
t = sys.stdin.read()
if "MATCHLOG" not in t:
    print(f"seed {seed}: no result. {t[:400]}")
    sys.exit(1)
d = json.loads(t[t.index("MATCHLOG") + 9:].splitlines()[0])
errors = t.count("SCRIPT ERROR")
fell = [(e["t"], e["unit"]) for e in d["events"] if e["event"] == "structure_destroyed"]
deaths = sum(c["deaths"] for c in d["champions"].values())
print(f"seed {seed}: {d['winner']} by {d['reason']} at {d['duration']/60:.1f} min | champion deaths {deaths} "
      f"(kills {d['kills']}) | objective {d['objective_captures']} | first fight {d['first_champion_fight']:.0f}s "
      f"| script errors {errors} | longest gap without structure damage {d['longest_gap_without_structure_damage']:.0f}s | structures fell {[(round(a), b) for a, b in fell]}")
