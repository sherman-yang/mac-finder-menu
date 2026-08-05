#!/usr/bin/env bash
# Remove com.apple.quarantine marks that an OLD build of this project applied.
#
# Builds before the broker change ran menu scripts inside the sandboxed Finder
# extension. Compression rewrites each file (temp copy + rename), and files
# created by a sandboxed process inherit com.apple.quarantine — so every file
# compressed by such a build was marked. Gatekeeper then refuses to load native
# extensions (.so, .dylib), which is how this surfaced: a virtualenv whose
# .so files all raised "Apple could not verify … is free of malware".
#
# Only marks whose agent field is AFSCFinderExtension are removed. Genuine
# quarantine from browsers, chat apps and the like is left alone — a blanket
# `xattr -dr com.apple.quarantine` would strip those too and quietly weaken
# Gatekeeper on real downloads.
#
# Dry run by default. Pass --apply to make changes.
#
# macOS-only by design.
set -euo pipefail

AGENT="AFSCFinderExtension"
APPLY=0
declare -a DIRS=()

for arg in "$@"; do
	case "$arg" in
		--apply) APPLY=1 ;;
		-h|--help)
			echo "usage: $(basename "$0") [--apply] <dir>..."
			echo "  Removes com.apple.quarantine marks applied by $AGENT."
			echo "  Without --apply, only reports what would change."
			exit 0
			;;
		-*) echo "unknown option: $arg" >&2; exit 2 ;;
		*)  DIRS+=("$arg") ;;
	esac
done

if (( ${#DIRS[@]} == 0 )); then
	echo "usage: $(basename "$0") [--apply] <dir>..." >&2
	exit 2
fi

for dir in "${DIRS[@]}"; do
	[ -d "$dir" ] || { echo "skip (not a directory): $dir" >&2; continue; }
	echo "==> $dir"

	# find -xattrname is a single-pass predicate; xattr is read in batches so the
	# scan does not fork once per file (that turns minutes into seconds).
	APPLY="$APPLY" AGENT="$AGENT" /usr/bin/perl - "$dir" <<'PERL'
use strict;
use warnings;

my ($dir)  = @ARGV;
my $apply  = $ENV{APPLY};
my $agent  = $ENV{AGENT};

open(my $find, "-|", "find", $dir, "-type", "f", "-xattrname", "com.apple.quarantine")
	or die "find failed: $!";
my @files;
while (<$find>) { chomp; push @files, $_ }
close $find;

my (@ours, %other);
while (my @chunk = splice(@files, 0, 400)) {
	open(my $x, "-|", "xattr", "-p", "com.apple.quarantine", @chunk) or next;
	my $i = 0;
	while (my $line = <$x>) {
		chomp $line;
		# With several files, xattr prefixes each value with "path: ".
		my $path = $chunk[$i];
		if (@chunk > 1 && $line =~ s/^(.*?):\s//) { $path = $1 }
		$i++;
		my $who = (split /;/, $line)[2] // '(unknown)';
		if ($who eq $agent) { push @ours, $path } else { $other{$who}++ }
	}
	close $x;
}

printf "    marked by %s: %d\n", $agent, scalar @ours;
printf "    left alone: %s\n",
	(%other ? join(", ", map { "$_ ($other{$_})" } sort keys %other) : "none");

exit 0 unless @ours;

unless ($apply) {
	print "    dry run — pass --apply to remove them\n";
	exit 0;
}

my $done = 0;
while (my @chunk = splice(@ours, 0, 400)) {
	system("xattr", "-d", "com.apple.quarantine", @chunk) == 0
		or warn "    xattr -d failed on a batch\n";
	$done += @chunk;
}
printf "    removed: %d\n", $done;
PERL
done

if (( APPLY == 0 )); then
	echo
	echo "Nothing changed. Re-run with --apply to remove the marks."
fi
