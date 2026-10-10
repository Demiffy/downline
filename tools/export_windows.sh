#!/bin/bash
# Builds the portable Windows game (exe + separate pck) and publishes a GitHub Release.
#   tools/export_windows.sh          -> build + GitHub Release (auto-updater picks it up)
#   tools/export_windows.sh debug    -> also exports a debug exe
#   tools/export_windows.sh local    -> build only, no release upload
# Needs godot 4.7.2 on PATH, its export templates installed (HANDOFF.md §11), and gh CLI.
set -e
cd "$(dirname "$0")/.."

ver=$(git rev-parse --short HEAD 2>/dev/null || echo dev)
out=build/windows
rm -rf "$out" && mkdir -p "$out"

# ── stamp the build version into src/version.gd ──
sed -i "s/^const BUILD := .*/const BUILD := \"$ver\"/" src/version.gd

# ── export ──
godot --headless --path . --import > /dev/null 2>&1 || true
godot --headless --path . --export-release "Windows" "$out/Downline.exe" 2>&1 | grep -E "ERROR|error" || true
[ -f "$out/Downline.exe" ] || { echo "export failed: no $out/Downline.exe"; exit 1; }
[ -f "$out/Downline.pck" ] || { echo "export failed: no $out/Downline.pck (embed_pck should be false)"; exit 1; }
if [ "$1" = "debug" ]; then
	godot --headless --path . --export-debug "Windows" "$out/Downline_debug.exe" 2>&1 | grep -E "ERROR|error" || true
fi

# ── restore version.gd so the working tree stays clean ──
sed -i "s/^const BUILD := .*/const BUILD := \"dev\"/" src/version.gd

# boot it once headless: the packed game must load without script errors
if "$out/Downline.exe" --headless --quit-after 300 2>&1 | grep -E "SCRIPT ERROR|^ERROR"; then
	echo "the exported game printed errors on boot (above)"; exit 1
fi

cp "docs/HOW TO PLAY.txt" "$out/" 2>/dev/null || true

# ── version.json for the auto-updater ──
pck_url="https://github.com/Demiffy/downline/releases/download/v${ver}/Downline.pck"
cat > "$out/version.json" <<EOF
{"version": "$ver", "pck_url": "$pck_url"}
EOF

# ── zip for manual distribution ──
zip_path="build/Downline-$ver.zip"
rm -f "$zip_path"
powershell.exe -NoProfile -Command "Compress-Archive -Path '$out\\*' -DestinationPath '$zip_path'"
ls -la "$out" "$zip_path"
echo ""
echo "Built from $ver."

if [ "$1" = "local" ]; then
	echo "Local-only build. Send $zip_path manually."
	exit 0
fi

# ── publish to GitHub Releases (the auto-updater fetches from here) ──
if ! command -v gh &> /dev/null; then
	echo "gh CLI not found; install it to publish releases automatically."
	echo "Send $zip_path manually for now."
	exit 0
fi

tag="v${ver}"
echo "Publishing release $tag ..."
# create the release (or update if it exists)
gh release create "$tag" \
	--repo "Demiffy/downline" \
	--title "Downline $ver" \
	--notes "Auto-published build $ver." \
	--latest \
	"$out/Downline.pck" \
	"$out/version.json" \
	"$zip_path" \
	2>&1 || {
	# if the tag already exists, just upload/overwrite the assets
	gh release upload "$tag" \
		--repo "Demiffy/downline" \
		--clobber \
		"$out/Downline.pck" \
		"$out/version.json" \
		"$zip_path"
}

echo ""
echo "Release $tag published. The auto-updater will pick up Downline.pck from:"
echo "  $pck_url"
echo "First-time players get $zip_path (exe + pck + how-to-play). After that, only the pck updates."
