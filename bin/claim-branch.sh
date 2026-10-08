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
#   bin/claim-branch.sh --sweep                   # delete RELEASED/EXPIRED leases
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
# 2. LEASE - a ref refs/heads/claims/<branch> on the remote whose commit
#    message carries session, harness, timestamp and TTL. Identity comes from
#    --me, an explicit session id, never inferred from git config. Acquiring is
#      git push --force-with-lease=<ref>:<expected> origin <sha>:<ref>
#    with <expected> empty for a create and the read sha for a takeover.
#
#    WHY UNDER refs/heads/. Leases used to live at refs/claims/<branch>. A
#    hosted agent session's git proxy (measured on Claude Code cloud sessions)
#    answers 403 to any push outside refs/heads/* and to ANY ref deletion, while
#    allowing refs/heads/* to be created and force-updated. So a session there
#    could neither take a lease nor release one. Hence:
#      - --acquire writes refs/heads/claims/<branch>, and nothing else.
#      - --release does not delete. It force-updates the ref (CAS on the sha it
#        read) to an inert commit carrying the RELEASED marker,
#          RELEASE harness=<h> session=<s> at=<iso>
#        and every reader treats that as free. Deletion is only the fallback,
#        for a remote that refuses the update but allows the delete.
#      - --sweep deletes RELEASED and EXPIRED leases, from wherever deletion
#        works. It never deletes a live lease or one it cannot read.
#      - A <branch> starting claims/ is refused (2), because that is the lease
#        namespace. The one exception is the lease push itself: .githooks/
#        pre-push checks every refs/heads/* ref it sends, so it asks about
#        "claims/<b>", and check mode passes that only when
#        PROJECT_CLAIM_LEASE_PUSH names an inert lease commit.
#      - A ref still at the OLD refs/claims/<branch> (a copy of this template
#        from before the move, with a session that ran the old script) is NOT
#        judged: every mode reports could-not-tell and names the command that
#        removes it. Reading it as free could hand a held branch to a second
#        session, and carrying a reader for a format no new copy ever writes
#        would be permanent code for a one-time transition. The REVERSE is not
#        covered and cannot be from here: an OLD copy reads only refs/claims/,
#        so it sees a lease under refs/heads/claims/ as free and can take a
#        second one. Upgrading is a cut-over (.claude/commands/worktree.md).
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
# flag. The window the flag actually closes is EARLIER: between lease_read_ref and
# the push opening its connection. A ref that moves in THAT window is advertised
# as its NEW value, so a plain --force finds the old value matching and clobbers
# a live holder. Only a lease pinned to the sha we actually read refuses. Do not
# drop the flag. (Create semantics and the CAS are properties of git refs, not
# of a namespace: the move to refs/heads/claims/ changes neither, and the
# hermetic suite exercises both there.)
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
#   2  could not tell  - no network, bad args, not a git repo, unreadable lease,
#                        or a lease left in the old refs/claims/ namespace
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
    --sweep)   MODE="sweep" ;;
    --me)     need_value --me      "${2:-}"; ME="$2";      shift ;;
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
# first place. Length before value - see lease_read_ref for why that order matters.
if [ "${#TTL_H}" -gt 5 ] || [ "$TTL_H" -lt 1 ] || [ "$TTL_H" -gt 8760 ]; then
  echo "--ttl must be between 1 and 8760 hours" >&2; exit 2
fi

# --me and --harness are stamped into the lease marker and read back by regex
# (lease_read_ref), so they are restricted to [A-Za-z0-9._:-]. Outside that set
# a value can forge another field: a space or '=' lets `--harness 'h session=x'`
# put a second session= in the body, and `--me 'a b'` is read back as session
# `a`. Inside it, one more case: the markers are found as WHOLE TOKENS
# (/\bRELEASE\b/, /\bCLAIM\b/), and perl's \b treats . : - as boundaries, so an
# id like `x-CLAIM` or `RELEASE` would make the body carry both markers. Every
# reader calls that could-not-tell and --sweep will not delete what it cannot
# read, so one such id would jam the branch until someone deleted the ref by
# hand. Refused here instead. (`RELEASED` is fine: D is a word character, so it
# does not contain the token.)
valid_id() { # $1 flag  $2 value
  case "$2" in
    ''|*[!A-Za-z0-9._:-]*)
      echo "$1 '$2' must be one or more of [A-Za-z0-9._:-]" >&2
      exit 2 ;;
  esac
  # Pure shell, no perl: a token is a maximal run of [A-Za-z0-9_], exactly what
  # \b delimits inside the allowed set. (perl is probed further down; doing this
  # with perl here would make a missing perl skip the check - fail open.)
  local tok rest="$2"
  while [ -n "$rest" ]; do
    tok="${rest%%[.:-]*}"
    case "$tok" in
      RELEASE|CLAIM)
        echo "$1 '$2' contains $tok as a whole token, which the lease marker parser" >&2
        echo "would read as a second marker. Pick an id without it." >&2
        exit 2 ;;
    esac
    [ "$tok" = "$rest" ] && break
    rest="${rest#"$tok"?}"
  done
}
[ -z "$ME" ] || valid_id --me "$ME"
valid_id --harness "$HARNESS"

say() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
# sayf: chatter that only ever appears on a FREE verdict. Suppressed by
# --quiet-if-free as well as --quiet. Every free-path message goes through this
# and every CLAIMED-path message through say(), which is what makes "silent when
# free, loud when not" a property of the call sites rather than a promise.
sayf() { [ "$QUIET" -eq 1 ] || [ "$QUIET_IF_FREE" -eq 1 ] || printf '%s\n' "$*"; }

if [ "$MODE" = "sweep" ]; then
  [ -z "$BRANCH" ] || { echo "--sweep takes no branch argument: it walks every lease ref" >&2; exit 2; }
else
  [ -n "$BRANCH" ] || { echo "usage: claim-branch.sh <branch> [--quiet|--quiet-if-free]" >&2; exit 2; }
fi
git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repository" >&2; exit 2; }

# --- the branch argument is a plain branch name -----------------------------
#
# Every lease path is built as refs/heads/claims/$BRANCH and the author check
# asks for refs/heads/$BRANCH. So `refs/heads/held` and `origin/held` are read
# as two OTHER branches, whose leases do not exist, and both answered 0 for a
# branch that was held (review finding on PR #32). A spelling that can name a
# held branch must never read as free, so the ambiguous forms are refused (2)
# with the form wanted, in every mode that takes a branch.
#
# The <remote>/ test matches only CONFIGURED remote names. A branch whose first
# segment merely looks like one (feature/x, upstream/x with no such remote) is
# an ordinary name. The cost is that a real branch named after a remote
# (origin/x as a local branch) cannot be claimed - rename it.
#
# check-ref-format --branch, and its output must equal the input: it also
# EXPANDS @{-1} and friends to some other branch, which is the same ambiguity.
want_plain_branch() { # $1 why
  echo "'$BRANCH' is not a plain branch name ($1)." >&2
  echo "Pass the branch the way 'git switch' takes it, e.g. '${2:-feature/x}'." >&2
  exit 2
}
if [ "$MODE" != "sweep" ]; then
  case "$BRANCH" in
    refs/*) want_plain_branch "it is a full ref; give the name under refs/heads/" "${BRANCH#refs/heads/}" ;;
    # git resolves heads/x, remotes/<r>/x and tags/x by trying refs/<name>, so
    # each names some other ref than the lease would be keyed on.
    heads/*|remotes/*|tags/*)
      want_plain_branch "git reads '${BRANCH%%/*}/' as refs/${BRANCH%%/*}/, a shorthand for another ref" "${BRANCH##*/}" ;;
  esac
  if ! remotes="$(git remote 2>/dev/null)"; then
    echo "could not list remotes, so cannot tell whether '$BRANCH' names a remote-tracking branch" >&2
    exit 2
  fi
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    case "$BRANCH" in
      "$r"/*) want_plain_branch "'$r' is a configured remote, so this reads as remote '$r', branch '${BRANCH#"$r"/}'" "${BRANCH#"$r"/}" ;;
    esac
  done <<REMOTES_EOF
$remotes
REMOTES_EOF
  if ! normalized="$(git check-ref-format --branch "$BRANCH" 2>/dev/null)" || [ "$normalized" != "$BRANCH" ]; then
    want_plain_branch "git does not accept it as a branch name as written"
  fi
  # `claims` itself is the directory every lease lives in: refs/heads/claims
  # cannot exist beside refs/heads/claims/<b>. (claims/<b> is handled below,
  # where the lease push's own check-mode pass-through lives.)
  if [ "$BRANCH" = "claims" ]; then
    echo "'claims' is the lease namespace's own directory (refs/heads/claims/*), not a work branch." >&2
    echo "Pick another name." >&2
    exit 2
  fi
fi

# LEASE_REF is the only lease ref this script reads, writes or releases.
# OLD_LEASE_REF is only ever probed for existence (see the header).
LEASE_REF="refs/heads/claims/$BRANCH"
OLD_LEASE_REF="refs/claims/$BRANCH"

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

# warn_if_not_on_branch <branch>
# --acquire writes the session id into THIS checkout's git dir, and the pre-push
# hook reads it from the worktree that pushes. Run from the main checkout before
# `git worktree add`, the id lands where nothing will ever push the branch, and
# the worktree's own push is later refused as an intruder ("you are: <no --me
# given>"). In the project this template came from, that happened three times
# in two days before this warning existed.
#
# WARN, never refuse: acquiring before the worktree exists is a legitimate way
# to reserve the name, and the lease on the remote is real either way. A HEAD
# that cannot be read (detached, or git failing) also warns; this is advice, so
# the cautious answer costs one extra line and nothing else.
warn_if_not_on_branch() {
  local here
  # Full ref, not --short: with a tag of the same name, --short answers
  # heads/<branch> and this would warn on the right checkout.
  here="$(git symbolic-ref --quiet HEAD 2>/dev/null)" || here=""
  [ "$here" = "refs/heads/$1" ] && return 0
  here="${here#refs/heads/}"
  echo "warning: this checkout is on '${here:-a detached or unreadable HEAD}', not '$1'." >&2
  echo "         The session id is recorded in this checkout, so a push of '$1'" >&2
  echo "         from its own worktree will be refused as another session's." >&2
  echo "         Fix: git worktree add first, then re-run --acquire from inside it," >&2
  echo "         or export PROJECT_SESSION_ID=<session-id> in the shell that pushes." >&2
  # The id left here is a smaller hazard than it was: check mode now honours it
  # only from a checkout ON the branch, so another session checking from this
  # (often shared) checkout no longer reads the lease as its own. It still
  # would if this checkout later switched to the branch. The write stays (a
  # single-clone session acquires, then switches branch in place), so name the
  # file to remove once the worktree holds the id.
  echo "         Then remove $(session_id_path 2>/dev/null || echo '<this git dir>/claim-session-id'):" >&2
  echo "         if this checkout is ever switched to '$1', it would read this lease as its own." >&2
}

lease_marker() { # $1 session  $2 harness  $3 iso  $4 ttl-hours
  printf 'CLAIM harness=%s session=%s at=%s ttl=%sh\n' "$2" "$1" "$3" "$4"
}

# release_marker <session> <harness> <iso>
# Written by --release OVER the lease ref instead of deleting it, because a
# hosted session's git proxy refuses every ref deletion. A reader treats a ref
# carrying it as FREE. It deliberately has no ttl= field and no CLAIM token, so
# the CLAIM parser cannot read it as a lease, and a body carrying BOTH tokens is
# could-not-tell.
release_marker() {
  printf 'RELEASE harness=%s session=%s at=%s\n' "$2" "$1" "$3"
}

# remote_ref_sha <ref> -> prints the sha of EXACTLY <ref> on origin, or nothing
# when it is absent; returns 2 when origin could not be asked.
#
# EXACT NAME ONLY. ls-remote matches a pattern against the TAIL of each ref, so
# asking for one ref can return others that merely end the same way. Only the
# line naming exactly <ref> counts; no such line means the ref is absent.
remote_ref_sha() {
  local rc=0 out l_sha l_ref sha=""
  out="$(git ls-remote --exit-code origin "$1" 2>/dev/null)" || rc=$?
  case "$rc" in
    0) : ;;
    2) return 0 ;;
    *) echo "could not reach origin to read $1 (git ls-remote exit $rc)" >&2; return 2 ;;
  esac
  while IFS=$'\t' read -r l_sha l_ref; do
    [ "$l_ref" = "$1" ] && sha="$l_sha"
  done <<LSR_EOF
$out
LSR_EOF
  printf '%s' "$sha"
}

# lease_read_ref <ref> -> prints "<STATE>|<session>|<at>|<sha>"; returns 0
# except on could-not-tell, which returns 2. STATE is one of:
#   NONE      no lease ref on the remote
#   RELEASED  a RELEASE marker: free, and <sha> is what a takeover CASes on
#   MINE      held by --me, still inside its TTL
#   HELD      held by another session, still inside its TTL
#   EXPIRED   a marker whose TTL has passed (holder is reported anyway)
# An unparseable marker is could-not-tell, NOT NONE. Something put that ref
# there; "I cannot read it" is not "nobody is there". So is an object that is
# not an inert lease commit: a code commit parked on refs/heads/claims/<b> is
# not a lease, whatever its message says.
lease_read_ref() {
  local ref="$1" sha body
  sha="$(remote_ref_sha "$ref")" || return 2
  [ -n "$sha" ] || { printf 'NONE|||\n'; return 0; }

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
  if ! git fetch --quiet --no-tags origin "+$ref:$tmpref" 2>/dev/null; then
    echo "could not fetch the lease ref $ref" >&2
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
    echo "could not resolve the fetched lease ref $ref" >&2
    return 2
  fi
  sha="$fetched"
  if ! body="$(git log -1 --format='%B' "$sha" 2>/dev/null)"; then
    git update-ref -d "$tmpref" 2>/dev/null || true
    echo "could not read the lease commit at $ref" >&2
    return 2
  fi
  # Inside refs/heads/ anyone can push anything, so the SHAPE is checked before
  # the message is believed: a code commit whose message happens to parse is
  # not a lease.
  if ! lease_object_is_inert "$sha"; then
    git update-ref -d "$tmpref" 2>/dev/null || true
    echo "$ref holds something that is not a lease (not a parentless empty-tree commit) - refusing to call that free" >&2
    return 2
  fi
  git update-ref -d "$tmpref" 2>/dev/null || true

  local session at ttl has_rel has_claim
  has_rel="$(printf '%s' "$body"   | perl -ne 'print "1" and last if /\bRELEASE\b/')"
  has_claim="$(printf '%s' "$body" | perl -ne 'print "1" and last if /\bCLAIM\b/')"
  if [ -n "$has_rel" ]; then
    # A RELEASE marker is free only when it is unambiguous: well-formed, and not
    # sharing a body with a CLAIM. Anything else is could-not-tell.
    if [ -n "$has_claim" ]; then
      echo "lease ref $ref carries both a RELEASE and a CLAIM marker - refusing to call that free" >&2
      return 2
    fi
    session="$(printf '%s' "$body" | perl -ne 'print "$1" and last if /\bRELEASE harness=\S+ session=(\S+) at=\S+/')"
    at="$(printf '%s' "$body"      | perl -ne 'print "$1" and last if /\bRELEASE harness=\S+ session=\S+ at=(\S+)/')"
    if [ -z "$session" ] || [ -z "$at" ]; then
      echo "lease ref $ref carries an unreadable RELEASE marker - refusing to call that free" >&2
      return 2
    fi
    printf 'RELEASED|%s|%s|%s\n' "$session" "$at" "$sha"
    return 0
  fi

  session="$(printf '%s' "$body" | perl -ne 'print "$1" and last if /\bsession=(\S+)/')"
  at="$(printf '%s' "$body"      | perl -ne 'print "$1" and last if /\bat=(\S+)/')"
  ttl="$(printf '%s' "$body"     | perl -ne 'print "$1" and last if /\bttl=(\d+)h/')"
  if [ -z "$session" ] || [ -z "$at" ] || [ -z "$ttl" ]; then
    echo "lease ref $ref exists but its marker is unreadable - refusing to call that free" >&2
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
    echo "lease ref $ref carries an implausible ttl (${ttl}h) - refusing to call that free" >&2
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

# release_object -> writes a RELEASED marker commit locally, prints its sha.
# Same shape as lease_object: parentless, empty tree, fixed identity.
release_object() {
  local empty_tree
  empty_tree="$(git hash-object -t tree /dev/null 2>/dev/null)" || return 1
  GIT_AUTHOR_NAME='claim-branch' GIT_AUTHOR_EMAIL='claim-branch@local' \
  GIT_COMMITTER_NAME='claim-branch' GIT_COMMITTER_EMAIL='claim-branch@local' \
  GIT_AUTHOR_DATE="$NOW" GIT_COMMITTER_DATE="$NOW" \
    git commit-tree "$empty_tree" -m "$(release_marker "$ME" "$HARNESS" "$NOW")" 2>/dev/null
}

# split_state <line> -> sets S_STATE S_HOLDER S_AT S_SHA from a lease_read_ref line.
split_state() {
  local rest
  S_STATE="${1%%|*}"
  rest="${1#*|}"
  S_HOLDER="${rest%%|*}"
  rest="${rest#*|}"
  S_AT="${rest%%|*}"
  S_SHA="${rest#*|}"
}

# push_lease_ref <ref> <expected-old-sha-or-empty> <new-sha-or-empty>
# One compare-and-swap push to a lease ref; an empty <new-sha> deletes it.
#
# THE PUSH GATE MUST NOT JUDGE A LEASE REF. .githooks/pre-push has two layers,
# and a lease push trips both:
#   - the green layer refuses any ref whose tree has no green marker, and a
#     lease's tree is the EMPTY tree, which nothing ever verifies;
#   - the branch-claim layer checks every refs/heads/* ref it sends, so it asks
#     this script about "claims/<branch>" - see the claims/ guard below.
# Hermetic fixtures with no hook installed cannot see either: the feature is
# green in the suite and unusable in a real repo.
#
# Both variables are scoped to THIS push, never exported:
#   PROJECT_SKIP_VERIFY=1     lifts the green layer for the lease's empty tree.
#   PROJECT_CLAIM_LEASE_PUSH  lets the claim layer pass "claims/<branch>". It
#                             names the inert object being written (or, for a
#                             deletion, removed), so a bare "1" left exported
#                             in a shell opens nothing.
# Each is earned rather than asserted: every caller checks the object really is
# a parentless commit over the empty tree before pushing it. A bypass that
# cannot verify what it is waving through is how a safety control rots.
push_lease_ref() {
  local ref="$1" expect="$2" new="$3" vouch
  vouch="${new:-$expect}"
  PROJECT_SKIP_VERIFY=1 PROJECT_CLAIM_LEASE_PUSH="$vouch" \
    git push --quiet --force-with-lease="$ref:$expect" origin "$new:$ref" >/dev/null 2>&1
}

# release_ref <sha-we-read> -> 0 once the lease ref no longer holds a live lease.
# The ref is force-updated to a RELEASED marker first (CAS on the sha we read,
# so a lease renewed between the read and this push is not overwritten), and
# deleted only if that fails: a hosted session cannot delete, and the design
# has to work there. Some remotes refuse the update and allow the delete (a
# ruleset that blocks force-pushes), which is what the fallback is for.
release_ref() {
  local old="$1" rel
  rel="$(release_object)" || return 1
  lease_object_is_inert "$rel" || return 1
  push_lease_ref "$LEASE_REF" "$old" "$rel" && return 0
  push_lease_ref "$LEASE_REF" "$old" "" && return 0
  return 1
}

# lease_df_clash -> prints, one per line, every lease ref on origin that a ref
# at $LEASE_REF would clash with as directory vs file: one ABOVE it (a lease on
# a prefix of $BRANCH) or BELOW it (a lease on $BRANCH/<anything>). Non-zero
# when origin could not be listed. Used only to EXPLAIN a refused push; the
# verdict (2) does not depend on it.
lease_df_clash() {
  local listing _l_sha l_ref
  listing="$(git ls-remote origin 'refs/heads/claims/*' 2>/dev/null)" || return 1
  while IFS=$'\t' read -r _l_sha l_ref; do
    [ -n "${l_ref:-}" ] || continue
    case "$LEASE_REF" in
      "$l_ref"/*) printf '%s\n' "$l_ref" ;;
    esac
    case "$l_ref" in
      "$LEASE_REF"/*) printf '%s\n' "$l_ref" ;;
    esac
  done <<DF_EOF
$listing
DF_EOF
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
  # Set only in check mode with no --me, when this checkout is not on the
  # branch (see OFF_BRANCH_ID below).
  if [ -n "${OFF_BRANCH_ID:-}" ] && [ "$OFF_BRANCH_ID" = "$1" ]; then
    say ""
    say "  This checkout recorded session $1, but it is not on '$BRANCH', and the id"
    say "  file counts only there. If this is your lease, push from a checkout on"
    say "  '$BRANCH', or set PROJECT_SESSION_ID=$1 for this one push."
  fi
}

# --- the claims/ namespace is not a work branch -----------------------------
#
# Leases live inside refs/heads/* because that is the only namespace a hosted
# session's git proxy lets through. The cost is that "claims/<x>" now looks
# like an ordinary branch name to everything else, including .githooks/pre-push,
# which calls this script in check mode for every refs/heads/* ref it sends:
# the lease push itself arrives here as "claims/<branch>".
#
# So a claims/ name is never a thing to acquire or release a lease ON (that
# would be a lease on a lease), and in check mode it passes only when the push
# was started by --acquire, --release or --sweep, which set
# PROJECT_CLAIM_LEASE_PUSH for their one push. The hook passes the environment
# through unchanged, so it needs no special case of its own.
#
# Why the variable carries a sha and not "1": check mode never sees the object
# being pushed, only the branch name. A bare "1" left exported would let any
# code branch named claims/<x> through this layer. Requiring it to name a
# parentless empty-tree commit means it can only vouch for a lease-shaped
# object. It still cannot prove that object is the one being pushed; the green
# layer is the other half, and a code push to claims/<x> that has not passed
# BOTH is refused.
case "$BRANCH" in
  claims/*)
    if [ "$MODE" = "check" ] && [ -n "${PROJECT_CLAIM_LEASE_PUSH:-}" ] &&
       lease_object_is_inert "$PROJECT_CLAIM_LEASE_PUSH"; then
      sayf "lease push to '$BRANCH' (vouched by $PROJECT_CLAIM_LEASE_PUSH)"
      exit 0
    fi
    echo "'$BRANCH' is in the lease namespace (refs/heads/claims/*), not a work branch." >&2
    echo "Leases are written only by claim-branch.sh --acquire/--release/--sweep." >&2
    echo "Pick a branch name that does not start with claims/." >&2
    exit 2
    ;;
esac

# --- sweep -------------------------------------------------------------------
#
# --release does not delete (a hosted session cannot), so RELEASED markers and
# expired leases accumulate under refs/heads/claims/*, where they show up as
# branches. --sweep deletes those, from a session where deletion works. It never
# deletes a live lease (MINE or HELD), never deletes what it cannot read, and
# pins each deletion to the sha it judged, so a lease retaken in between is left
# alone. Safe to re-run.
#
# Exit 0 when everything it could judge was handled, 2 when anything could not
# be read or deleted. Never 1: sweeping claims nothing.
if [ "$MODE" = "sweep" ]; then
  if ! listing="$(git ls-remote origin 'refs/heads/claims/*' 2>/dev/null)"; then
    echo "could not list refs/heads/claims/* on origin" >&2
    exit 2
  fi
  sweep_bad=0
  while IFS=$'\t' read -r _sw_sha sw_ref; do
    case "${sw_ref:-}" in
      refs/heads/claims/*) ;;
      *) continue ;;
    esac
    LEASE_REF="$sw_ref"
    BRANCH="${sw_ref#refs/heads/claims/}"
    if ! sw_line="$(lease_read_ref "$sw_ref")"; then
      say "skipped $sw_ref (could not read it; not deleting what I cannot judge)"
      sweep_bad=1
      continue
    fi
    split_state "$sw_line"
    case "$S_STATE" in
      RELEASED|EXPIRED)
        if push_lease_ref "$sw_ref" "$S_SHA" ""; then
          say "deleted $sw_ref ($S_STATE, session $S_HOLDER)"
        else
          say "could not delete $sw_ref ($S_STATE); deletion may be refused here"
          sweep_bad=1
        fi
        ;;
      NONE) : ;;
      *) sayf "kept $sw_ref (live, session $S_HOLDER)" ;;
    esac
  done <<SWEEP_EOF
$listing
SWEEP_EOF
  [ "$sweep_bad" -eq 0 ] || exit 2
  exit 0
fi

# --- the old namespace: refs/claims/<branch> --------------------------------
#
# Leases used to live there. A copy of this template from before the move can
# still hold one, taken by a session running the old script, and that session
# cannot see a lease under refs/heads/claims/ either. This version does not read
# the old marker: it reports could-not-tell and says how to remove the ref.
# Treating it as absent would answer FREE on a branch another session may be
# working, the one answer this script must never give; reading it would keep a
# second parser alive for a format no new copy ever writes.
#
# Deleting a refs/claims/* ref does not go through the claim layer of
# .githooks/pre-push (it checks refs/heads/* only), so the command below works
# from any session whose remote allows ref deletion.
old_sha="$(remote_ref_sha "$OLD_LEASE_REF")" || exit 2
if [ -n "$old_sha" ]; then
  echo "could not tell: '$BRANCH' has a lease in the OLD namespace, $OLD_LEASE_REF," >&2
  echo "written by an earlier version of this script. This version reads only" >&2
  echo "refs/heads/claims/* and will not guess whether that lease is live." >&2
  echo "  If it is yours, or its holder has finished, remove it:" >&2
  echo "    git push origin :$OLD_LEASE_REF" >&2
  echo "  If another session may still hold it, coordinate, or wait out its TTL" >&2
  echo "  (4h by default) and then remove it the same way." >&2
  exit 2
fi

# --- acquire / release ------------------------------------------------------

if [ "$MODE" != "check" ]; then
  [ -n "$ME" ] || { echo "--$MODE needs --me <session-id>: the whole point is an identity git config cannot supply" >&2; exit 2; }

  state_line="$(lease_read_ref "$LEASE_REF")" || exit 2
  split_state "$state_line"
  STATE="$S_STATE"; HOLDER="$S_HOLDER"; HELD_AT="$S_AT"; OLD_SHA="$S_SHA"

  if [ "$MODE" = "release" ]; then
    case "$STATE" in
      NONE|RELEASED) sayf "release: no lease on '$BRANCH'"; exit 0 ;;
      MINE|EXPIRED)
        if [ "$STATE" = "EXPIRED" ] && [ "$HOLDER" != "$ME" ]; then
          say "refusing to release: '$BRANCH' is held by $HOLDER, not you"
          exit 1
        fi
        if release_ref "$OLD_SHA"; then
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
      warn_if_not_on_branch "$BRANCH"
      sayf "lease on '$BRANCH' is already yours (session $ME)"; exit 0 ;;
    HELD) report_held "$HOLDER" "$HELD_AT"; exit 1 ;;
  esac

  LEASE_SHA="$(lease_object)" || { echo "could not build the lease object" >&2; exit 2; }

  # NONE -> expect the ref to be absent (empty expected value). EXPIRED or
  # RELEASED -> CAS on the exact sha we read, so a takeover cannot clobber a
  # lease that was renewed in the meantime. Both are atomic create-or-fail
  # against the remote.
  case "$STATE" in
    EXPIRED|RELEASED) EXPECT="$OLD_SHA" ;;
    *) EXPECT="" ;;
  esac

  if ! lease_object_is_inert "$LEASE_SHA"; then
    echo "refusing to push a lease object that is not a parentless empty-tree commit" >&2
    exit 2
  fi
  if push_lease_ref "$LEASE_REF" "$EXPECT" "$LEASE_SHA"; then
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
    warn_if_not_on_branch "$BRANCH"
    sayf "acquired the lease on '$BRANCH' (session $ME, ttl ${TTL_H}h)"
    exit 0
  fi

  # The push was refused. git says "stale info", which is indistinguishable from
  # an ordinary out-of-date ref and names nobody - so re-read the ref and report
  # who actually holds it rather than echoing that.
  after="$(lease_read_ref "$LEASE_REF")" || exit 2
  split_state "$after"
  after_state="$S_STATE"
  after_sha="$S_SHA"

  # A REFUSED PUSH IS NOT PROOF SOMEBODY BEAT US, and reporting it as one sends
  # the operator to coordinate with a session that is not there. On a takeover
  # (EXPECT set) the CAS was pinned to $OLD_SHA, so if the ref still reads that
  # same sha then nothing moved and the push failed for its own reasons - a
  # transport blip, a server refusing the namespace, a hook. That is
  # could-not-tell, and the usual "the network died so the re-read would have
  # failed too" argument does not hold: the push and the re-read are separate
  # calls and only one of them has to fail.
  #
  # A CHANGED sha is a real race and stays CLAIMED, as does any HELD.
  if [ -n "$EXPECT" ] && [ "$after_sha" = "$EXPECT" ]; then
    echo "the lease push for '$BRANCH' was refused, but the lease has not moved" >&2
    echo "($after_sha). Nobody took it - the push itself failed. Retry, and if it" >&2
    echo "keeps failing check that the remote accepts refs/heads/claims/*." >&2
    exit 2
  fi

  case "$after_state" in
    HELD|EXPIRED|RELEASED)
      # EXPIRED or RELEASED here means it MOVED, but to something that is not a
      # live lease: a race with another writer that we lost. Still CLAIMED.
      report_held "$S_HOLDER" "$S_AT"
      exit 1
      ;;
    MINE)
      if ! session_id_write "$ME"; then
        echo "warning: could not record the session id, so your own pushes may" >&2
        echo "         still be refused; check that $(session_id_path 2>/dev/null) is writable" >&2
      fi
      warn_if_not_on_branch "$BRANCH"
      sayf "lease on '$BRANCH' is already yours (session $ME)"; exit 0 ;;
    *)
      # Absent AND refused: the usual cause is a directory/file clash. git
      # stores refs as paths, so refs/heads/claims/feat and
      # refs/heads/claims/feat/x cannot both exist, and a RELEASED marker left
      # by `--release feat` keeps the first one alive. Name it, and the fix.
      if clash="$(lease_df_clash)" && [ -n "$clash" ]; then
        echo "could not take the lease on '$BRANCH': git cannot store $LEASE_REF" >&2
        echo "beside an existing lease ref on a nested name:" >&2
        printf '%s\n' "$clash" | sed 's/^/    /' >&2
        echo "If that lease is RELEASED or EXPIRED, run: bin/claim-branch.sh --sweep" >&2
        echo "(from a session that can delete refs), then --acquire again. If it is live," >&2
        echo "its holder has to release it first, or pick a branch name that does not nest." >&2
        exit 2
      fi
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
#     --me  >  the per-worktree session-id file (only when HEAD is <branch>)
#           >  $PROJECT_SESSION_ID
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
#
# AND ONLY FROM A CHECKOUT ON THIS BRANCH. The file records who acquired from
# this checkout, not who is running the check. --acquire run from the shared
# main checkout (before `git worktree add`) leaves the holder's id there, and
# another session checking from that same checkout then adopted it and read
# the live lease as MINE - exit 0 on a held branch (review finding on PR #32).
# The caller the fallback exists for, the pre-push hook, runs in the worktree
# that is pushing its own branch, so HEAD names the branch there. A detached or
# unreadable HEAD honours no file: no identity, so a live lease reads HELD.
# That file is still read there, into OFF_BRANCH_ID, for one purpose only: if
# it names the holder, report_held says why the holder's own push was refused
# (pushing from a detached HEAD or under another local name). Without that, the
# holder reads "leased by another session" naming its own id.
OFF_BRANCH_ID=""
if [ -z "$ME" ]; then
  here_branch="$(git symbolic-ref --quiet HEAD 2>/dev/null)" || here_branch=""
  # Full ref, not --short: with a tag of the same name, --short answers
  # heads/<branch> and the holder's own push would be refused.
  if [ -n "$here_branch" ] && [ "$here_branch" = "refs/heads/$BRANCH" ]; then
    ME="$(session_id_read)"
  else
    OFF_BRANCH_ID="$(session_id_read)"
  fi
fi
[ -n "$ME" ] || ME="${PROJECT_SESSION_ID:-}"
check_state="$(lease_read_ref "$LEASE_REF")" || exit 2
case "${check_state%%|*}" in
  HELD)
    split_state "$check_state"
    report_held "$S_HOLDER" "$S_AT"
    exit 1
    ;;
  # NONE / MINE / EXPIRED / RELEASED fall through to the author check on
  # purpose. EXPIRED especially: a lease that outlives its TTL is meant to stop
  # holding the branch, or a dead session would own it forever and the TTL
  # would mean nothing. "an EXPIRED lease is free again" in the suite pins
  # that. RELEASED is a lease its holder gave back: free, like NONE.
  NONE|MINE|EXPIRED|RELEASED) : ;;
  *)
    # An unrecognised state is could-not-tell, not free. lease_read_ref returns
    # only the five above today, so this arm is unreachable - which is exactly
    # why it is here: a sixth token added later would otherwise fall through to
    # the author check and could answer 0 on a branch this signal never judged.
    echo "unrecognised lease state '${check_state%%|*}' for $BRANCH - refusing to call that free" >&2
    exit 2
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
#
# The FULL ref name, and only the line naming it exactly. ls-remote matches a
# pattern against the TAIL of each ref, so `ls-remote --heads origin feat/x`
# also returns refs/heads/claims/feat/x - the lease ref. A leased branch not yet
# on the remote would then "exist", fail to fetch, and every check would be 2.
rc=0
remote_line="$(git ls-remote --exit-code origin "refs/heads/$BRANCH" 2>/dev/null)" || rc=$?
case "$rc" in
  0) : ;;                                                # something matched; checked below
  2) sayf "free: no remote branch '$BRANCH'"; exit 0 ;;   # --exit-code: no match
  *) echo "could not reach origin (git ls-remote exit $rc)" >&2; exit 2 ;;
esac

REMOTE_SHA=""
while IFS=$'\t' read -r rl_sha rl_ref; do
  [ "$rl_ref" = "refs/heads/$BRANCH" ] && REMOTE_SHA="$rl_sha"
done <<REMOTE_EOF
$remote_line
REMOTE_EOF
if [ -z "$REMOTE_SHA" ]; then
  sayf "free: no remote branch '$BRANCH'"
  exit 0
fi

# Fetch the branch's FULL history, not a shallow slice. A shallow `--depth=N` is
# unsafe here: a branch with N recent commits of yours can still carry an OLDER
# commit by someone else, and the shallow fetch hides it while `git log` still
# succeeds. That reports 'free' on a claimed branch, which is the single answer
# this script must never get wrong. Correctness beats the few hundred ms.
if ! git fetch --quiet --no-tags origin "refs/heads/$BRANCH" 2>/dev/null; then
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
#
# It RETURNS NON-ZERO rather than printing nothing when awk cannot run, and the
# callers below exit 2 on that. Swapping in awk fixes the `|| true` and leaves
# the fail-open direction it exists to close: with no awk the count is empty,
# `[ "$bot_n" -gt 0 ]` errors and takes the ELSE branch, and the script prints
# `free: '<b>' has  commit(s)` and exits 0 - a blank number inside the one
# verdict this script must never get wrong. The perl guard further up is the
# same rule about a different tool.
count_lines() {
  local n
  n="$(printf '%s\n' "$1" | awk 'NF { n++ } END { print n + 0 }')" || return 1
  # awk exiting 0 having printed nothing (or something non-numeric) is the same
  # unusable answer as awk failing, so shape is checked rather than status alone.
  case "$n" in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf '%s\n' "$n"
}

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
  if ! mine_n=$(count_lines "$mine") || ! bot_n=$(count_lines "$bot_lines"); then
    echo "could not count the commits on '$BRANCH' (awk unavailable or unusable)" >&2
    echo "- refusing to report a free verdict carrying a blank count" >&2
    exit 2
  fi
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
