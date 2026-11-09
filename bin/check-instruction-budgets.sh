#!/usr/bin/env bash
# =============================================================================
# check-instruction-budgets.sh - byte budgets for the AGENTS.md files
# =============================================================================
# Adapted from phuryn/product-engineering,
# agent-harness/skills/agent-instructions/scripts/check_budgets.py
# (MIT, (c) 2026 Pawel Huryn). The pattern taken: a checked-in budgets file,
# a per-file verdict, and "(review YYYY-MM)" tags listed once their month has
# passed. What changed: bytes instead of words (Codex truncates by bytes),
# concatenation sums, optional files, and exit 2 for "could not run".
#
# WHY. Codex loads AGENTS.md text only up to project_doc_max_bytes (32768 by
# default) and drops the rest without a warning: the agent simply never sees
# the rules past the cut, and nothing in the session says so. This template's
# own AGENTS.md ships close to that default, and filling in its FILL-IN slots
# grows it, so a copy can cross the line on its first afternoon. Nothing fails
# when that happens; this does.
#
# If you raise project_doc_max_bytes (in ~/.codex/config.toml on each machine
# that runs Codex), raise `limit` in bin/instruction-budgets.txt to match, and
# the root AGENTS.md `file` budget with it, in the same change. If your project never runs Codex, delete the budgets file:
# CI then prints a skip instead of failing.
#
# WHAT CODEX CONCATENATES. It walks up from the working directory to the
# nearest project_root_markers entry (default `.git`), then joins every
# AGENTS.md from there down to the working directory with a blank line. So a
# nested sub/AGENTS.md is loaded together with the root file whenever Codex
# starts inside sub/. Budget that pair with a `sum` line; each sum adds the
# 2-byte blank-line separator.
#
# INPUTS. bin/instruction-budgets.txt, one directive per line, `#` comments:
#   limit    <bytes>                  Codex's project_doc_max_bytes
#   share    <1-100>                  percent of limit any concatenation may use
#   file     <name> <path> <bytes>    a required file and its own budget
#   optional <name> <path> <bytes>    measured when present, NOT CHECKED if not
#   sum      <name> <name>...         a concatenation, checked against the cap
# Paths are relative to the repo root (the working directory). A file in a
# sibling checkout is `optional`: measured on a machine that has it, reported
# NOT CHECKED in CI. NOT CHECKED is never printed as ok and never counted as
# under budget.
#
# Usage:  bin/check-instruction-budgets.sh [--today YYYY-MM]
# Exit:   0 = every measured file and sum is within budget
#         1 = something is over
#         2 = COULD NOT RUN (no budgets file, a malformed line, a required file
#             missing or unreadable, a bad argument). No verdict is printed.
# Review tags past their month are listed and never change the exit code.
#
# Perl for the parsing (same engine on macOS, Git Bash and Linux runners).
# bash 3.2 compatible.
# =============================================================================
set -euo pipefail

TODAY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --today)
      [ $# -ge 2 ] || { echo "check-instruction-budgets: --today needs YYYY-MM" >&2; exit 2; }
      TODAY="$2"; shift 2 ;;
    *)
      echo "check-instruction-budgets: unknown argument '$1' (expected --today YYYY-MM)" >&2
      exit 2 ;;
  esac
done

if [ -z "$TODAY" ]; then
  TODAY="$(date +%Y-%m)" || { echo "check-instruction-budgets: could not read the date" >&2; exit 2; }
fi

CONFIG="bin/instruction-budgets.txt"
if [ ! -f "$CONFIG" ]; then
  echo "check-instruction-budgets: $CONFIG not found - run from the repo root" >&2
  exit 2
fi

# perl's own status is the script's status: die -> 2, over -> 1, clean -> 0.
rc=0
TODAY="$TODAY" perl -e '
use strict;
use warnings;

# Any die is "could not run", whatever errno perl would have exited with.
$SIG{__DIE__} = sub { print STDERR "check-instruction-budgets: $_[0]"; exit 2; };

sub fatal { print STDERR "check-instruction-budgets: $_[0]\n"; exit 2; }

my $today = $ENV{TODAY};
fatal("bad --today `$today`, expected YYYY-MM")
  unless $today =~ /\A\d{4}-(0[1-9]|1[0-2])\z/;

my $cfg = $ARGV[0];
open my $fh, "<", $cfg or fatal("cannot read $cfg: $!");
my ($limit, $share);
my (%file, @order, @sums);
my $n = 0;
while (my $line = <$fh>) {
  $n++;
  $line =~ s/#.*//;
  $line =~ s/\s+\z//;
  $line =~ s/\A\s+//;
  next if $line eq "";
  my @w = split /\s+/, $line;
  my $kw = shift @w;
  if ($kw eq "limit") {
    fatal("$cfg:$n: limit takes one integer") unless @w == 1 && $w[0] =~ /\A[1-9]\d*\z/;
    fatal("$cfg:$n: limit declared twice") if defined $limit;
    $limit = $w[0];
  } elsif ($kw eq "share") {
    fatal("$cfg:$n: share takes one integer 1-100")
      unless @w == 1 && $w[0] =~ /\A\d+\z/ && $w[0] >= 1 && $w[0] <= 100;
    fatal("$cfg:$n: share declared twice") if defined $share;
    $share = $w[0];
  } elsif ($kw eq "file" || $kw eq "optional") {
    fatal("$cfg:$n: $kw takes <name> <path> <bytes>")
      unless @w == 3 && $w[2] =~ /\A[1-9]\d*\z/;
    my ($name, $path, $budget) = @w;
    fatal("$cfg:$n: name `$name` declared twice") if exists $file{$name};
    $file{$name} = { path => $path, budget => $budget, optional => ($kw eq "optional") };
    push @order, $name;
  } elsif ($kw eq "sum") {
    fatal("$cfg:$n: sum takes two or more names") unless @w >= 2;
    push @sums, [$n, @w];
  } else {
    fatal("$cfg:$n: unknown directive `$kw`");
  }
}
close $fh;
fatal("$cfg: no limit") unless defined $limit;
fatal("$cfg: no share") unless defined $share;
fatal("$cfg: declares no file or optional entry") unless @order;
for my $s (@sums) {
  my ($ln, @names) = @$s;
  for my $nm (@names) {
    fatal("$cfg:$ln: sum names undeclared file `$nm`") unless exists $file{$nm};
  }
}

my $cap = int($limit * $share / 100);

# Measure every file before printing anything, so a required file that is
# missing stops the run with no partial verdict on screen.
my %size;
my %text;
for my $nm (@order) {
  my $f = $file{$nm};
  if (! -e $f->{path}) {
    next if $f->{optional};
    fatal("required file $f->{path} ($nm) not found");
  }
  # A directory passes -e and opens on Linux, then reads as 0 bytes: an
  # unknown that would print ok. Only a plain file is measured.
  fatal("$f->{path} ($nm) is not a plain file") unless -f $f->{path};
  # Bytes as on disk. A Windows checkout with core.autocrlf=true measures
  # CRLF bytes, which is what Codex reads there; CI measures LF, so near a
  # budget the local verdict can be stricter than the CI one.
  open my $in, "<:raw", $f->{path} or fatal("cannot read $f->{path} ($nm): $!");
  local $/;
  my $data = <$in>;
  fatal("read of $f->{path} ($nm) failed: $!") if !defined $data && $!;
  close $in;
  $data = "" unless defined $data;
  $size{$nm} = length $data;
  $text{$nm} = $data;
}

my $over = 0;
my $unchecked = 0;
printf "limit %d bytes, share %d%%: any concatenation may use %d\n", $limit, $share, $cap;
for my $nm (@order) {
  my $f = $file{$nm};
  if (!exists $size{$nm}) {
    printf "NOT CHECKED  %-8s %s (not present here)\n", $nm, $f->{path};
    $unchecked++;
    next;
  }
  my $bad = $size{$nm} > $f->{budget};
  $over++ if $bad;
  printf "%-4s %8d / %-8d %-8s %s\n", ($bad ? "OVER" : "ok"), $size{$nm}, $f->{budget}, $nm, $f->{path};
}
for my $s (@sums) {
  my ($ln, @names) = @$s;
  my $label = join " + ", @names;
  my @missing = grep { !exists $size{$_} } @names;
  if (@missing) {
    printf "NOT CHECKED  %s (%s not present here)\n", $label, join(", ", @missing);
    $unchecked++;
    next;
  }
  my $total = 2 * (@names - 1);
  $total += $size{$_} for @names;
  my $bad = $total > $cap;
  $over++ if $bad;
  printf "%-4s %8d / %-8d %s\n", ($bad ? "OVER" : "ok"), $total, $cap, $label;
}

# Review tags: report only.
for my $nm (@order) {
  next unless exists $text{$nm};
  my $ln = 0;
  for my $line (split /\n/, $text{$nm}) {
    $ln++;
    while ($line =~ /\(review (\d{4}-\d{2})\)/g) {
      print "past review $1: $file{$nm}{path}:$ln\n" if $1 lt $today;
    }
  }
}

my $note = $unchecked ? " ($unchecked NOT CHECKED, see above)" : "";
if ($over) {
  print "result: $over over budget$note\n";
  exit 1;
}
print "result: ok$note\n";
exit 0;
' "$CONFIG" || rc=$?

case "$rc" in
  0 | 1) exit "$rc" ;;
  *) exit 2 ;;
esac
