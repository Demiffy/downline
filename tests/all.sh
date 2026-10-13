#!/bin/bash
# Runs the headless test suites and reports each one: as many at once as the machine has cores
# (all 18 at once overloaded it: everything slowed down and the timing-sensitive checks failed),
# the longest first so the run ends with the quick ones. A suite that fails is run once more on its
# own: if it passes then, that's reported (a check that only fails under load).
#   tests/all.sh          quick: logic + one-station smoke + stranding + monsters + scrap loop + hazards/menu
#   tests/all.sh full     the three-station smoke instead of the one-station one
#   JOBS=4 tests/all.sh   at most 4 at once
cd "$(dirname "$0")/.."
mode="${1:-quick}"
out=$(mktemp -d)
smoke_arg="quick"; [ "$mode" = "full" ] && smoke_arg="full"
jobs="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 6)}"
# name, time limit (s), extra args; longest first
suites=(
	"stranded 200"
	"monsters 300"
	"levels 400"
	"hazards 200"
	"husk_follow 150"
	"kit 200"
	"photo_drop 200"
	"lift 120"
	"voice_play 120"
	"smoke 300 $smoke_arg"
	"creatures2 200"
	"save 200"
	"thin_items 200"
	"loop 120"
	"site_clock 150"
	"economy 120"
	"settings_logic 60"
	"check 120"
)
run_one() {
	set -- $1
	local name=$1 secs=$2 extra=$3
	if [ -n "$extra" ]; then
		tests/run.sh "$secs" --headless --path . -s "tests/$name.gd" -- "$extra" > "$out/$name" 2>&1
	else
		tests/run.sh "$secs" --headless --path . -s "tests/$name.gd" > "$out/$name" 2>&1
	fi
}
export -f run_one
export out
start=$(date +%s)
printf '%s\n' "${suites[@]}" | xargs -P "$jobs" -I{} bash -c 'run_one "{}"'
fail=0
for s in "${suites[@]}"; do
	n=${s%% *}
	line=$(grep -E "^[a-z0-9_]+\.gd: " "$out/$n" | tail -1)
	if [[ "$line" != *"ALL PASSED"* ]]; then   # once more, alone: some checks are timing-sensitive under the load of the rest
		first=$(grep -E "^FAIL" "$out/$n" | head -3)
		run_one "$s"
		line=$(grep -E "^[a-z0-9_]+\.gd: " "$out/$n" | tail -1)
		[[ "$line" == *"ALL PASSED"* ]] && { echo "PASS  $n   (passed on retry, alone; under load:)"; echo "$first" | sed 's/^/        /'; continue; }
	fi
	if [[ "$line" == *"ALL PASSED"* ]]; then
		echo "PASS  $n"
	else
		fail=1
		echo "FAIL  $n   ${line:-(no result - crashed or timed out)}"
		grep -E "^FAIL|SCRIPT ERROR" "$out/$n" | head -8 | sed 's/^/        /'
		[ -z "$line" ] && tail -5 "$out/$n" | sed "s/^/        /"
	fi
done
echo "($(( $(date +%s) - start )) s, $jobs at a time)"
rm -rf "$out"
exit $fail
