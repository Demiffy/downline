#!/bin/bash
# Two game windows over ENet: the host acts, the client takes screenshots of what it sees.
# usage: tests/mp_shots.sh <out_dir> [quick]
cd "$(dirname "$0")/.."
out=${1:-/tmp/mp_shots}
port=$((24900 + RANDOM % 90))
mkdir -p "$out"
tests/run.sh 400 --path . --resolution 1280x720 --position 0,0 -s tests/mp_shots.gd -- host $port "$out" $2 > "$out/host.log" 2>&1 &
hp=$!
tests/run.sh 400 --path . --resolution 1280x720 --position 640,360 -s tests/mp_shots.gd -- client $port "$out" $2 > "$out/client.log" 2>&1 &
cp=$!
wait $hp
wait $cp
grep -hE "SCRIPT ERROR|no ack|no mirror|done" "$out/host.log" "$out/client.log"
ls "$out"/*.png | wc -l
