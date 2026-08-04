# Finder Quick Action — "Show Actual Size on Disk"
# macOS-only by design: BSD du/find/stat, zsh idioms and osascript are intentional.
# UF_COMPRESSED is bit 0x20 of st_flags, so `int(flags/32) % 2` tests it without
# relying on awk bitwise functions (BSD awk has none).
emulate -L zsh

MAX_DETAIL=15

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

(( $# )) || exit 0

report=""
t_disk=0 t_app=0 t_files=0 t_comp=0 t_raw=0
shown=0

for p in "$@"; do
	d=$(/usr/bin/du -sk  "$p" 2>/dev/null | /usr/bin/tail -1 | /usr/bin/cut -f1); d=${d:-0}
	a=$(/usr/bin/du -skA "$p" 2>/dev/null | /usr/bin/tail -1 | /usr/bin/cut -f1); a=${a:-0}

	# one pass: total files, compressed files, bytes still uncompressed
	stats=$(/usr/bin/find "$p" -type f -print0 2>/dev/null \
		| /usr/bin/xargs -0 /usr/bin/stat -f '%f %z' 2>/dev/null \
		| /usr/bin/awk '{ n++; if (int($1 / 32) % 2 == 1) c++; else raw += $2 }
		                END { print n + 0, c + 0, raw + 0 }')
	n=${${(z)stats}[1]:-0}
	c=${${(z)stats}[2]:-0}
	raw=${${(z)stats}[3]:-0}
	u=$(( n - c ))

	# clamp: tiny files can occupy more on disk than their logical size (block rounding)
	pct=$(/usr/bin/awk -v a="$a" -v d="$d" 'BEGIN { printf "%.1f", (a > 0 && a > d) ? (a - d) * 100.0 / a : 0 }')

	if (( shown < MAX_DETAIL )); then
		report+="${p:t}
   On disk:    $(human $d)
   Apparent:   $(human $a)
   Saved:      ${pct}%
   Files:      $n total — $c compressed, $u not ($(human $(( raw / 1024 ))))

"
		(( shown++ ))
	fi

	t_disk=$(( t_disk + d ))
	t_app=$(( t_app + a ))
	t_files=$(( t_files + n ))
	t_comp=$(( t_comp + c ))
	t_raw=$(( t_raw + raw ))
done

(( $# > MAX_DETAIL )) && report+="… and $(( $# - MAX_DETAIL )) more item(s) not listed

"

if (( $# > 1 )); then
	tpct=$(/usr/bin/awk -v a="$t_app" -v d="$t_disk" 'BEGIN { printf "%.1f", (a > 0 && a > d) ? (a - d) * 100.0 / a : 0 }')
	report+="TOTAL ($# items)
   On disk:    $(human $t_disk)
   Apparent:   $(human $t_app)
   Saved:      ${tpct}%
   Files:      $t_files total — $t_comp compressed, $(( t_files - t_comp )) not ($(human $(( t_raw / 1024 ))))
"
fi

alert "Actual Size on Disk" "$report"
