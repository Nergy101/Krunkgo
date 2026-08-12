#!/usr/bin/env bash
# Evidence pipeline for one gauntlet round.
#   tools/round.sh <round-name>
# Produces shots/<round-name>/*.png and shots/<round-name>/bench.json,
# and fails loudly on any GDScript parse error.
set -uo pipefail

GODOT="${GODOT:-/Applications/Godot_mono.app/Contents/MacOS/Godot}"
ROUND="${1:-r0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/shots/$ROUND"

cd "$ROOT"
mkdir -p "$OUT"

echo "== parse check =="
ERR="$("$GODOT" --headless --path . --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|Failed to load script" || true)"
if [ -n "$ERR" ]; then
	echo "$ERR"
	echo "PARSE FAILED"
	exit 1
fi
echo "clean"

echo "== bench (8s, vsync off, full bot fight) =="
"$GODOT" --path . --resolution 1600x900 -- bench=8 botfight seed=7 2>&1 \
	| grep -E "^BENCH" | sed 's/^BENCH //' > "$OUT/bench.json" || true
cat "$OUT/bench.json"

echo "== map shots =="
"$GODOT" --path . --resolution 1600x900 -- "shots=res://shots/$ROUND" shotset=map seed=7 2>&1 \
	| grep -E "^SHOT" || true

echo "== gameplay shots =="
"$GODOT" --path . --resolution 1600x900 -- "shots=res://shots/$ROUND" shotset=game seed=7 2>&1 \
	| grep -E "^SHOT" || true

echo "== done: $OUT =="
ls -1 "$OUT"
