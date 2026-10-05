#!/bin/sh
# usage: tests/run.sh <secs> <godot args...>
secs=$1; shift
perl -e "alarm $secs; exec @ARGV" godot "$@"
