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

echo "== extra shot sets =="
for set in fx ads class scope; do
	"$GODOT" --path . --resolution 1600x900 -- "shots=res://shots/$ROUND" shotset=$set seed=3 2>&1 \
		| grep -cE "^SHOT" || true
done

# Probes belong in the round, not in a hand-typed chain per round. One of those
# chains silently produced a ZERO-BYTE movetest.json and it was handed to a
# critic as evidence; the critic correctly refused the piece. Nothing downstream
# reads these files, so an empty one is invisible until someone opens it.
echo "== probes =="
run_probe() {   # name, args..., -> $OUT/<name>.json, must be non-empty
	local name="$1"; shift
	"$GODOT" --path . --resolution 1280x720 -- "$@" 2>&1 \
		| grep -E "^$(echo "$name" | tr '[:lower:]' '[:upper:]')" > "$OUT/$name.json" || true
	if [ ! -s "$OUT/$name.json" ]; then
		printf '\nPROBE FAILED: %s produced no output (%s is empty)\n' "$name" "$OUT/$name.json"
		printf 'Refusing to hand a critic an empty evidence file.\n'
		exit 1
	fi
	printf '  %-10s %6s bytes\n' "$name" "$(wc -c < "$OUT/$name.json" | tr -d ' ')"
}
run_probe movetest movetest seed=7
run_probe bottest  bottest  seed=7
run_probe hittest  hittest  seed=7

echo "== done: $OUT =="
ls -1 "$OUT"
