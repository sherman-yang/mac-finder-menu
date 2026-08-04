#!/usr/bin/env bash
# Build and install both front-ends:
#   1. FinderSync extension  -> two items at the TOP LEVEL of the context menu
#   2. Automator Quick Actions -> same two items in the Services submenu
#      (fallback for iCloud-managed Desktop/Documents, where Finder suppresses
#      FinderSync extension items)
#
# macOS-only by design. Needs Command Line Tools; Xcode is not required.
set -euo pipefail

HERE=$(cd -- "$(dirname -- "$0")" && pwd -P)
APP_NAME="AFSC Finder Menu"
EXT_ID="local.afsc.FinderMenu.Extension"
APP_DEST="/Applications/$APP_NAME.app"
SERVICES="$HOME/Library/Services"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

command -v applesauce >/dev/null 2>&1 || cat <<'WARN'
warning: `applesauce` was not found on PATH.
         The compress action expects it at /opt/homebrew/bin/applesauce.
         Install it with:
             brew install Dr-Emann/homebrew-tap/applesauce
WARN

# --- 1. FinderSync extension ----------------------------------------------
echo "==> building FinderSync extension"
bash "$HERE/finder-extension/build.sh"

echo "==> installing to $APP_DEST"
# pkd does not pick up extensions from ~/Applications; /Applications is required.
rm -rf "$APP_DEST"
/usr/bin/ditto "$HERE/finder-extension/build/$APP_NAME.app" "$APP_DEST"

"$LSREGISTER" -f "$APP_DEST"
pluginkit -a "$APP_DEST/Contents/PlugIns/AFSCFinderExtension.appex"
pluginkit -e use -i "$EXT_ID"

# --- 2. Automator Quick Actions -------------------------------------------
echo "==> building Quick Actions"
/usr/bin/python3 "$HERE/quick-actions/build_quickactions.py"

echo "==> installing to $SERVICES"
mkdir -p "$SERVICES"
for bundle in "$HERE/quick-actions/build/"*.workflow; do
	name=$(basename "$bundle")
	rm -rf "$SERVICES/$name"
	/usr/bin/ditto "$bundle" "$SERVICES/$name"
	echo "    $name"
done
/System/Library/CoreServices/pbs -flush 2>/dev/null || true

# --- restart Finder so both front-ends load -------------------------------
killall Finder 2>/dev/null || true
sleep 3

echo
echo "==> installed"
pluginkit -m -p com.apple.FinderSync -v 2>/dev/null | grep -i afsc || \
	echo "    WARNING: extension is not registered — see docs/FINDINGS.md"
echo
echo "Right-click any file or folder outside iCloud Desktop/Documents."
