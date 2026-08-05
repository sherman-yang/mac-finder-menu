#!/usr/bin/env bash
# Build "AFSC Finder Menu.app" — a host app carrying a FinderSync .appex that
# puts two items at the TOP LEVEL of the Finder context menu.
#
# macOS-only by design. Needs Command Line Tools (swiftc + codesign); Xcode is
# not required.
set -euo pipefail

HERE=$(cd -- "$(dirname -- "$0")" && pwd -P)
SRC="$HERE/src"
OUT="$HERE/build"
SCRIPTS="$HERE/../scripts"        # single source of truth for the zsh actions

APP_NAME="AFSC Finder Menu"
APP_ID="local.afsc.FinderMenu"
EXT_NAME="AFSCFinderExtension"
EXT_ID="local.afsc.FinderMenu.Extension"
MIN_OS="26.0"
TARGET="$(uname -m)-apple-macos${MIN_OS}"

APP="$OUT/$APP_NAME.app"
EXT="$APP/Contents/PlugIns/$EXT_NAME.appex"

rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mkdir -p "$EXT/Contents/MacOS" "$EXT/Contents/Resources"

# --- host app -------------------------------------------------------------
xcrun swiftc -target "$TARGET" -parse-as-library \
	-framework AppKit \
	-o "$APP/Contents/MacOS/$APP_NAME" \
	"$SRC/host.swift"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>$APP_NAME</string>
	<key>CFBundleIdentifier</key><string>$APP_ID</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>$APP_NAME</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
	<!-- No Dock icon: broker launches (see host.swift) would otherwise flash one
	     for every menu click. UI mode opts back in at runtime. -->
	<key>LSUIElement</key><true/>
	<key>NSHumanReadableCopyright</key><string>Local build</string>
</dict>
</plist>
PLIST

# Menu item scripts live in the HOST app: the extension brokers every action to
# it (see host.swift), so the host is what needs them at runtime.
cp "$SCRIPTS"/*.zsh "$APP/Contents/Resources/"

# --- extension ------------------------------------------------------------
# App extensions enter through NSExtensionMain, not main(); -parse-as-library
# keeps swiftc from synthesising a top-level entry point.
xcrun swiftc -target "$TARGET" -parse-as-library \
	-framework AppKit -framework FinderSync \
	-Xlinker -e -Xlinker _NSExtensionMain \
	-o "$EXT/Contents/MacOS/$EXT_NAME" \
	"$SRC/FinderSyncExt.swift"

# NSPrincipalClass, LSUIElement and CFBundleSupportedPlatforms are all load
# bearing — without them pkd discovers the plug-in and then drops it again.
cat > "$EXT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleDisplayName</key><string>$APP_NAME</string>
	<key>CFBundleExecutable</key><string>$EXT_NAME</string>
	<key>CFBundleIdentifier</key><string>$EXT_ID</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>$EXT_NAME</string>
	<key>CFBundlePackageType</key><string>XPC!</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
	<key>LSUIElement</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionAttributes</key>
		<dict/>
		<key>NSExtensionPointIdentifier</key><string>com.apple.FinderSync</string>
		<key>NSExtensionPrincipalClass</key><string>FinderSyncExt</string>
	</dict>
</dict>
</plist>
PLIST


# --- sign (ad-hoc) --------------------------------------------------------
# Inside-out: extension first, then the app that contains it. Only the extension
# carries the sandbox entitlements — pkd requires them, the host app does not.
codesign --force --sign - --timestamp=none --entitlements "$HERE/ext.entitlements" "$EXT"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

echo "built: $APP"
