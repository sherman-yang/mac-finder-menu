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

# --- files currently open for writing --------------------------------------
# Compression replaces a file by writing a temp copy and renaming over it, which
# swaps the inode. A process holding the file open for WRITING goes on writing to
# the detached old inode: those writes vanish when it closes, and for a SQLite
# set (db + -wal + -shm) that is corruption. Readers are safe — an existing fd
# keeps reading consistent old data — so only w/u modes are excluded.
#
# There is no cheap "who has THIS file open" query on macOS — lsof answers it by
# walking every process's fd table, the same cost as listing everything. So the
# check cannot literally run per file. Instead the snapshot is refreshed between
# batches once it is older than SNAP_TTL seconds, which keeps each file's check
# at most a few seconds stale (batch time + TTL) instead of as stale as the whole
# run.
#
# -n -P -l are load bearing: without them lsof does reverse DNS and port/user
# lookups unrelated to files, costing ~13 s instead of ~0.4 s (measured).
#
# Two limits by design: a file opened inside the residual window is still not
# covered (a race, where without the guard it was a certainty); and an
# unprivileged lsof cannot see files held open by root daemons.
SNAP_TTL=${AFSC_SNAP_TTL:-5}
typeset -A open_writers
snap_taken=0

refresh_open_writers() {
	local now=$(/bin/date +%s)
	(( now - snap_taken < SNAP_TTL )) && return 0
	open_writers=()
	local line
	while IFS= read -r line; do
		open_writers[$line]=1
	done < <(/usr/sbin/lsof -n -P -l -u "$UID" -F an 2>/dev/null \
		| /usr/bin/awk '
			/^a/   { mode = substr($0, 2) }
			/^n\// { if (mode == "w" || mode == "u") print substr($0, 2) }')
	snap_taken=$now
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

# --- enumerate candidate files ----------------------------------------------
# Enumerating here rather than handing directories to applesauce is what makes
# the open-writer exclusion possible at all. It also skips already-compressed
# files at the find layer, so re-runs do less work. NUL-delimited, so paths with
# spaces and newlines survive — though a newline path can never match lsof's
# newline-delimited output, so it fails open: compressed, exactly as it would
# have been before this guard existed.
typeset -a files
files=("${(@0)$(/usr/bin/find "${targets[@]}" -type f ! -flags compressed -print0 2>/dev/null)}")
# NUL-splitting leaves one empty element for an empty stream — drop empties.
files=(${files:#})

if (( $#files == 0 )); then
	alert "Nothing to compress" "No uncompressed files in the selection.
${skip_block}"
	exit 0
fi

# --- compress in batches, re-checking open writers between them --------------
# Each batch is filtered against a snapshot at most SNAP_TTL seconds old, so a
# file's check happens moments before its compression, not at the start of a
# possibly long run. BATCH keeps each applesauce invocation well under ARG_MAX
# (getconf ARG_MAX = 1 MB; 500 paths ≈ 75 KB at typical lengths).
BATCH=${AFSC_BATCH:-500}
before=$(disk_kb "${targets[@]}")

open_skipped=0
compressed_count=0
rc=0
output=""
typeset -a batch eligible

for (( i = 1; i <= $#files; i += BATCH )); do
	batch=("${(@)files[i, i + BATCH - 1]}")
	refresh_open_writers

	eligible=()
	for f in "${batch[@]}"; do
		if [[ -n ${open_writers[$f]-} ]]; then
			(( open_skipped++ ))
		else
			eligible+=("$f")
		fi
	done
	(( $#eligible )) || continue

	batch_out=$("$APPLESAUCE" compress --verify "${eligible[@]}" 2>&1)
	if (( $? != 0 )); then
		rc=1
		output=$batch_out       # keep the most recent failure for the alert
	fi
	(( compressed_count += $#eligible ))
done

after=$(disk_kb "${targets[@]}")

if (( open_skipped > 0 )); then
	skip_block+="Skipped $open_skipped file(s) open for writing"$'\n'
fi

if (( compressed_count == 0 )); then
	alert "Nothing to compress" "Every uncompressed file in the selection was open for writing.
${skip_block}"
	exit 0
fi

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
