#!/bin/bash
# Builds the game's C++ for every platform it ships on, into bin/: macOS (universal) and Windows (x86_64,
# cross-compiled with MinGW), each for the editor/tests (template_debug) and the exported game
# (template_release). Needs scons and mingw-w64 (brew install scons mingw-w64).
set -e
cd "$(dirname "$0")"
api="$(pwd)/extension_api.json"
for t in template_debug template_release; do
	scons -j8 target=$t custom_api_file="$api"
	scons -j8 platform=windows arch=x86_64 use_mingw=yes target=$t custom_api_file="$api"
done
