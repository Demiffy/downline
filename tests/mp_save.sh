#!/bin/bash
# Save and continue with a crew: round 1 plays and saves, round 2 continues (host + client, headless).
cd "$(dirname "$0")/.."
out=$(mktemp -d)
ok=0
for round in 1 2; do
	port=$((24600 + RANDOM % 300))
	tests/run.sh 200 --headless --path . -s tests/mp_save.gd -- host $port $round > "$out/host" 2>&1 &
	hp=$!
	tests/run.sh 200 --headless --path . -s tests/mp_save.gd -- client $port $round > "$out/client" 2>&1 &
	cp=$!
	wait $hp || ok=1
	wait $cp || ok=1
	grep -hE "^(ok|FAIL)|SCRIPT ERROR|mp_save.gd" "$out/host" "$out/client"
	[ "$1" = "-v" ] && { echo "--- host"; cat "$out/host"; echo "--- client"; cat "$out/client"; }
done
rm -rf "$out"
exit $ok
