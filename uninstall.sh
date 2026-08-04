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
OWNER_KEY="MacFinderMenuOwned"     # must match build_quickactions.py

if [ -d "$APP_DEST" ]; then
	pluginkit -r "$APP_DEST/Contents/PlugIns/AFSCFinderExtension.appex" 2>/dev/null || true
	rm -rf "$APP_DEST"
	echo "removed $APP_DEST"
fi

# Remove every Quick Action carrying our marker key, whatever it is named, so
# renamed menu items from older installs go too. The user's own are untouched.
for bundle in "$SERVICES"/*.workflow; do
	[ -d "$bundle" ] || continue
	/usr/bin/plutil -extract "$OWNER_KEY" raw -o - "$bundle/Contents/Info.plist" \
		>/dev/null 2>&1 || continue
	rm -rf "$bundle"
	echo "removed $bundle"
done

/System/Library/CoreServices/pbs -flush 2>/dev/null || true
killall Finder 2>/dev/null || true

echo "done"
pluginkit -m -i "$EXT_ID" 2>/dev/null | grep -q . \
	&& echo "note: pluginkit still lists $EXT_ID; it clears on next login" || true
