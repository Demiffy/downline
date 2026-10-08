#!/bin/bash
# Builds the portable Windows game and packs it to send to friends.
#   tools/export_windows.sh          -> build/windows/Downline.exe + build/Downline-<commit>.zip
#   tools/export_windows.sh debug    -> build/windows/Downline_debug.exe as well (for chasing bugs)
# Needs godot 4.7.2 on PATH and its export templates installed (HANDOFF.md §11).
set -e
cd "$(dirname "$0")/.."
ver=$(git rev-parse --short HEAD 2>/dev/null || echo dev)
out=build/windows
rm -rf "$out" && mkdir -p "$out"
godot --headless --path . --import > /dev/null 2>&1 || true
godot --headless --path . --export-release "Windows" "$out/Downline.exe" 2>&1 | grep -E "ERROR|error" || true
[ -f "$out/Downline.exe" ] || { echo "export failed: no $out/Downline.exe"; exit 1; }
if [ "$1" = "debug" ]; then
	godot --headless --path . --export-debug "Windows" "$out/Downline_debug.exe" 2>&1 | grep -E "ERROR|error" || true
fi
# boot it once headless: the packed game must load without script errors
if "$out/Downline.exe" --headless --quit-after 300 2>&1 | grep -E "SCRIPT ERROR|^ERROR"; then
	echo "the exported game printed errors on boot (above)"; exit 1
fi
cp "docs/HOW TO PLAY.txt" "$out/"
zip_path="build/Downline-$ver.zip"
rm -f "$zip_path"
powershell.exe -NoProfile -Command "Compress-Archive -Path '$out\\*' -DestinationPath '$zip_path'"
ls -la "$out" "$zip_path"
echo "Send $zip_path (built from $ver). Everyone in a crew needs the same build."
