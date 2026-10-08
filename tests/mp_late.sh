#!/bin/bash
# Multiplayer: joining a shift that's already under way.
cd "$(dirname "$0")/.."
port=$((24900 + RANDOM % 300))
out=$(mktemp -d)
tests/run.sh 200 --headless --path . -s tests/mp.gd -- host_late $port > "$out/host" 2>&1 &
hp=$!
tests/run.sh 200 --headless --path . -s tests/mp.gd -- late $port > "$out/client" 2>&1 &
cp=$!
wait $hp; h=$?
wait $cp; c=$?
grep -hE "^(ok|FAIL)|SCRIPT ERROR|mp.gd" "$out/host" "$out/client"
rm -rf "$out"
[ $h -eq 0 ] && [ $c -eq 0 ]
