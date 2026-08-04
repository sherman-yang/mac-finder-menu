# Finder menu item — "Open in VS Code (New Window)"
#
# Opens the selection as a fresh workspace window, whether it is files, folders
# or a mix.
#
# macOS-only by design. No success dialog: VS Code coming to the front is the
# feedback. Only failures are reported.
emulate -L zsh

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
	p=$(/usr/bin/mdfind "kMDItemCFBundleIdentifier == 'com.microsoft.VSCode'" 2>/dev/null | /usr/bin/head -1)
	[[ -n $p && -d $p ]] && { print -r -- "$p"; return 0 }
	return 1
}

# Start VS Code through LaunchServices if it is not running yet. This matters:
# the Finder extension is sandboxed, and a VS Code launched as its child would
# inherit that sandbox. Once VS Code is up, the `code` CLI only talks to it over
# IPC and exits, so the sandboxed child is short-lived and harmless.
ensure_running() {
	local app=$1 i
	/usr/bin/pgrep -f "$app/Contents/MacOS/" >/dev/null 2>&1 && return 0
	/usr/bin/open -g -a "$app" 2>/dev/null || return 1
	for i in {1..40}; do
		/bin/sleep 0.25
		/usr/bin/pgrep -f "$app/Contents/MacOS/" >/dev/null 2>&1 && return 0
	done
	return 1
}

(( $# )) || exit 0

app=$(find_vscode) || {
	alert "VS Code not found" "Looked in:
/Applications
~/Applications
and Spotlight (bundle id com.microsoft.VSCode)

Install it from https://code.visualstudio.com"
	exit 1
}

cli="$app/Contents/Resources/app/bin/code"

if [[ ! -x $cli ]]; then
	# No bundled CLI: LaunchServices can still open the paths, just without
	# control over which window they land in.
	/usr/bin/open -a "$app" -- "$@" 2>/dev/null || alert "Could not open in VS Code" "VS Code was found at:
$app"
	exit
fi

if ! ensure_running "$app"; then
	alert "Could not start VS Code" "VS Code was found at:
$app
but it did not come up within 10 seconds."
	exit 1
fi

# Paths from Finder are always absolute, so none can be mistaken for a flag.
"$cli" --new-window "$@" || alert "Could not open in VS Code" "$cli exited $?"
