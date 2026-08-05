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
# When VS Code is not running there is no window to add to, so the selection is
# simply opened (open -a): a fresh instance showing exactly these items is the
# closest meaning "add" has in that state — launched by launchd rather than as
# this script's child, with nothing to poll for (see docs/FINDINGS.md).
#
# macOS-only by design. No success dialog: the window updating is the feedback.
# Only failures are reported.
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

if ! is_running || [[ ! -x $cli ]]; then
	/usr/bin/open -a "$app" -- "$@" || alert "Could not open in VS Code" "VS Code was found at:
$app
but LaunchServices refused to open the selection with it."
	exit
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
