#!/usr/bin/env bash
# Remove everything install.sh puts on the system. Compressed files are left
# alone — they stay readable with or without this tool. To undo compression:
#     applesauce decompress <path>
#
# macOS-only by design.
set -euo pipefail

APP_NAME="AFSC Finder Menu"
EXT_ID="local.afsc.FinderMenu.Extension"
APP_DEST="/Applications/$APP_NAME.app"
SERVICES="$HOME/Library/Services"

if [ -d "$APP_DEST" ]; then
	pluginkit -r "$APP_DEST/Contents/PlugIns/AFSCFinderExtension.appex" 2>/dev/null || true
	rm -rf "$APP_DEST"
	echo "removed $APP_DEST"
fi

for name in "Compress (APFS Transparent).workflow" "Show Actual Size on Disk.workflow"; do
	if [ -d "$SERVICES/$name" ]; then
		rm -rf "$SERVICES/$name"
		echo "removed $SERVICES/$name"
	fi
done

/System/Library/CoreServices/pbs -flush 2>/dev/null || true
killall Finder 2>/dev/null || true

echo "done"
pluginkit -m -i "$EXT_ID" 2>/dev/null | grep -q . \
	&& echo "note: pluginkit still lists $EXT_ID; it clears on next login" || true
