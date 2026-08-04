# Finder menu item — "Add to VS Code Workspace"
#
# Sends the selection to the last active VS Code window instead of opening a new
# one. The two kinds of item mean different things there, so they take different
# CLI flags:
#
#   folders -> --add           attach as workspace roots (VS Code documents
#                              --add as taking <folder>)
#   files   -> --reuse-window  open as editors in that same window
#
# macOS-only by design. No success dialog: the window updating is the feedback.
# Only failures are reported.
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

# See vscode.zsh — VS Code must already be running so the sandboxed extension
# never becomes its parent.
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
	alert "VS Code CLI not found" "Expected at:
$cli

Adding to an existing workspace needs the bundled CLI — LaunchServices cannot
express it."
	exit 1
fi

if ! ensure_running "$app"; then
	alert "Could not start VS Code" "VS Code was found at:
$app
but it did not come up within 10 seconds."
	exit 1
fi

typeset -a dirs files
for p in "$@"; do
	if [[ -d $p ]]; then
		dirs+=("$p")
	else
		files+=("$p")
	fi
done

rc=0
(( $#dirs ))  && { "$cli" --add "${dirs[@]}"           || rc=$? }
(( $#files )) && { "$cli" --reuse-window "${files[@]}" || rc=$? }

(( rc == 0 )) || alert "Could not add to VS Code workspace" "$cli exited $rc"
