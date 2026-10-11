#!/bin/bash
# Builds the portable Windows game: build/windows (Downline.exe + Downline.pck + HOW TO PLAY) and
# build/Downline-<commit>.zip, plus build/windows/version.json for the auto-updater (src/updater.gd).
#   tools/export_windows.sh            build only
#   tools/export_windows.sh debug      also a debug exe
#   tools/export_windows.sh release    build, then publish it as the latest GitHub Release: everyone's
#                                      game fetches the new pck from there on its next launch
# Needs godot 4.7.2 on PATH and its export templates (HANDOFF.md §11); `release` needs gh, logged in.
# Release from a clean, pushed main: the build is named after the commit.
set -e
cd "$(dirname "$0")/.."

ver=$(git rev-parse --short HEAD)
seq=$(git rev-list --count HEAD)
base=$(sed -n 's/^const BASE := \([0-9]*\).*/\1/p' src/version.gd)
engine=$(godot --version | cut -d. -f1-3)
out=build/windows
repo=Demiffy/downline

if [ "$1" = "release" ]; then
	[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "uncommitted changes: commit and push first"; exit 1; }
	git fetch -q origin main
	[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "HEAD isn't origin/main: push first"; exit 1; }
	command -v gh > /dev/null || { echo "gh CLI not found"; exit 1; }
	gh release view "v$ver" --repo "$repo" > /dev/null 2>&1 && { echo "v$ver is already released"; exit 1; }
fi

rm -rf "$out" && mkdir -p "$out"

# Stamp the build into version.gd for the export; put it back however this ends.
cp src/version.gd build/version.gd.keep
trap 'mv -f build/version.gd.keep src/version.gd' EXIT
sed -i -e "s/^const BUILD := .*/const BUILD := \"$ver\"/" -e "s/^const SEQ := .*/const SEQ := $seq/" src/version.gd

godot --headless --path . --import > /dev/null 2>&1 || true
godot --headless --path . --export-release "Windows" "$out/Downline.exe" 2>&1 | grep -E "ERROR|error" || true
[ -f "$out/Downline.exe" ] || { echo "export failed: no $out/Downline.exe"; exit 1; }
[ -f "$out/Downline.pck" ] || { echo "export failed: no $out/Downline.pck (embed_pck must stay off)"; exit 1; }
if [ "$1" = "debug" ]; then
	godot --headless --path . --export-debug "Windows" "$out/Downline_debug.exe" 2>&1 | grep -E "ERROR|error" || true
fi

# boot it once headless: the packed game must load without script errors
if "$out/Downline.exe" --headless --quit-after 300 2>&1 | grep -E "SCRIPT ERROR|^ERROR"; then
	echo "the exported game printed errors on boot (above)"; exit 1
fi

cp "docs/HOW TO PLAY.txt" "$out/"
zip="build/Downline-$ver.zip"
rm -f "$zip"
powershell.exe -NoProfile -Command "Compress-Archive -Path '$out\\*' -DestinationPath '$zip'"

# What the updater reads (kept out of the zip: it's only for the release).
sha=$(sha256sum "$out/Downline.pck" | cut -d' ' -f1)
size=$(stat -c %s "$out/Downline.pck")
cat > build/version.json <<EOF
{"version": "$ver", "seq": $seq, "base": $base, "godot": "$engine",
 "pck_url": "https://github.com/$repo/releases/download/v$ver/Downline.pck", "sha256": "$sha", "size": $size}
EOF
ls -la "$out" "$zip"
echo "Built $ver (#$seq, base $base, Godot $engine)."

if [ "$1" = "release" ]; then
	gh release create "v$ver" --repo "$repo" --target "$(git rev-parse HEAD)" --latest \
		--title "Downline $ver" --notes "$(git log -1 --format=%s)" \
		"$out/Downline.pck" build/version.json "$zip"
	echo "Released v$ver: games update themselves on their next launch. New players get $zip."
fi
