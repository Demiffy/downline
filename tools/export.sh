#!/bin/bash
# Builds the game for Windows and macOS, from either machine (Git Bash on Windows, Terminal on a Mac):
#   build/windows/        Downline.exe + Downline.pck + HOW TO PLAY.txt
#   build/mac/            Downline.zip (Godot's export: Downline.app, universal, ad-hoc signed)
#   build/Downline-<commit>-windows.zip, build/Downline-<commit>-mac.zip   what friends download
#   build/Downline.pck + build/version.json                                what the auto-updater fetches
# Both platforms run the same pack (no imported assets: everything is built in code), so one
# Downline.pck and one version.json update Windows and Mac players alike (src/updater.gd).
#   tools/export.sh            build only
#   tools/export.sh debug      also a debug Windows exe
#   tools/export.sh release    build, then publish it as the latest GitHub Release: everyone's
#                              game fetches the new pck from there on its next launch
# Needs godot 4.7.2 on PATH and its export templates (HANDOFF.md §11); `release` needs gh, logged in.
# Release from a clean, pushed main: the build is named after the commit.
set -e
cd "$(dirname "$0")/.."

ver=$(git rev-parse --short HEAD)
seq=$(git rev-list --count HEAD)
base=$(sed -n 's/^const BASE := \([0-9]*\).*/\1/p' src/version.gd)
engine=$(godot --version | cut -d. -f1-3)
repo=Demiffy/downline

if [ "$1" = "release" ]; then
	[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "uncommitted changes: commit and push first"; exit 1; }
	git fetch -q origin main
	[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "HEAD isn't origin/main: push first"; exit 1; }
	command -v gh > /dev/null || { echo "gh CLI not found"; exit 1; }
	gh release view "v$ver" --repo "$repo" > /dev/null 2>&1 && { echo "v$ver is already released"; exit 1; }
fi

sha256() { if command -v sha256sum > /dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
# zip <archive> <files...>: adds the files at the top of the archive (Mac zip, or PowerShell)
addzip() {
	local z=$1; shift
	if command -v zip > /dev/null; then zip -qj "$z" "$@"
	else
		local p=""; for f in "$@"; do p="$p,'$(cygpath -w "$f")'"; done
		powershell.exe -NoProfile -Command "Compress-Archive -Update -Path ${p#,} -DestinationPath '$(cygpath -w "$z")'"
	fi
}

rm -rf build/windows build/mac && mkdir -p build/windows build/mac

# Stamp the build into version.gd for the export; put it back however this ends.
cp src/version.gd build/version.gd.keep
trap 'mv -f build/version.gd.keep src/version.gd' EXIT
perl -pi -e "s/^const BUILD := .*/const BUILD := \"$ver\"/; s/^const SEQ := .*/const SEQ := $seq/" src/version.gd

godot --headless --path . --import > /dev/null 2>&1 || true
godot --headless --path . --export-release "Windows" build/windows/Downline.exe 2>&1 | grep -E "ERROR|error" || true
[ -f build/windows/Downline.exe ] || { echo "Windows export failed: no build/windows/Downline.exe (export templates installed?)"; exit 1; }
[ -f build/windows/Downline.pck ] || { echo "Windows export failed: no Downline.pck (embed_pck must stay off)"; exit 1; }
if [ "$1" = "debug" ]; then
	godot --headless --path . --export-debug "Windows" build/windows/Downline_debug.exe 2>&1 | grep -E "ERROR|error" || true
fi
godot --headless --path . --export-release "macOS" build/mac/Downline.zip 2>&1 | grep -E "ERROR|error" || true
[ -f build/mac/Downline.zip ] || { echo "macOS export failed: no build/mac/Downline.zip"; exit 1; }

# Boot the pack once headless with this machine's godot: it must load without script errors.
cp build/windows/Downline.pck build/Downline.pck
if (cd build && godot --headless --main-pack Downline.pck --quit-after 300 2>&1) | grep -E "SCRIPT ERROR|^ERROR"; then
	echo "the exported game printed errors on boot (above)"; exit 1
fi

cp "docs/HOW TO PLAY.txt" build/windows/
win="build/Downline-$ver-windows.zip"
mac="build/Downline-$ver-mac.zip"
rm -f "$win" "$mac"
addzip "$win" build/windows/Downline.exe build/windows/Downline.pck "build/windows/HOW TO PLAY.txt"
cp build/mac/Downline.zip "$mac"
addzip "$mac" "build/windows/HOW TO PLAY.txt"

# What the updater reads (kept out of the zips: it's only for the release).
size=$(wc -c < build/Downline.pck | tr -d ' ')
cat > build/version.json <<EOF
{"version": "$ver", "seq": $seq, "base": $base, "godot": "$engine",
 "pck_url": "https://github.com/$repo/releases/download/v$ver/Downline.pck", "sha256": "$(sha256 build/Downline.pck)", "size": $size}
EOF
ls -la build/Downline.pck "$win" "$mac"
echo "Built $ver (#$seq, base $base, Godot $engine) for Windows and macOS."

if [ "$1" = "release" ]; then
	gh release create "v$ver" --repo "$repo" --target "$(git rev-parse HEAD)" --latest \
		--title "Downline $ver" --notes "$(git log -1 --format=%s)" \
		build/Downline.pck build/version.json "$win" "$mac"
	echo "Released v$ver: games update themselves on their next launch. New players get $win or $mac."
fi
