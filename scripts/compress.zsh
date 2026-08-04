# Finder Quick Action — "Compress (APFS Transparent)"
# macOS-only by design: BSD stat/du, /sbin/mount, zsh idioms and osascript are intentional.
emulate -L zsh

APPLESAUCE=/opt/homebrew/bin/applesauce
SF_RESTRICTED=0x80000     # SIP flag on /System, /usr, /bin, /sbin

alert() {
	/usr/bin/osascript - "$1" "$2" <<'OSA'
on run argv
	display alert (item 1 of argv) message (item 2 of argv) buttons {"OK"} default button "OK"
end run
OSA
}

human() {  # KiB -> human readable
	/usr/bin/awk -v k="$1" 'BEGIN {
		b = k * 1024; split("B KB MB GB TB PB", u, " "); i = 1
		while (b >= 1024 && i < 6) { b /= 1024; i++ }
		printf "%.1f %s", b, u[i]
	}'
}

disk_kb() {  # summed on-disk KiB for every argument
	local total=0 v p
	for p in "$@"; do
		v=$(/usr/bin/du -sk "$p" 2>/dev/null | /usr/bin/tail -1 | /usr/bin/cut -f1)
		total=$(( total + ${v:-0} ))
	done
	print -r -- $total
}

# --- mount table, read once ------------------------------------------------
# `mount` prints e.g.  /dev/disk3s1s1 on / (apfs, sealed, local, read-only)
typeset -a MP_POINTS MP_TYPES
load_mounts() {
	local line rest m t
	while IFS= read -r line; do
		rest=${line#* on }
		m=${rest%% \(*}
		t=${rest#*\(}
		t=${t%%,*}
		t=${t%%\)*}
		MP_POINTS+=("$m")
		MP_TYPES+=("$t")
	done < <(/sbin/mount)
}

mount_of() {  # -> "mountpoint<TAB>fstype" for the longest mount point containing $1
	# NB: do not name the local `path` — in zsh that is the special array tied to
	# $PATH, and ${path[...]} would subscript the array instead of the string.
	local tgt=$1 best="" bestt="" m i
	for (( i = 1; i <= $#MP_POINTS; i++ )); do
		m=$MP_POINTS[i]
		# "$m" is quoted so metacharacters in mount point names stay literal
		if [[ $m == "/" || $tgt == "$m" || $tgt == "$m"/* ]]; then
			if (( $#m >= $#best )); then
				best=$m
				bestt=$MP_TYPES[i]
			fi
		fi
	done
	print -r -- "$best	$bestt"
}

is_restricted() {  # SIP-protected?
	local f
	f=$(/usr/bin/stat -f %f "$1" 2>/dev/null) || return 1
	[[ -n $f ]] || return 1
	(( f & SF_RESTRICTED ))
}

(( $# )) || exit 0

if [[ ! -x $APPLESAUCE ]]; then
	alert "applesauce not found" "Expected at:
$APPLESAUCE

Install it with:
brew install Dr-Emann/homebrew-tap/applesauce"
	exit 1
fi

load_mounts

# --- classify the selection ------------------------------------------------
typeset -a targets skipped
home_real=${HOME:A}

for p in "$@"; do
	rp=${p:A}
	name=${p:t}
	[[ -n $name ]] || name=$rp     # basename of "/" is empty

	if is_restricted "$rp"; then
		skipped+=("$name — SIP-protected system path")
		continue
	fi

	info=$(mount_of "$rp")
	mp=${info%%	*}
	ft=${info##*	}

	if [[ $rp == "/" || ( -n $mp && $rp == $mp ) ]]; then
		skipped+=("$name — volume root, too broad")
		continue
	fi

	if [[ $rp == $home_real ]]; then
		skipped+=("$name — home folder root, too broad")
		continue
	fi

	if [[ $ft != apfs && $ft != hfs ]]; then
		skipped+=("$name — ${ft:-unknown} volume, no APFS/HFS+ compression")
		continue
	fi

	targets+=("$p")
done

skip_block=""
if (( $#skipped )); then
	skip_block=$'\n'"Skipped $#skipped item(s):"$'\n'
	for s in $skipped; do skip_block+="• $s"$'\n'; done
fi

if (( $#targets == 0 )); then
	alert "Nothing to compress" "Every selected item was skipped.
${skip_block}"
	exit 0
fi

# --- compress --------------------------------------------------------------
before=$(disk_kb "${targets[@]}")
output=$("$APPLESAUCE" compress --verify "${targets[@]}" 2>&1)
rc=$?                     # `status` is read-only in zsh — do not use it here
after=$(disk_kb "${targets[@]}")

if (( rc != 0 )); then
	alert "Compression failed" "$output"
	exit 1
fi

saved=$(( before - after ))
(( saved < 0 )) && saved=0
pct=$(/usr/bin/awk -v b="$before" -v s="$saved" 'BEGIN { printf "%.1f", (b > 0 && s > 0) ? s * 100.0 / b : 0 }')

names=""
for p in "${targets[@]:0:10}"; do names+="• ${p:t}"$'\n'; done
(( $#targets > 10 )) && names+="• … and $(( $#targets - 10 )) more"$'\n'

alert "Compressed $#targets item(s)" "${names}
Before:   $(human $before)
After:    $(human $after)
Saved:    $(human $saved)   (${pct}%)
${skip_block}
Editing a file drops its compression — re-run this action after changes.
Undo with:  applesauce decompress <path>"
