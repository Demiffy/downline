#!/bin/bash
# An observer photo across a crew (host + client, headless).
cd "$(dirname "$0")/.."
port=$((24600 + RANDOM % 300))
out=$(mktemp -d)
tests/run.sh 200 --headless --path . -s tests/mp_photo.gd -- host $port > "$out/host" 2>&1 &
hp=$!
tests/run.sh 200 --headless --path . -s tests/mp_photo.gd -- client $port > "$out/client" 2>&1 &
cp=$!
wait $hp; h=$?
wait $cp; c=$?
grep -hE "^(ok|FAIL)|SCRIPT ERROR|mp_photo.gd" "$out/host" "$out/client"
[ "$1" = "-v" ] && { echo "--- host"; cat "$out/host"; echo "--- client"; cat "$out/client"; }
rm -rf "$out"
[ $h -eq 0 ] && [ $c -eq 0 ]
