# Finder menu item — "Open in VS Code (New Window)"
#
# Opens the selection as a fresh workspace window, whether it is files, folders
# or a mix.
#
# Two paths on purpose. When VS Code is already running, the bundled `code` CLI
# expresses --new-window over IPC. When it is not, the selection is handed to
# LaunchServices in one shot (open -a with the paths) — a fresh instance IS a
# new window, launched by launchd rather than as this script's child, and there
# is nothing to poll for (see docs/FINDINGS.md for the launch-and-poll version
# this replaced).
#
# macOS-only by design. No success dialog: VS Code coming to the front is the
# feedback. Only failures are reported.
emulate -L zsh

BUNDLE_ID="com.microsoft.VSCode"

alert() {
	/usr/bin/osascript - "$1" "$2" <<'OSA'
on run argv
	display alert (item 1 of argv) message (item 2 of argv) buttons {"OK"} default button "OK"
end run
OSA
}

find_vscode() {
	local p
	for p in "/Applications/Visual Studio Code.app" \
	         "$HOME/Applications/Visual Studio Code.app"; do
		[[ -d $p ]] && { print -r -- "$p"; return 0 }
	done
	p=$(/usr/bin/mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null | /usr/bin/head -1)
	[[ -n $p && -d $p ]] && { print -r -- "$p"; return 0 }
	return 1
}

# NSRunningApplication via AppleScript: works from the sandbox (unlike pgrep),
# sends no Apple event to VS Code, and does not launch it.
is_running() {
	[[ $(/usr/bin/osascript -e "application id \"$BUNDLE_ID\" is running" 2>/dev/null) == true ]]
}

(( $# )) || exit 0

app=$(find_vscode) || {
	alert "VS Code not found" "Looked in:
/Applications
~/Applications
and Spotlight (bundle id $BUNDLE_ID)

Install it from https://code.visualstudio.com"
	exit 1
}

cli="$app/Contents/Resources/app/bin/code"

if is_running && [[ -x $cli ]]; then
	# Paths from Finder are always absolute, so none can be mistaken for a flag.
	"$cli" --new-window "$@" || alert "Could not open in VS Code" "$cli exited $?"
else
	/usr/bin/open -a "$app" -- "$@" || alert "Could not open in VS Code" "VS Code was found at:
$app
but LaunchServices refused to open the selection with it."
fi
