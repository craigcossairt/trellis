#!/usr/bin/env bash
# =============================================================================
# check-cdpath-cd.sh - a cd into a script's own directory must clear CDPATH
# =============================================================================
# A script finds its siblings with `cd` into `dirname` of its own path. When the
# caller has CDPATH exported (`CDPATH=.` is a common shell-profile line) and ran
# the script by a RELATIVE path, bash resolves that relative directory THROUGH
# CDPATH, and a cd that resolved through CDPATH ECHOES the directory to stdout.
# Inside a `$(...)` capture the echo lands in the variable, which then holds two
# lines, and every helper path built from it names nothing:
#
#   CDPATH=. bash -c 'd="$(cd "$(dirname bin/x.sh)" && pwd)"; printf "[%s]\n" "$d"'
#
# prints the directory twice. In this template that broke the sensitive-file
# hook (it refused EVERY edit, having lost its path helper) and the Cursor/Grok
# adapter, which the wiring runs as `bash bin/run-claude-hook.sh` - a relative
# path - and which fails OPEN on a missing target, so it allowed every edit,
# .env included. A bare cd (not captured) is wrong too: CDPATH can resolve it
# to a DIFFERENT directory of the same name, silently.
#
# The guarded form, which never consults CDPATH and never echoes:
#
#   HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
#
# Rule: a `cd` (any options) whose argument is built from `$(dirname ...)`,
# `${BASH_SOURCE[0]%/*}` or `${0%/*}` must carry an EMPTY `CDPATH=` assignment
# as its prefix (`CDPATH=''`, `CDPATH=""` or a bare `CDPATH=`). A non-empty
# prefix is not a guard.
#
# What it does not see: the two-step form (`d=$(dirname "$0"); cd "$d"`) and a
# cd into any other variable derived from a relative path. The rule is scoped to
# the one-expression self-location idiom, which is where the bug was measured.
#
# The surface is every tracked `*.sh` and `.githooks/*` file - the same set the
# lint step in hooks CI (shellcheck) reads.
#
# OPT-OUT: `# cdpath-ok: <reason>` on the line, as a real shell comment. The
# reason is REQUIRED.
#
# Usage:
#   check-cdpath-cd.sh [--list]
#     --list  print file:line for each site instead of failing (always exits 0;
#             a reporting mode, not a gate)
#
# Exit codes:
#   0  clean
#   1  at least one unguarded site on the surface
#   2  could not scan (not a repo, no surface, unreadable file)
#
# Behavior is pinned by bin/tests/test-check-cdpath-cd.sh.
# =============================================================================
set -uo pipefail

MODE="${1:-count}"
case "$MODE" in
  count | --list) ;;
  *)
    echo "check-cdpath-cd: unknown mode '$MODE' (expected --list or nothing)" >&2
    exit 2
    ;;
esac

if ! ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || [ -z "$ROOT" ]; then
  echo "check-cdpath-cd: not inside a git repository - cannot scan." >&2
  exit 2
fi
cd "$ROOT" || exit 2

# Captured into a variable, not piped, so a failed listing is visible here. A
# surface that could not be listed is not a surface with nothing on it, and an
# EMPTY one is a scan with no input, not a clean scan.
if ! SURFACE=$(git ls-files -- '*.sh' '.githooks/*' 2>/dev/null); then
  echo "check-cdpath-cd: could not list the shell surface - refusing to report a pass." >&2
  exit 2
fi
[ -n "$SURFACE" ] || { echo "check-cdpath-cd: empty shell surface - refusing to report a pass." >&2; exit 2; }

# This file is scanned by its own rule. Pure comment lines are skipped and it
# contains no self-locating cd at all, so the self-scan is clean without
# excluding this path.
OUT=$(SURFACE="$SURFACE" perl -e '
  my @files = grep { length } split /\n/, ($ENV{SURFACE} // "");
  my @hits;
  my $unreadable = 0;
  # A cd, with any options (-P is the symlink-safe idiom) and an optional --,
  # whose argument starts with the script own directory: a dirname
  # substitution, or the parameter-expansion spelling of it on BASH_SOURCE or
  # $0. Optionally inside double quotes.
  my $opts       = qr/(?:-[LPe@]+\s+)*(?:--\s+)?/;
  my $selfdir    = qr/"?(?:\$\(\s*dirname\b|\$\{(?:BASH_SOURCE(?:\[0\])?|0)%)/;
  my $cd_dirname = qr/(?<![\w-])cd\s+$opts$selfdir/;
  # The same, with an EMPTY CDPATH assignment immediately before the cd.
  my $guarded    = qr/(?<![\w])CDPATH=(?:\x27\x27|""|)\s+cd\s+$opts$selfdir/;
  for my $f (@files) {
    my $fh;
    unless (open $fh, "<", $f) { $unreadable++; print STDERR "check-cdpath-cd: cannot read $f\n"; next; }
    my $n = 0;
    while (my $line = <$fh>) {
      $n++;
      $line =~ s/\r?\n\z//;
      next if $line =~ /^\s*#/;
      # The opt-out counts only as a real shell comment: quoted spans are
      # removed first (a marker inside quotes is data), and the # must start a
      # word, since a # glued to a word is literal in shell.
      (my $bare = $line) =~ s/"(?:\\.|[^"\\])*"|\x27[^\x27]*\x27//g;
      next if $bare =~ /(?:^|\s)#\s*cdpath-ok:\s*\S/;
      my $all = () = $line =~ /$cd_dirname/g;
      next unless $all;
      my $ok = () = $line =~ /$guarded/g;
      push @hits, "$f:$n" if $all > $ok;
    }
    close $fh;
  }
  exit 3 if $unreadable;
  print "$_\n" for @hits;
')
PERL_RC=$?

if [ "$PERL_RC" = 3 ]; then
  echo "check-cdpath-cd: at least one file could not be read - refusing to report a pass." >&2
  exit 2
elif [ "$PERL_RC" != 0 ]; then
  echo "check-cdpath-cd: the scan failed (perl exit $PERL_RC) - refusing to report a pass." >&2
  exit 2
fi

if [ "$MODE" = "--list" ]; then
  [ -n "$OUT" ] && printf '%s\n' "$OUT"
  exit 0
fi

if [ -z "$OUT" ]; then
  echo "check-cdpath-cd: clean - every cd into a script's own directory clears CDPATH"
  exit 0
fi

COUNT=$(printf '%s\n' "$OUT" | awk 'NF { n++ } END { print n + 0 }')
echo "check-cdpath-cd: $COUNT cd(s) into a dirname-derived directory without a CDPATH guard:" >&2
printf '%s\n' "$OUT" | sed 's/^/  /' >&2
cat >&2 <<'EOF'

  With CDPATH exported and the script run by a RELATIVE path, that cd resolves
  through CDPATH and echoes the directory, so a $(...) capture holds two lines
  and every sibling path built from it breaks. Clear CDPATH on the cd itself:

    HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"

  If a line provably cannot see CDPATH, annotate it:
    # cdpath-ok: <why>
EOF
exit 1
