#!/usr/bin/env bash
# Bot behaviour across several seeds. A single 14 s run is a lottery: the same
# seed produced 31.7%, 48.1% and 64.4% engagement for one bot on three
# consecutive runs, and a critic reasonably read one 0.0% sample as a stranded
# bot. Claims about "the worst bot" need more than one draw.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-shots/sweep}"; mkdir -p "$OUT"
GODOT="${GODOT:-/Applications/Godot_mono.app/Contents/MacOS/Godot}"
for s in 1 2 3 4 5; do
  # No timeout(1) here: it is not on PATH for spawned scripts, and with
  # || true swallowing the failure every run silently produced an empty file.
  "$GODOT" --path . --resolution 1280x720 -- bottest seed=$s 2>&1 \
    | grep -E "^BOTTEST" > "$OUT/bottest_seed$s.json" || true
  # An empty run must not be averaged away. The aggregate happily reported
  # "runs": 4 from a five-seed sweep, which is the same silent-empty-evidence
  # bug that cost a critic round when movetest.json came out zero bytes.
  if [ ! -s "$OUT/bottest_seed$s.json" ]; then
    printf '\nPROBE FAILED: bottest seed=%s produced no output\n' "$s"
    exit 1
  fi
done
python3 - "$OUT" <<'PY'
import json, sys, glob, statistics as st
d = sys.argv[1]
runs = []
for f in sorted(glob.glob(f"{d}/bottest_seed*.json")):
    t = open(f).read().strip()
    if t:
        runs.append(json.loads(t[8:]))
eng = [v["engage_pct"] for r in runs for v in r["per_bot"].values()]
cov = [v["cover_pct"] for r in runs for v in r["per_bot"].values()]
air = [v["air_pct"] for r in runs for v in r["per_bot"].values()]
out = {
    "runs": len(runs),
    "bot_samples": len(eng),
    "engage_min": min(eng), "engage_mean": round(st.mean(eng), 1), "engage_max": max(eng),
    "bots_below_10pct_engage": sum(1 for e in eng if e < 10.0),
    "air_max": max(air),
    "cover_users_pct": round(100.0 * sum(1 for c in cov if c > 0) / len(cov), 1),
    "avg_engage_by_run": [r["avg_engage_pct"] for r in runs],
    "hits_per_sec_by_run": [r["bot_hits_per_sec"] for r in runs],
    "jumps_per_sec_by_run": [r["bot_jumps_per_sec"] for r in runs],
}
open(f"{d}/botsweep.json", "w").write(json.dumps(out, indent=1))
print("BOTSWEEP", json.dumps(out))
PY
