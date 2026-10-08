#!/bin/bash
# Multiplayer end to end: a host and a client, two headless game processes over ENet.
cd "$(dirname "$0")/.."
port=$((24600 + RANDOM % 300))
out=$(mktemp -d)
tests/run.sh 200 --headless --path . -s tests/mp.gd -- host $port > "$out/host" 2>&1 &
hp=$!
tests/run.sh 200 --headless --path . -s tests/mp.gd -- client $port > "$out/client" 2>&1 &
cp=$!
wait $hp; h=$?
wait $cp; c=$?
grep -hE "^(ok|FAIL)|SCRIPT ERROR|mp.gd" "$out/host" "$out/client"
[ "$1" = "-v" ] && { echo "--- host"; cat "$out/host"; echo "--- client"; cat "$out/client"; }
rm -rf "$out"
[ $h -eq 0 ] && [ $c -eq 0 ]
