#!/bin/bash
# Runs the headless test suites side by side and reports each one.
#   tests/all.sh          quick: logic + one-station smoke + stranding + monsters + scrap loop + hazards/menu
#   tests/all.sh full     the three-station smoke instead of the one-station one
cd "$(dirname "$0")/.."
mode="${1:-quick}"
out=$(mktemp -d)
smoke_arg="quick"; [ "$mode" = "full" ] && smoke_arg="full"
declare -a names=(check smoke stranded monsters loop hazards levels lift voice_play kit creatures2 save photo_drop thin_items)
tests/run.sh 120 --headless --path . -s tests/check.gd > "$out/check" 2>&1 &
tests/run.sh 300 --headless --path . -s tests/smoke.gd -- "$smoke_arg" > "$out/smoke" 2>&1 &
tests/run.sh 150 --headless --path . -s tests/stranded.gd > "$out/stranded" 2>&1 &
tests/run.sh 300 --headless --path . -s tests/monsters.gd > "$out/monsters" 2>&1 &
tests/run.sh 120 --headless --path . -s tests/loop.gd > "$out/loop" 2>&1 &
tests/run.sh 150 --headless --path . -s tests/hazards.gd > "$out/hazards" 2>&1 &
tests/run.sh 400 --headless --path . -s tests/levels.gd > "$out/levels" 2>&1 &
tests/run.sh 120 --headless --path . -s tests/lift.gd > "$out/lift" 2>&1 &
tests/run.sh 120 --headless --path . -s tests/voice_play.gd > "$out/voice_play" 2>&1 &
tests/run.sh 150 --headless --path . -s tests/kit.gd > "$out/kit" 2>&1 &
tests/run.sh 200 --headless --path . -s tests/creatures2.gd > "$out/creatures2" 2>&1 &
tests/run.sh 200 --headless --path . -s tests/save.gd > "$out/save" 2>&1 &
tests/run.sh 200 --headless --path . -s tests/photo_drop.gd > "$out/photo_drop" 2>&1 &
tests/run.sh 200 --headless --path . -s tests/thin_items.gd > "$out/thin_items" 2>&1 &
wait
fail=0
for n in "${names[@]}"; do
	line=$(grep -E "^[a-z0-9_]+\.gd: " "$out/$n" | tail -1)
	if [[ "$line" == *"ALL PASSED"* ]]; then
		echo "PASS  $n"
	else
		fail=1
		echo "FAIL  $n   ${line:-(no result - crashed or timed out)}"
		grep -E "^FAIL|SCRIPT ERROR" "$out/$n" | head -8 | sed 's/^/        /'
		[ -z "$line" ] && tail -5 "$out/$n" | sed "s/^/        /"
	fi
done
rm -rf "$out"
exit $fail
