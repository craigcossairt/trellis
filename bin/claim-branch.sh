#!/usr/bin/env bash
# =============================================================================
# claim-branch.sh - is anyone already working this branch?
# =============================================================================
# `.claude/commands/worktree.md` stops two sessions sharing a CHECKOUT. Nothing
# stops them sharing a BRANCH: both fetch it clean, both commit, and the second
# push either clobbers the first or leaves the branch 1-ahead/1-behind to
# untangle by hand.
#
#   bin/claim-branch.sh <branch>                  # report; exit 1 if claimed
#   bin/claim-branch.sh <branch> --quiet          # exit code only
#   bin/claim-branch.sh <branch> --quiet-if-free  # silent on 0, loud on 1 and 2
#
#   bin/claim-branch.sh --acquire <branch> --me <session-id> [--harness <name>]
#   bin/claim-branch.sh --release <branch> --me <session-id>
#
# TWO SIGNALS, AND THEY ANSWER DIFFERENT QUESTIONS
#
# 1. AUTHOR EMAIL - commits already pushed to the branch under an email that is
#    not yours. Catches a real teammate, including one who never ran this tool.
#    It CANNOT catch a second agent session on this machine: every session
#    stamps the same user.email, so their commits are indistinguishable from
#    yours. That was the whole gap. An earlier version of this file opened by
#    describing concurrent sessions and then keyed on the one field that cannot
#    separate them.
#
# 2. LEASE - a ref refs/claims/<branch> on the remote whose commit message
#    carries session, harness, timestamp and TTL. Identity comes from --me, an
#    explicit session id, never inferred from git config. Acquiring is
#      git push --force-with-lease=refs/claims/<b>:<expected> origin <sha>:<ref>
#    with <expected> empty for a create and the read sha for a takeover.
#
# CHECKING RESERVES NOTHING, AND THAT IS WHY THE LEASE EXISTS. Signal 1 only
# reads the remote. Two sessions can both run the check, both get exit 0, and
# both start. In the project this template came from that happened four times
# before the lease was added, and every one of them was a clean fast-forward.
# If more than one session can run here, the check is a pre-flight and
# `--acquire` is the step that actually holds the branch.
#
# WHAT THE CAS IS PROVEN TO DO, and what it is not - read this before
# "simplifying" the push. Proven: two sessions racing to CREATE the same lease
# cannot both win. The loser is rejected with "reference already exists", which
# comes from git's CREATE semantics - a push computed while the ref was absent
# is sent as a create, and the server refuses a create over an existing ref
# whether or not --force is passed. A lease that moves DURING the push is also
# refused with or without --force-with-lease, because the push carries the value
# git saw when it ADVERTISED the ref. So neither of those cases demonstrates the
# flag. The window the flag actually closes is EARLIER: between lease_read and
# the push opening its connection. A ref that moves in THAT window is advertised
# as its NEW value, so a plain --force finds the old value matching and clobbers
# a live holder. Only a lease pinned to the sha we actually read refuses. Do not
# drop the flag.
#
# The lease is ADDITIVE, not a replacement. It sees sessions that ran the tool;
# the email check sees authors who did not. Dropping either trades one blind
# spot for another, so the check reports CLAIMED if EITHER fires.
#
# git reports a refused lease as "stale info", which is also what an ordinary
# out-of-date tracking ref produces. It names no author and proves nothing, so a
# refusal here is never reported from the push output: the ref is re-read and
# the holder named.
#
# --quiet-if-free is the mode a HOOK wants, and it is not the same as --quiet.
# --quiet suppresses the CLAIMED report too, so a pre-push hook built on it
# refuses the push and prints nothing about why - the user is left with a bare
# non-zero exit. --quiet-if-free says nothing on the common answer (free) and
# prints the full report on the two that need acting on.
#
# A clean fast-forward is NOT permission. That is what a collision looks like
# from the inside, which is why "it merged fine" is not evidence of anything.
# Neither is a --force-with-lease that goes through, and a lease REJECTION is
# not the collision alarm: it reads as "stale info", names nobody, and does not
# fire at all once an intervening fetch has refreshed the tracking ref.
#
# Exit codes are the contract:
#   0  free            - no remote branch, no lease, or every commit is yours
#   1  CLAIMED         - another session holds the lease, or another author has
#                        pushed commits
#   2  could not tell  - no network, bad args, not a git repo, unreadable lease
#
# 2 is deliberately NOT folded into either 0 or 1. "I could not reach the
# remote" is not "nobody is there" - the same mistake as `|| true` on a grep, or
# a scan that cannot run reading as clean. A caller that treats 2 as free has
# reintroduced the bug this script exists to prevent.
# =============================================================================
set -uo pipefail

# Every value flag rejects a missing value rather than silently swallowing the
# next flag as its argument: `--me --quiet` must not set ME=--quiet.
#
# A function rather than `[ A ] && [ B ] || { fail; }`. That idiom reads as
# if-then-else and is not one (SC2015), and this repo's CI runs shellcheck over
# every script here. (Do not let a comment line BEGIN with the word shellcheck
# followed by a period - the linter reads that as a malformed directive and
# refuses to parse the rest of the file.)
need_value() { # $1 flag name, $2 candidate value
  if [ -z "$2" ] || [ "${2#-}" != "$2" ]; then
    echo "$1 needs a value" >&2
    exit 2
  fi
}

QUIET=0
QUIET_IF_FREE=0
BRANCH=""
MODE="check"
ME=""
HARNESS="unknown"
NOW=""
TTL_H=4
while [ "$#" -gt 0 ]; do
  case "$1" in
    --quiet) QUIET=1 ;;
    --quiet-if-free) QUIET_IF_FREE=1 ;;
    --acquire) MODE="acquire" ;;
    --release) MODE="release" ;;
    --me)      need_value --me      "${2:-}"; ME="$2";      shift ;;
    --harness) need_value --harness "${2:-}"; HARNESS="$2"; shift ;;
    --now)     need_value --now     "${2:-}"; NOW="$2";     shift ;;
    --ttl)     need_value --ttl     "${2:-}"; TTL_H="$2";   shift ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *)
      if [ -z "$BRANCH" ]; then
        BRANCH="$1"
      else
        echo "too many arguments" >&2; exit 2
      fi
      ;;
  esac
  shift
done

# The clock is injectable so TTL expiry is testable without sleeping. Default to
# real time; a caller that passes --now owns its correctness.
[ -n "$NOW" ] || NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
case "$TTL_H" in
  ''|*[!0-9]*) echo "--ttl must be a whole number of hours" >&2; exit 2 ;;
esac
# Bounded, and bounded HERE too because this value is what gets stamped into the
# lease ref: an unbounded --ttl is how a wrapping marker would be written in the
# first place. Length before value - see lease_read for why that order matters.
if [ "${#TTL_H}" -gt 5 ] || [ "$TTL_H" -lt 1 ] || [ "$TTL_H" -gt 8760 ]; then
  echo "--ttl must be between 1 and 8760 hours" >&2; exit 2
fi

say() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
# sayf: chatter that only ever appears on a FREE verdict. Suppressed by
# --quiet-if-free as well as --quiet. Every free-path message goes through this
# and every CLAIMED-path message through say(), which is what makes "silent when
# free, loud when not" a property of the call sites rather than a promise.
sayf() { [ "$QUIET" -eq 1 ] || [ "$QUIET_IF_FREE" -eq 1 ] || printf '%s\n' "$*"; }

[ -n "$BRANCH" ] || { echo "usage: claim-branch.sh <branch> [--quiet|--quiet-if-free]" >&2; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repository" >&2; exit 2; }

LEASE_REF="refs/claims/$BRANCH"

# --- lease ------------------------------------------------------------------
#
# NOTE ON ORDERING: --now is validated below, immediately after epoch_of is
# defined and BEFORE any path that can return free. Validating it lazily (only
# when a lease turns out to exist) means a branch with no lease answers "free"
# while holding a clock nobody could parse - could-not-tell folded into free,
# through the side door.

# epoch_of <iso8601-utc> -> epoch on stdout, or non-zero. Shape-valid input can
# still be calendar-invalid (2026-99-99T00:00:00Z), which must land as UNKNOWN
# rather than as a free verdict, so the caller checks the exit status.
#
# perl, not awk: the read side below needs capture groups and BSD awk on macOS
# has no 3-argument match().
epoch_of() {
  ISO="$1" perl -e '
    use strict; use warnings; use Time::Local qw(timegm);
    my $v = $ENV{ISO} // "";
    exit 1 unless $v =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$/;
    my ($y,$mo,$d,$h,$mi,$s) = ($1,$2,$3,$4,$5,$6);
    exit 1 if $mo < 1 || $mo > 12 || $d < 1 || $d > 31 || $h > 23 || $mi > 59 || $s > 60;
    my $e = eval { timegm($s, $mi, $h, $d, $mo - 1, $y) };
    exit 1 if $@ || !defined $e;
    print "$e\n";
  '
}

# A MISSING perl must be reported as a missing tool, not as a bad timestamp.
# Without this, epoch_of fails for want of an interpreter, the caller below
# blames "$NOW", and the operator is told to fix a value that is already
# correct. The exit code would be right (2, could-not-tell) and the instruction
# wrong, which is the worse half: an error message is an instruction, and this
# one sends you to fix the one thing that is not broken.
#
# Probing `perl -MTime::Local` rather than `command -v perl`, because the module
# is the actual dependency - a perl without it fails in exactly the same way,
# and the probe is what makes this testable with a stub on PATH.
perl -MTime::Local -e 'exit 0' >/dev/null 2>&1 || {
  echo "claim-branch.sh needs perl with Time::Local to read timestamps, and could not run it." >&2
  echo "This is a missing tool, not a bad --now value. Install perl, or run this from a shell that has it." >&2
  exit 2
}

epoch_of "$NOW" >/dev/null || { echo "--now '$NOW' is not valid ISO-8601 UTC (YYYY-MM-DDTHH:MM:SSZ)" >&2; exit 2; }

# --- per-worktree session identity ------------------------------------------
#
# session_id_path -> where THIS worktree records the session holding its lease.
#
# --absolute-git-dir, NEVER --git-common-dir. In a linked worktree the two
# differ:
#   --absolute-git-dir  <repo>/.git/worktrees/<name>   per-worktree
#   --git-common-dir    <repo>/.git                    shared by every worktree
# Using the common dir would put one id where every worktree reads it, so two
# sessions would answer MINE to each other's leases - exactly the defect this
# whole file exists to prevent, reintroduced by a one-flag mistake. And
# --absolute-git-dir rather than --git-dir because the latter can return a
# RELATIVE ".git", which would resolve against whatever cwd the caller has.
session_id_path() {
  local d
  d="$(git rev-parse --absolute-git-dir 2>/dev/null)" || return 1
  [ -n "$d" ] || return 1
  printf '%s/claim-session-id\n' "$d"
}

# Prints the recorded id, or nothing. Never fails the caller: an unreadable or
# absent file means "no identity", which leaves a live lease reading HELD.
session_id_read() {
  local f
  f="$(session_id_path)" || return 0
  [ -f "$f" ] || return 0
  # First line only, whitespace squeezed - a stray newline or CR must not become
  # part of the id and silently stop it matching the lease.
  head -1 < "$f" 2>/dev/null | tr -d '[:space:]'
}

session_id_write() {
  local f
  f="$(session_id_path)" || return 1
  printf '%s\n' "$1" > "$f" 2>/dev/null || return 1
}

session_id_clear() {
  local f
  f="$(session_id_path)" || return 0
  rm -f "$f" 2>/dev/null || true
}

# lease_object_is_inert <sha> -> 0 only if <sha> is a COMMIT, over the empty
# tree, with no parents. Anything else - including any git call that fails - is
# non-zero.
#
# This gates a PROJECT_SKIP_VERIFY bypass, so it has to fail CLOSED on every
# path. An earlier version compared `rev-parse <sha>^{tree}` against
# `hash-object -t tree /dev/null` inline and treated silent output as "no
# parents". Two holes: it never established the object was a commit at all (a
# raw empty TREE peels to itself and has no ^@ output, so it would have passed),
# and if hash-object itself failed BOTH sides were empty, compared equal, and
# the bypass was set - unknown resolving to the permissive answer.
lease_object_is_inert() {
  local ty tree empty parents
  ty="$(git cat-file -t "$1" 2>/dev/null)" || return 1
  [ "$ty" = "commit" ] || return 1

  tree="$(git rev-parse --verify --quiet "$1^{tree}" 2>/dev/null)" || return 1
  [ -n "$tree" ] || return 1

  empty="$(git hash-object -t tree /dev/null 2>/dev/null)" || return 1
  [ -n "$empty" ] || return 1
  [ "$tree" = "$empty" ] || return 1

  # ^@ lists a commit's parents and prints NOTHING for a parentless one. Not
  # `rev-list --parents -n1 | cut -d" " -f2-`: cut with no delimiter present
  # returns the WHOLE line, so a parentless commit reads as HAVING parents.
  # No `|| true` here: rev-parse <sha>^@ exits 0 for a parentless commit (empty
  # output) AND 0 for one with parents, and 128 only when the object is not a
  # commit - so the failure this would swallow is a real one, and swallowing it
  # would let the bypass through on an object never shown to be parentless.
  parents="$(git rev-parse "$1^@" 2>/dev/null)" || return 1
  [ -z "$parents" ] || return 1
  return 0
}

lease_marker() { # $1 session  $2 harness  $3 iso  $4 ttl-hours
  printf 'CLAIM harness=%s session=%s at=%s ttl=%sh\n' "$2" "$1" "$3" "$4"
}

# lease_read -> prints "<STATE>|<session>|<at>|<sha>"; returns 0 always except
# on could-not-tell, which returns 2. STATE is one of:
#   NONE     no lease ref on the remote
#   MINE     held by --me, still inside its TTL
#   HELD     held by another session, still inside its TTL
#   EXPIRED  a marker whose TTL has passed (holder is reported anyway)
# An unparseable marker is could-not-tell, NOT NONE. Something put that ref
# there; "I cannot read it" is not "nobody is there".
lease_read() {
  local rc=0 line sha body
  line="$(git ls-remote --exit-code origin "$LEASE_REF" 2>/dev/null)" || rc=$?
  case "$rc" in
    0) : ;;
    2) printf 'NONE|||\n'; return 0 ;;
    *) echo "could not reach origin to read the lease (git ls-remote exit $rc)" >&2; return 2 ;;
  esac
  sha="${line%%$'\t'*}"

  # READ BY SHA, NEVER THROUGH A SHARED REF NAME.
  #
  # refs/* is shared by every worktree of a repo: a ref written in a linked
  # worktree is immediately visible in the main checkout and vice versa. With
  # one fixed scratch ref name, session A checking branch X and session B
  # checking branch Y both write it - A fetches X's lease, B overwrites with
  # Y's, then A's read returns Y's session and ttl. A then judges X by Y's
  # marker and can answer MINE or EXPIRED for a branch that is genuinely HELD,
  # which is the one answer this script must never get wrong. $$ makes the
  # destination per-process.
  #
  # Named refs/claim-lease-read-$$ and not refs/claim-lease-read/$$: a directory
  # cannot be created where a loose ref file already exists, so the child form
  # would fail to lock in any checkout that had ever written the parent name.
  local tmpref="refs/claim-lease-read-$$"
  if ! git fetch --quiet --no-tags origin "+$LEASE_REF:$tmpref" 2>/dev/null; then
    echo "could not fetch the lease ref $LEASE_REF" >&2
    return 2
  fi
  # JUDGE WHAT WE JUST FETCHED, not the sha ls-remote returned a moment ago. The
  # lease can be taken over between the two calls, and the branch-history path
  # below already settles the same question the same way.
  #
  # Reading the object by the ls-remote sha would NOT fail safely: lease_object
  # builds the lease commit LOCALLY with commit-tree before pushing it, so a
  # session's own lease object stays in its object database forever. `git log`
  # on it succeeds long after another session has taken the ref, and the verdict
  # comes back MINE on a branch somebody else now holds.
  local fetched
  if ! fetched="$(git rev-parse --verify --quiet "$tmpref")" || [ -z "$fetched" ]; then
    git update-ref -d "$tmpref" 2>/dev/null || true
    echo "could not resolve the fetched lease ref for $BRANCH" >&2
    return 2
  fi
  sha="$fetched"
  if ! body="$(git log -1 --format='%B' "$sha" 2>/dev/null)"; then
    git update-ref -d "$tmpref" 2>/dev/null || true
    echo "could not read the lease commit for $BRANCH" >&2
    return 2
  fi
  git update-ref -d "$tmpref" 2>/dev/null || true

  local session at ttl
  session="$(printf '%s' "$body" | perl -ne 'print "$1" and last if /\bsession=(\S+)/')"
  at="$(printf '%s' "$body"      | perl -ne 'print "$1" and last if /\bat=(\S+)/')"
  ttl="$(printf '%s' "$body"     | perl -ne 'print "$1" and last if /\bttl=(\d+)h/')"
  if [ -z "$session" ] || [ -z "$at" ] || [ -z "$ttl" ]; then
    echo "lease ref $LEASE_REF exists but its marker is unreadable - refusing to call that free" >&2
    return 2
  fi
  # An out-of-range ttl is could-not-tell, NOT expired. Expiry is
  # `now >= at + ttl*3600` in shell arithmetic, which is signed 64-bit and
  # WRAPS: ttl=9999999999999999h yields a large negative deadline, every lease
  # compares as past it, and a live lease reads EXPIRED and then free.
  #
  # The LENGTH test runs first and is not redundant: `[ "$x" -gt N ]` evaluates
  # the string as a 64-bit integer, so a long enough digit string wraps inside
  # the very comparison meant to catch it and comes out looking small.
  if [ "${#ttl}" -gt 5 ] || [ "$ttl" -lt 1 ] || [ "$ttl" -gt 8760 ]; then
    echo "lease ref $LEASE_REF carries an implausible ttl (${ttl}h) - refusing to call that free" >&2
    return 2
  fi

  local at_e now_e
  at_e="$(epoch_of "$at")"   || { echo "lease timestamp '$at' is not valid ISO-8601 UTC" >&2; return 2; }
  now_e="$(epoch_of "$NOW")" || { echo "--now '$NOW' is not valid ISO-8601 UTC" >&2; return 2; }

  if [ "$now_e" -ge "$((at_e + ttl * 3600))" ]; then
    printf 'EXPIRED|%s|%s|%s\n' "$session" "$at" "$sha"
  elif [ -n "$ME" ] && [ "$session" = "$ME" ]; then
    printf 'MINE|%s|%s|%s\n' "$session" "$at" "$sha"
  else
    printf 'HELD|%s|%s|%s\n' "$session" "$at" "$sha"
  fi
}

# lease_object -> writes the lease commit locally, prints its sha.
# A parentless commit over the EMPTY tree: the lease carries no content, only a
# message, so it needs no history and costs one object. The identity is set
# explicitly rather than read from git config - depending on user.email here
# would reintroduce the very coupling the lease exists to remove.
lease_object() {
  local empty_tree
  empty_tree="$(git hash-object -t tree /dev/null 2>/dev/null)" || return 1
  GIT_AUTHOR_NAME='claim-branch' GIT_AUTHOR_EMAIL='claim-branch@local' \
  GIT_COMMITTER_NAME='claim-branch' GIT_COMMITTER_EMAIL='claim-branch@local' \
  GIT_AUTHOR_DATE="$NOW" GIT_COMMITTER_DATE="$NOW" \
    git commit-tree "$empty_tree" -m "$(lease_marker "$ME" "$HARNESS" "$NOW" "$TTL_H")" 2>/dev/null
}

report_held() { # $1 session  $2 at
  say "CLAIMED: '$BRANCH' is leased by another session"
  say ""
  say "    session $1  since $2"
  say ""
  say "  you are: ${ME:-<no --me given>}"
  say ""
  say "  Do not work this branch. Either pick a different one, or coordinate -"
  say "  that session may still be mid-task. The lease expires on its own."
}

# --- acquire / release ------------------------------------------------------

if [ "$MODE" != "check" ]; then
  [ -n "$ME" ] || { echo "--$MODE needs --me <session-id>: the whole point is an identity git config cannot supply" >&2; exit 2; }

  state_line="$(lease_read)" || exit 2
  STATE="${state_line%%|*}"
  rest="${state_line#*|}"
  HOLDER="${rest%%|*}"
  rest="${rest#*|}"
  HELD_AT="${rest%%|*}"
  OLD_SHA="${rest#*|}"

  if [ "$MODE" = "release" ]; then
    case "$STATE" in
      NONE) sayf "release: no lease on '$BRANCH'"; exit 0 ;;
      MINE|EXPIRED)
        if [ "$STATE" = "EXPIRED" ] && [ "$HOLDER" != "$ME" ]; then
          say "refusing to release: '$BRANCH' is held by $HOLDER, not you"
          exit 1
        fi
        # CAS on the sha we just read, so a lease renewed between the read and
        # this push is not deleted out from under its holder.
        if git push --quiet --force-with-lease="$LEASE_REF:$OLD_SHA" origin ":$LEASE_REF" >/dev/null 2>&1; then
          session_id_clear
          sayf "released the lease on '$BRANCH'"
          exit 0
        fi
        echo "could not release the lease on '$BRANCH' (it may have changed underneath)" >&2
        exit 2
        ;;
      HELD)
        say "refusing to release: '$BRANCH' is held by $HOLDER, not you"
        exit 1
        ;;
    esac
  fi

  # acquire
  case "$STATE" in
    MINE)
      # Re-acquiring your own live lease is idempotent, and it also REPAIRS a
      # missing id file - a session that lost it (new worktree, manual delete)
      # would otherwise be self-blocked with no way back short of the ttl.
      if ! session_id_write "$ME"; then
        echo "warning: could not record the session id, so your own pushes may" >&2
        echo "         still be refused; check that $(session_id_path 2>/dev/null) is writable" >&2
      fi
      sayf "lease on '$BRANCH' is already yours (session $ME)"; exit 0 ;;
    HELD) report_held "$HOLDER" "$HELD_AT"; exit 1 ;;
  esac

  LEASE_SHA="$(lease_object)" || { echo "could not build the lease object" >&2; exit 2; }

  # NONE -> expect the ref to be absent (empty expected value). EXPIRED -> CAS
  # on the exact sha we read, so a takeover cannot clobber a lease that was
  # renewed in the meantime. Both are atomic create-or-fail against the remote.
  if [ "$STATE" = "EXPIRED" ]; then EXPECT="$OLD_SHA"; else EXPECT=""; fi

  # THE GREEN GATE MUST NOT JUDGE A LEASE REF.
  #
  # .githooks/pre-push refuses any ref whose tree has no green marker. A lease
  # commit's tree is the EMPTY tree, which nothing ever verifies, so without
  # this the gate blocks every --acquire in a configured repo:
  #
  #   BLOCKED: pushing <sha> -> refs/claims/<branch> with no green verification.
  #
  # That is a false positive of the same family as the automation-author one
  # below: the gate exists to stop unverified CODE reaching the remote, and a
  # claims ref carries none. Hermetic fixtures do not catch it, because they
  # have no .githooks installed - the feature is green in the suite and unusable
  # in a real repo.
  #
  # The bypass is scoped to THIS push and is earned rather than asserted: refuse
  # to set it unless the object really is a parentless commit over the empty
  # tree. A bypass that cannot verify what it is waving through is how a safety
  # control rots. PROJECT_SKIP_VERIFY only lifts the green layer; the
  # branch-claim layer is a separate bypass and stays on, which is why the two
  # are kept independent.
  if ! lease_object_is_inert "$LEASE_SHA"; then
    echo "refusing to push a lease object that is not a parentless empty-tree commit" >&2
    exit 2
  fi
  if PROJECT_SKIP_VERIFY=1 git push --quiet --force-with-lease="$LEASE_REF:$EXPECT" origin "$LEASE_SHA:$LEASE_REF" >/dev/null 2>&1; then
    # Record who this worktree is, so the pre-push hook - which passes no --me,
    # because it has no session id to pass - can tell this session's own push
    # from an intruder's. A write failure is reported but does NOT fail the
    # acquire: the lease is already on the remote at this point, and exiting
    # non-zero would say "you did not get it" about a lease you did get. The
    # cost of the missing file is a self-blocked push, which is loud and
    # recoverable; the cost of a wrong exit code is a session that re-acquires
    # over its own live lease.
    if ! session_id_write "$ME"; then
      echo "warning: acquired the lease but could not record the session id;" >&2
      echo "         your own pushes may be refused until you re-run --acquire" >&2
    fi
    sayf "acquired the lease on '$BRANCH' (session $ME, ttl ${TTL_H}h)"
    exit 0
  fi

  # The push was refused. git says "stale info", which is indistinguishable from
  # an ordinary out-of-date ref and names nobody - so re-read the ref and report
  # who actually holds it rather than echoing that.
  after="$(lease_read)" || exit 2
  case "${after%%|*}" in
    HELD|EXPIRED)
      rest="${after#*|}"
      report_held "${rest%%|*}" "$(rest2="${rest#*|}"; printf '%s' "${rest2%%|*}")"
      exit 1
      ;;
    MINE)
      if ! session_id_write "$ME"; then
        echo "warning: could not record the session id, so your own pushes may" >&2
        echo "         still be refused; check that $(session_id_path 2>/dev/null) is writable" >&2
      fi
      sayf "lease on '$BRANCH' is already yours (session $ME)"; exit 0 ;;
    *)
      echo "the lease push was refused but the ref reads as absent - refusing to guess" >&2
      exit 2
      ;;
  esac
fi

# --- check: signal 1, the lease --------------------------------------------
# Runs FIRST because it is the signal that can see a concurrent session.
#
# IDENTITY ON THE CHECK PATH, and why it is not just "--me or nothing".
# .githooks/pre-push runs `claim-branch.sh <branch> --quiet-if-free` and has no
# session id to pass - there is no ambient one. With no identity, a live lease
# has to read as HELD, and that means acquiring a lease on YOUR OWN branch
# blocks YOUR OWN next push, with the report naming your own session as
# "another session". That is a guard firing predictably on work the operator
# dispatched themselves, which makes its bypass permanently required - and a
# bypass that is always required is a bypass nobody reads.
#
# So the check path resolves an identity when no --me is given:
#
#     --me  >  the per-worktree session-id file  >  $PROJECT_SESSION_ID
#
# THE FILE OUTRANKS THE ENV VAR, and that order is the safety property rather
# than a preference. The env var is the source that CANNOT be made per-session;
# the file is per-worktree by construction. If the env var won, a single
# machine-wide value would silently suppress the file in every worktree and hand
# every session one identity, which is free-on-a-held-branch. Letting the unsafe
# source override the safe one is backwards, so it does not. --me still wins: it
# is explicit, per-invocation, and cannot be set globally by accident.
#
# DO NOT SET $PROJECT_SESSION_ID GLOBALLY. A harness settings file's env block
# is static and machine-wide, so every concurrent session would carry the SAME
# id and each would read the others' leases as MINE - free on a held branch, the
# one answer this must never give. A SessionStart hook cannot supply it either;
# it runs in its own subprocess and its exports never reach the shells that
# later run git push. The worktree is the real session boundary, which is why
# --acquire records the id in this worktree's OWN git dir and --release removes
# it: the file is present exactly while this worktree holds a lease.
#
# A STALE file (the lease expired, or another session took it over) simply fails
# to match the lease's session, so the verdict is HELD. The failure direction is
# the safe one by construction, not by care.
#
# Deliberately CHECK-ONLY. --acquire and --release keep requiring an explicit
# --me: taking a lease is a deliberate act that should name itself. The fallback
# exists for the one caller that provably cannot pass a flag.
[ -n "$ME" ] || ME="$(session_id_read)"
[ -n "$ME" ] || ME="${PROJECT_SESSION_ID:-}"
check_state="$(lease_read)" || exit 2
case "${check_state%%|*}" in
  HELD)
    check_rest="${check_state#*|}"
    check_holder="${check_rest%%|*}"
    check_rest="${check_rest#*|}"
    report_held "$check_holder" "${check_rest%%|*}"
    exit 1
    ;;
esac

# --- check: signal 2, author email ------------------------------------------
# Who am I? The email git will actually stamp on a commit is the only identity
# that distinguishes authors here.
ME_NAME="$(git config user.name 2>/dev/null || true)"
ME_EMAIL="$(git config user.email 2>/dev/null || true)"
[ -n "$ME_EMAIL" ] || {
  echo "git user.email is unset - cannot tell your commits from anyone else's" >&2
  exit 2
}

# The base branch to scope the range against. Do not hardcode 'main': a repo
# started from this template may use master, trunk, or anything else. Ask the
# remote what its HEAD points at, and fall back only if it has not been set.
BASE=""
if ref="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)"; then
  BASE="${ref#refs/remotes/}"
fi
if [ -z "$BASE" ]; then
  for candidate in origin/main origin/master; do
    if git rev-parse --verify --quiet "$candidate" >/dev/null; then BASE="$candidate"; break; fi
  done
fi
[ -n "$BASE" ] || {
  echo "cannot determine the default branch - run 'git remote set-head origin -a'" >&2
  exit 2
}

# Does the branch exist on the remote? ls-remote exits 0 with EMPTY output when
# the ref is absent and non-zero when it could not ask. Those are different
# answers and must never share a branch of this `case`.
rc=0
remote_line="$(git ls-remote --exit-code --heads origin "$BRANCH" 2>/dev/null)" || rc=$?
case "$rc" in
  0) : ;;                                                # exists
  2) sayf "free: no remote branch '$BRANCH'"; exit 0 ;;   # --exit-code: no match
  *) echo "could not reach origin (git ls-remote exit $rc)" >&2; exit 2 ;;
esac

REMOTE_SHA="${remote_line%%$'\t'*}"

# Fetch the branch's FULL history, not a shallow slice. A shallow `--depth=N` is
# unsafe here: a branch with N recent commits of yours can still carry an OLDER
# commit by someone else, and the shallow fetch hides it while `git log` still
# succeeds. That reports 'free' on a claimed branch, which is the single answer
# this script must never get wrong. Correctness beats the few hundred ms.
if ! git fetch --quiet --no-tags origin "$BRANCH" 2>/dev/null; then
  echo "could not fetch origin/$BRANCH" >&2
  exit 2
fi

# Attribute against what was JUST fetched, not the SHA read from ls-remote
# earlier. The branch can advance between the two calls, and judging a stale SHA
# would miss exactly the commit someone else has only now pushed.
if ! FETCHED_SHA="$(git rev-parse FETCH_HEAD 2>/dev/null)"; then
  echo "could not resolve FETCH_HEAD for $BRANCH" >&2
  exit 2
fi
# Held rather than printed here: under --quiet-if-free the verdict is not known
# yet, and this note must not break the "silent when free" contract. It is
# emitted below on whichever path we actually take.
MOVED_NOTE=""
if [ "$FETCHED_SHA" != "$REMOTE_SHA" ]; then
  MOVED_NOTE="note: '$BRANCH' moved between discovery and fetch; judging the newer $FETCHED_SHA"
  sayf "$MOVED_NOTE"
fi

# Commits on the branch that are not on the base branch - the work someone has
# already done here. Scope against the base rather than your local HEAD: you may
# not have this branch at all yet. The base must be present for the range to
# mean anything; an absent one would make every commit look novel.
if ! git rev-parse --verify --quiet "$BASE" >/dev/null; then
  echo "$BASE not in this checkout - cannot scope the range" >&2
  exit 2
fi
if ! authors="$(git log --format='%ae|%an|%h|%s' "$BASE..$FETCHED_SHA" 2>/dev/null)"; then
  echo "could not read history for $BRANCH" >&2
  exit 2
fi

if [ -z "$authors" ]; then
  sayf "free: '$BRANCH' exists but has no commits beyond $BASE"
  exit 0
fi

# github-actions[bot] is AUTOMATION, not a session.
#
# A workflow that pushes to a branch (regenerated baselines, a formatting pass,
# a version bump) commits under this identity. Counting it as "someone else"
# makes every branch it touches refuse every later human push - permanently, not
# once. That is a false positive, and a guard that cries wolf on work the
# operator dispatched themselves is a guard people learn to bypass.
#
# Matched as EXACT addresses, never a substring of "bot". A substring rule would
# silently ignore a real person whose address happens to contain it, and for a
# collision detector that is the unsafe direction. Both spellings below are
# GitHub-controlled noreply addresses no human can register.
#
# grep -qxF, not a regex: the literal [ ] in the address are a CHARACTER CLASS
# to grep. That is not hypothetical - the first draft of this exemption's own
# test used plain grep, never matched the literal, and asserted nothing at all.
#
# Deliberately ONLY this bot. Dependency bots, review bots and release bots also
# push branches and their collision semantics have not been thought through;
# leaving them counted is the conservative default.
#
# KNOWN LIMIT, stated rather than hidden. Commit author email is unsigned local
# metadata, so a session that DELIBERATELY set this address would be ignored.
# This is not an authentication control: it detects ACCIDENTAL concurrency
# between sessions carrying different configured identities, and a colliding
# session could already hide by using your address, which by default it has.
BOT_EMAILS='41898282+github-actions[bot]@users.noreply.github.com
github-actions[bot]@users.noreply.github.com'

is_bot() { printf '%s\n' "$BOT_EMAILS" | grep -qxF "$1"; }

# awk, not `grep -c . || true`. This file spends its header saying that a check
# which cannot run must not read as a clean one, and `|| true` on a grep is the
# canonical way to break that: it maps grep's exit 2 (error) onto the same
# result as its exit 1 (no match). awk prints a count and needs no rescue.
count_lines() { printf '%s\n' "$1" | awk 'NF { n++ } END { print n + 0 }'; }

bot_lines=""
others=""
mine=""
while IFS= read -r line; do
  [ -z "$line" ] && continue
  addr="${line%%|*}"
  if [ "$addr" = "$ME_EMAIL" ]; then
    mine="${mine}${line}"$'\n'
  elif is_bot "$addr"; then
    bot_lines="${bot_lines}${line}"$'\n'
  else
    others="${others}${line}"$'\n'
  fi
done <<AUTHORS_EOF
$authors
AUTHORS_EOF
others="${others%$'\n'}"
bot_lines="${bot_lines%$'\n'}"
mine="${mine%$'\n'}"

if [ -z "$others" ]; then
  mine_n=$(count_lines "$mine")
  bot_n=$(count_lines "$bot_lines")
  if [ "$bot_n" -gt 0 ]; then
    # Say it out loud. Ignoring the bot is a judgement this script makes on the
    # operator's behalf, and a judgement they cannot see is indistinguishable
    # from a bug.
    sayf "free: '$BRANCH' has $mine_n commit(s) of yours, plus $bot_n from github-actions[bot]"
    sayf "      (automation, not another session - ignored deliberately)"
  else
    sayf "free: '$BRANCH' has $mine_n commit(s), all yours ($ME_EMAIL)"
  fi
  exit 0
fi

# The note was withheld above under --quiet-if-free; this is a CLAIMED verdict,
# so it belongs in the report.
if [ "$QUIET_IF_FREE" -eq 1 ] && [ -n "$MOVED_NOTE" ]; then
  say "$MOVED_NOTE"
fi
say "CLAIMED: '$BRANCH' carries commits by someone else"
say ""
printf '%s\n' "$others" | awk -F'|' '{printf "    %s  %s  <%s>  %s\n", $3, $2, $1, $4}' \
  | while IFS= read -r l; do say "$l"; done
say ""
say "  you are: $ME_NAME <$ME_EMAIL>"
say ""
say "  Do not push over it. Either pick a different branch, or coordinate -"
say "  another session may still be mid-task. If you have already fetched it,"
say "  'git log origin/$BRANCH' shows what they have done."
exit 1
