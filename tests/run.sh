#!/bin/sh
# usage: tests/run.sh <secs> <godot args...>
# Runs godot with a time limit, silent (the dummy audio driver). A test that needs a window (a shot
# script: no --headless) opens it behind whatever you're working in: Godot brings itself to the
# front as it starts, so the app you were in is put back in front the moment it does (on a Mac).
secs=$1; shift
case " $* " in
	*" --headless "*) exec perl -e "alarm $secs; exec @ARGV" godot --audio-driver Dummy "$@" ;;
esac
front=""
if command -v osascript >/dev/null 2>&1; then
	front=$(osascript -e 'tell application "System Events" to name of first application process whose frontmost is true' 2>/dev/null)
fi
perl -e "alarm $secs; exec @ARGV" godot --audio-driver Dummy "$@" &
pid=$!
lower() { echo "$1" | tr 'A-Z' 'a-z'; }
if [ -n "$front" ] && [ "$(lower "$front")" != "godot" ]; then
	(
		for i in $(seq 1 60); do   # (up to 15 s for its window to come up)
			sleep 0.25
			now=$(osascript -e 'tell application "System Events" to name of first application process whose frontmost is true' 2>/dev/null)
			if [ "$(lower "$now")" = "godot" ]; then
				osascript -e "tell application \"$front\" to activate" >/dev/null 2>&1
				break
			fi
			kill -0 $pid 2>/dev/null || break
		done
	) &
fi
wait $pid
