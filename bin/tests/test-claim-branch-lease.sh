#!/usr/bin/env bash
# =============================================================================
# test-claim-branch-lease.sh - hermetic suite for the branch LEASE
# =============================================================================
# test-claim-branch.sh covers the author-email signal. This covers the one it
# cannot see: two sessions under the SAME git identity, which is what every
# concurrent agent session on one machine looks like.
#
# The lease is a remote ref refs/claims/<branch> pointing at a commit whose
# message carries the marker. Acquiring is
#   git push --force-with-lease=refs/claims/<b>: origin <sha>:refs/claims/<b>
# where the EMPTY expected value means "must not exist" - an atomic
# create-or-fail.
#
# The dangerous answer is a held lease reported FREE, so the cases below lean on
# that direction. UNKNOWN (2) must never collapse into free (0): an unparseable
# marker is not an absent one.
#
# Hermetic: a bare repo in a temp dir plays origin. No network. The clock is
# INJECTED via --now, so TTL expiry is asserted without sleeping and without a
# fixture that rots.
#
# Run:  bash bin/tests/test-claim-branch-lease.sh
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../claim-branch.sh"
[ -f "$SCRIPT" ] || { echo "missing $SCRIPT" >&2; exit 1; }

# The fixture must not inherit host git config: a global core.hooksPath would
# run the host's hooks during fixture commits.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

# The check path falls back to $PROJECT_SESSION_ID when no --me is given. A
# value inherited from the developer's shell would silently change verdicts
# here, so the suite owns it. Unset, not empty-string: the script tests for
# non-empty.
unset PROJECT_SESSION_ID

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

# Fixture commands fail CLOSED. A half-built sandbox otherwise reports whatever
# that broken state happens to produce, which is green often enough to matter.
must() { "$@" || { echo "FIXTURE FAILED: $*" >&2; exit 1; }; }

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t claimlease)"
trap 'rm -rf "$TMP"' EXIT

ME='session-aaa'
OTHER='session-bbb'
EMAIL='dev@example.com'           # BOTH sessions use this: that is the point
NOW='2026-09-08T12:00:00Z'
LATER='2026-09-08T15:59:00Z'      # inside a 4h TTL taken at NOW
EXPIRED='2026-09-08T16:01:00Z'    # past it

ORIGIN="$TMP/origin.git"
must git init -q --bare "$ORIGIN"
must git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main

# Two working clones standing in for two concurrent agent sessions. Same
# user.email in both, deliberately.
seed_repo() { # $1 dir
  must git init -q "$1"
  must git -C "$1" config user.email "$EMAIL"
  must git -C "$1" config user.name  'Dev'
  must git -C "$1" config commit.gpgsign false
  must git -C "$1" config core.autocrlf false
  must git -C "$1" remote add origin "$ORIGIN"
}
seed_repo "$TMP/a"
printf 'base\n' > "$TMP/a/README.md"
must git -C "$TMP/a" add README.md
must git -C "$TMP/a" commit -qm base
must git -C "$TMP/a" branch -M main
must git -C "$TMP/a" push -q origin main

must git clone -q "$ORIGIN" "$TMP/b"
must git -C "$TMP/b" config user.email "$EMAIL"
must git -C "$TMP/b" config user.name  'Dev'
must git -C "$TMP/b" config commit.gpgsign false
must git -C "$TMP/b" config core.autocrlf false

A() { ( cd "$TMP/a" && bash "$SCRIPT" "$@" ); }
B() { ( cd "$TMP/b" && bash "$SCRIPT" "$@" ); }

run() { # run <fn> <args...> -> sets ACTUAL and OUT
  local fn="$1"; shift
  OUT="$("$fn" "$@" 2>&1)"; ACTUAL=$?
}
want() { # want <expected-exit> <label>
  if [ "$ACTUAL" = "$1" ]; then ok "$2 (exit $1)"
  else bad "$2" "want exit $1, got $ACTUAL: $OUT"; fi
}

# The lease commit a rival session would have pushed. Built by hand so the
# fixture can plant one without going through the script under test.
rival_lease() { # $1 session  $2 at  $3 ttl-hours
  git -C "$TMP/a" commit-tree "$(git -C "$TMP/a" hash-object -t tree /dev/null)" \
    -m "CLAIM harness=other session=$1 at=$2 ttl=$3h"
}

echo "claim-branch.sh - lease"

# --- acquire ---------------------------------------------------------------
run A --acquire feat/x --me "$ME" --harness claude-code --now "$NOW"
want 0 "session A acquires a free branch"

run A --acquire feat/x --me "$ME" --harness claude-code --now "$LATER"
want 0 "re-acquiring my OWN lease is idempotent, not a collision"

# THE case the email signal cannot see. Same user.email in both clones.
run B --acquire feat/x --me "$OTHER" --harness cursor --now "$LATER"
want 1 "session B cannot acquire A's live lease (SAME user.email)"

case "$OUT" in
  *"$ME"*) ok "refusal names the holding session" ;;
  *)       bad "refusal names the holding session" "got: $OUT" ;;
esac

# git reports a lease rejection as "stale info", which is indistinguishable from
# an ordinary out-of-date ref. The script must re-read the ref and say who holds
# it rather than echo that.
case "$OUT" in
  *"stale info"*) bad "refusal does not leak git's 'stale info'" "got: $OUT" ;;
  *)              ok "refusal does not leak git's 'stale info'" ;;
esac

# --- check reports the lease ------------------------------------------------
run B feat/x --me "$OTHER" --now "$LATER"
want 1 "plain check reports another session's live lease as CLAIMED"

run A feat/x --me "$ME" --now "$LATER"
want 0 "plain check treats my own lease as free"

# --- TTL --------------------------------------------------------------------
run B feat/x --me "$OTHER" --now "$EXPIRED"
want 0 "an EXPIRED lease is free again"

run B --acquire feat/x --me "$OTHER" --harness cursor --now "$EXPIRED"
want 0 "an expired lease can be taken over"

run A feat/x --me "$ME" --now "$EXPIRED"
want 1 "after takeover the original holder now sees CLAIMED"

# --- release ----------------------------------------------------------------
run B --release feat/x --me "$OTHER" --now "$EXPIRED"
want 0 "the holder can release its own lease"

run A feat/x --me "$ME" --now "$EXPIRED"
want 0 "a released branch is free again"

run A --acquire feat/y --me "$ME" --harness claude-code --now "$NOW"
want 0 "A acquires feat/y"
run B --release feat/y --me "$OTHER" --now "$NOW"
want 1 "a session cannot release a lease it does not hold"

# --- layering: the email signal still fires ---------------------------------
# The lease is additive. A branch carrying a DIFFERENT author's pushed commits
# is CLAIMED even with no lease on it - that is the teammate who never ran this
# tool, and the one case the lease alone cannot see.
must git -C "$TMP/a" checkout -q -b feat/teammate
printf 'x\n' > "$TMP/a/t.txt"
must git -C "$TMP/a" add t.txt
must git -C "$TMP/a" -c user.email='someone@else.test' -c user.name='Teammate' commit -qm 'their work'
must git -C "$TMP/a" push -q origin feat/teammate
must git -C "$TMP/a" checkout -q main

run A feat/teammate --me "$ME" --now "$NOW"
want 1 "a branch with another AUTHOR is still CLAIMED with no lease present"

# --- github-actions[bot] is automation, not a session -----------------------
# A workflow that pushes to a branch must not make every later human push read
# as a collision. Matched as an EXACT address: a substring rule on "bot" would
# silently ignore a real person whose address contains it.
must git -C "$TMP/a" checkout -q -b feat/botpush
printf 'g\n' > "$TMP/a/g.txt"
must git -C "$TMP/a" add g.txt
must git -C "$TMP/a" -c user.email='github-actions[bot]@users.noreply.github.com' \
  -c user.name='github-actions[bot]' commit -qm 'regenerated baselines'
must git -C "$TMP/a" push -q origin feat/botpush
must git -C "$TMP/a" checkout -q main

run A feat/botpush --me "$ME" --now "$NOW"
want 0 "a branch whose only other author is github-actions[bot] stays free"
# Matched on the free path's OWN wording, not on the string "github-actions".
# The bot's address appears in the CLAIMED report too, so a substring match on
# the name is satisfied whether the exemption fired or not - measured: breaking
# the exemption left a bare `*github-actions*` case green.
case "$OUT" in
  *"automation, not another session"*) ok "the free verdict SAYS it ignored the bot" ;;
  *)                                   bad "the free verdict SAYS it ignored the bot" "got: $OUT" ;;
esac

# A real person whose address merely CONTAINS 'bot' must still count. This is
# the case a substring match would get wrong, and it is the unsafe direction.
must git -C "$TMP/a" checkout -q -b feat/notabot
printf 'n\n' > "$TMP/a/n.txt"
must git -C "$TMP/a" add n.txt
must git -C "$TMP/a" -c user.email='robotham@example.com' -c user.name='R Botham' commit -qm 'human work'
must git -C "$TMP/a" push -q origin feat/notabot
must git -C "$TMP/a" checkout -q main

run A feat/notabot --me "$ME" --now "$NOW"
want 1 "a human address merely CONTAINING 'bot' is still CLAIMED"

# The near miss that makes the -x in `grep -qxF` load-bearing: an address that
# is a strict SUBSTRING of a real allowlist entry. Without -x the allowlist line
# "41898282+github-actions[bot]@users.noreply.github.com" contains this one, so
# it would be matched and silently ignored - a collision detector waving through
# an address nobody vetted. The case above does not cover it: "robotham@" is not
# a substring of anything in the list, so dropping -x leaves it green. Measured
# before this case existed: the -x mutation produced 0 red across 66 cases.
must git -C "$TMP/a" checkout -q -b feat/substringbot
printf 's\n' > "$TMP/a/s.txt"
must git -C "$TMP/a" add s.txt
must git -C "$TMP/a" -c user.email='actions[bot]@users.noreply.github.com' \
  -c user.name='Not The Actions Bot' commit -qm 'not the actions bot'
must git -C "$TMP/a" push -q origin feat/substringbot
must git -C "$TMP/a" checkout -q main

run A feat/substringbot --me "$ME" --now "$NOW"
want 1 "an address that is a strict SUBSTRING of the bot's is NOT exempt"

# --- the actual race --------------------------------------------------------
# Everything above exits on the PRE-CHECK: lease_read sees HELD and returns
# before the push happens, so none of it exercises the compare-and-swap on the
# push itself. Removing --force-with-lease entirely leaves all of the above
# green, which is why the next three sections exist.
#
# The window is between a session reading "no lease" and its push landing. To
# open it deterministically, give the pushing clone a git pre-push hook that
# creates a COMPETING lease the instant the push starts. No seam is added to the
# script for this: git's own hook machinery supplies the interleaving.
must git clone -q "$ORIGIN" "$TMP/racer"
must git -C "$TMP/racer" config user.email "$EMAIL"
must git -C "$TMP/racer" config user.name 'Dev'
must git -C "$TMP/racer" config commit.gpgsign false

RIVAL="$(rival_lease "$OTHER" "$NOW" 4)"
[ -n "$RIVAL" ] || { echo "FIXTURE FAILED: could not build the rival lease" >&2; exit 1; }

HOOK="$TMP/racer/.git/hooks/pre-push"
cat > "$HOOK" <<EOH
#!/usr/bin/env bash
# Fires inside the racer's push: plant a rival lease before this push lands.
git -C "$TMP/a" push -q --force origin "$RIVAL:refs/claims/feat/race" || true
EOH
must chmod +x "$HOOK"

OUT="$( ( cd "$TMP/racer" && bash "$SCRIPT" --acquire feat/race --me "$ME" --harness claude-code --now "$NOW" ) 2>&1 )"; ACTUAL=$?
want 1 "a lease that appears mid-push is REFUSED (git create semantics, not the pre-check)"

# And the loser must not have overwritten the winner.
HOLDER="$(git -C "$TMP/a" ls-remote origin refs/claims/feat/race | cut -f1)"
if [ "$HOLDER" = "$RIVAL" ]; then ok "the rival still holds the lease after the refused push"
else bad "the rival still holds the lease after the refused push" "ref is $HOLDER, wanted $RIVAL"; fi

must rm -f "$HOOK"

# The case above is refused by git's CREATE semantics: the push was computed
# when the ref did not exist, so it is sent as a create, and the server rejects
# a create against an existing ref ("reference already exists") whether or not
# --force is passed. Worth knowing, because it means that case does NOT test the
# compare-and-swap - replacing --force-with-lease with --force leaves it green.
#
# The danger the CAS exists for is a lease RENEWED between being read as expired
# and the takeover push landing: the holder is alive again, and stealing from
# them is exactly the collision this script exists to prevent.
#
# The hook below opens that window MID-PUSH, and git refuses it on its own (the
# push carries the old value from ref advertisement, which is now stale), so
# this case too stays green under a plain --force. The case that isolates the
# flag is the next one - "moved before the push" - which moves the ref BEFORE
# the push connects, where --force finds the advertised old value matching and
# clobbers. Keep both: this one pins the behaviour, that one pins the flag.
must git -C "$TMP/a" push -q --force origin "$(rival_lease "$OTHER" "$NOW" 4):refs/claims/feat/renew"

RENEWED="$(rival_lease "$OTHER" "$EXPIRED" 4)"
[ -n "$RENEWED" ] || { echo "FIXTURE FAILED: could not build the renewed lease" >&2; exit 1; }

cat > "$HOOK" <<EOH
#!/usr/bin/env bash
# The holder renews mid-push: the ref moves off the sha the takeover read.
git -C "$TMP/a" push -q --force origin "$RENEWED:refs/claims/feat/renew" || true
EOH
must chmod +x "$HOOK"

# At EXPIRED the lease reads as expired, so the racer proceeds to take it over.
OUT="$( ( cd "$TMP/racer" && bash "$SCRIPT" --acquire feat/renew --me "$ME" --harness claude-code --now "$EXPIRED" ) 2>&1 )"; ACTUAL=$?
if [ "$ACTUAL" != 0 ]; then ok "a takeover is refused when the lease is renewed mid-push (compare-and-swap)"
else bad "a takeover is refused when the lease is renewed mid-push (compare-and-swap)" "acquired anyway: $OUT"; fi

HOLDER="$(git -C "$TMP/a" ls-remote origin refs/claims/feat/renew | cut -f1)"
if [ "$HOLDER" = "$RENEWED" ]; then ok "the renewed lease survives the refused takeover"
else bad "the renewed lease survives the refused takeover" "ref is $HOLDER, wanted $RENEWED"; fi

must rm -f "$HOOK"

# --- the window --force-with-lease actually closes --------------------------
# The window where the lease IS load-bearing is between this script reading the
# lease and the push opening its connection. A ref that moves in THAT window is
# advertised as its NEW value, so a plain --force finds the old value matching
# and clobbers a live holder. Only a lease pinned to the sha we actually read
# refuses.
#
# Seam: a `git` shim ahead of the real one on PATH which performs the rival's
# renew the first time it sees a push, then execs through. The interleaving
# comes from the shim; no seam is added to claim-branch.sh for it.
must git -C "$TMP/a" push -q --force origin "$(rival_lease "$OTHER" "$NOW" 4):refs/claims/feat/window"

RENEWED2="$(rival_lease "$OTHER" "$EXPIRED" 4)"
[ -n "$RENEWED2" ] || { echo "FIXTURE FAILED: could not build the second renewed lease" >&2; exit 1; }

REAL_GIT="$(command -v git)"
SHIM="$TMP/shim"
must mkdir -p "$SHIM"
cat > "$SHIM/git" <<EOS
#!/usr/bin/env bash
# Renew the rival lease once, on the first push, BEFORE the real push runs.
for a in "\$@"; do
  if [ "\$a" = "push" ] && [ ! -e "$TMP/.shim-fired" ]; then
    : > "$TMP/.shim-fired"
    "$REAL_GIT" -C "$TMP/a" push -q --force origin "$RENEWED2:refs/claims/feat/window" || true
    break
  fi
done
exec "$REAL_GIT" "\$@"
EOS
must chmod +x "$SHIM/git"

OUT="$( ( cd "$TMP/racer" && PATH="$SHIM:$PATH" bash "$SCRIPT" --acquire feat/window \
  --me "$ME" --harness claude-code --now "$EXPIRED" ) 2>&1 )"; ACTUAL=$?
if [ "$ACTUAL" != 0 ]; then ok "a takeover is refused when the lease moved before the push (the CAS earns its keep)"
else bad "a takeover is refused when the lease moved before the push (the CAS earns its keep)" "acquired anyway: $OUT"; fi

HOLDER2="$(git -C "$TMP/a" ls-remote origin refs/claims/feat/window | cut -f1)"
if [ "$HOLDER2" = "$RENEWED2" ]; then ok "the pre-push renewal survives (a plain --force would have clobbered it)"
else bad "the pre-push renewal survives (a plain --force would have clobbered it)" "ref is $HOLDER2, wanted $RENEWED2"; fi

must rm -f "$TMP/.shim-fired"

# --- a concurrent process cannot swap the lease body under us ---------------
# refs/* is SHARED by every worktree of a repo, and a project running several
# sessions reaches this script from several of them at once. A single FIXED
# local ref name would therefore be contended: one session fetches branch X's
# lease into it, another overwrites with branch Y's, and the first parses Y's
# session and ttl while judging X.
#
# The poison marker names THIS session, so a script that read through a fixed
# ref name would answer MINE and exit 0 free on a branch another session
# genuinely holds. Reverting the destination to a fixed name fails this case.
#
# THE INJECTION POINT IS THE WHOLE CASE, and the first draft got it wrong.
# Firing on `log` is too late: lease_read resolves the ref with `git rev-parse`
# and then passes the resolved SHA to `git log`, so by the time `log` runs there
# is no ref left to poison - a fixed-name implementation would have resolved the
# correct sha already and the case passed whatever the code did. So the shim
# fires on `fetch`, runs the REAL fetch first, and poisons the fixed name in the
# window between the fetch landing and the rev-parse reading it. Raised by
# review; the mutation battery could not see it, because a mutation only
# perturbs code you already wrote and this was a gap between the fixture and
# reality.
must git -C "$TMP/a" push -q --force origin "$(rival_lease "$OTHER" "$NOW" 4):refs/claims/feat/collide"

POISON="$(git -C "$TMP/a" commit-tree "$(git -C "$TMP/a" hash-object -t tree /dev/null)" \
  -m "CLAIM harness=claude-code session=$ME at=$NOW ttl=4h")"
[ -n "$POISON" ] || { echo "FIXTURE FAILED: could not build the poison lease" >&2; exit 1; }

SHIM2="$TMP/shim2"
must mkdir -p "$SHIM2"
cat > "$SHIM2/git" <<EOS2
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = "fetch" ] && [ ! -e "$TMP/.collide-fired" ]; then
    : > "$TMP/.collide-fired"
    # Real fetch FIRST, so the ref exists to be clobbered, then poison the fixed
    # name before the caller's rev-parse reads it.
    "$REAL_GIT" "\$@"; rc=\$?
    "$REAL_GIT" -C "$TMP/a" update-ref refs/claim-lease-read "$POISON" || true
    exit \$rc
  fi
done
exec "$REAL_GIT" "\$@"
EOS2
must chmod +x "$SHIM2/git"

OUT="$( ( cd "$TMP/a" && PATH="$SHIM2:$PATH" bash "$SCRIPT" feat/collide --me "$ME" --now "$NOW" ) 2>&1 )"; ACTUAL=$?
want 1 "a clobbered refs/claim-lease-read cannot turn another session's lease into mine"
case "$OUT" in
  *"$OTHER"*) ok "the verdict names the real holder, not the poisoned marker" ;;
  *)          bad "the verdict names the real holder, not the poisoned marker" "got: $OUT" ;;
esac

# FIXTURE SANITY, and the case above is worth nothing without it. The verdict it
# asserts (exit 1, names $OTHER) is ALSO what correct code produces when the
# poison never lands - a shim that never matched `fetch`, or an `update-ref`
# that failed under `|| true`. A fixture that silently stopped firing would
# leave this green while proving nothing, which is the same defect the injection
# point itself had. Same guard as the ls-remote counter in test-claim-branch.sh.
#
# Both halves are needed: that the shim RAN, and that the poison is actually on
# the fixed ref name at the end. The second is stable because correct code only
# ever touches refs/claim-lease-read-$$ and deletes it, so the bare name it
# never reads keeps whatever the shim put there.
if [ -e "$TMP/.collide-fired" ]; then ok "fixture sanity: the collide shim fired"
else bad "fixture sanity: the collide shim fired" "no $TMP/.collide-fired - the poison never landed"; fi
POISONED_AT="$(git -C "$TMP/a" rev-parse --verify --quiet refs/claim-lease-read || true)"
if [ "$POISONED_AT" = "$POISON" ]; then
  ok "fixture sanity: refs/claim-lease-read really carries the poison marker"
else
  bad "fixture sanity: refs/claim-lease-read really carries the poison marker" \
      "ref is '${POISONED_AT:-<absent>}', wanted $POISON"
fi

must rm -f "$TMP/.collide-fired"
git -C "$TMP/a" update-ref -d refs/claim-lease-read 2>/dev/null || true

# --- a lease taken over between ls-remote and fetch -------------------------
# lease_read asks ls-remote for the sha, then fetches. If another session takes
# the lease over in that window, the ls-remote sha is already stale.
#
# Reading the object by that stale sha LOOKS safe - a missing object would fail
# and land as could-not-tell - but the object is never missing in the case that
# matters: lease_object builds the lease commit locally with commit-tree before
# pushing, so a session's OWN lease object stays in its object database forever.
# The read succeeds and answers MINE on a branch somebody else now holds.
#
# Seam: a `git` shim that hands the lease to OTHER the first time it sees a
# fetch, i.e. after ls-remote has already returned A's own sha.
run A --acquire feat/moved --me "$ME" --harness claude-code --now "$NOW"
want 0 "A acquires feat/moved (its lease object is now in A's local object store)"

STOLEN="$(rival_lease "$OTHER" "$NOW" 4)"
[ -n "$STOLEN" ] || { echo "FIXTURE FAILED: could not build the stolen lease" >&2; exit 1; }

SHIM3="$TMP/shim3"
must mkdir -p "$SHIM3"
cat > "$SHIM3/git" <<EOS3
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = "fetch" ] && [ ! -e "$TMP/.moved-fired" ]; then
    : > "$TMP/.moved-fired"
    "$REAL_GIT" -C "$TMP/a" push -q --force origin "$STOLEN:refs/claims/feat/moved" || true
    break
  fi
done
exec "$REAL_GIT" "\$@"
EOS3
must chmod +x "$SHIM3/git"

OUT="$( ( cd "$TMP/a" && PATH="$SHIM3:$PATH" bash "$SCRIPT" feat/moved --me "$ME" --now "$NOW" ) 2>&1 )"; ACTUAL=$?
want 1 "a lease taken over between ls-remote and fetch is judged on what was FETCHED, not the stale sha"
case "$OUT" in
  *"$OTHER"*) ok "the moved-lease verdict names the new holder" ;;
  *)          bad "the moved-lease verdict names the new holder" "got: $OUT" ;;
esac
must rm -f "$TMP/.moved-fired"

# --- an out-of-range ttl is could-not-tell, never expired -------------------
# Expiry is `now >= at + ttl*3600` in shell arithmetic: signed 64-bit, and it
# WRAPS. A large ttl yields a negative deadline, so every lease compares as past
# it and a LIVE lease reads EXPIRED and then free. That is the answer this
# script must never give, so an implausible ttl has to land as 2.
must git -C "$TMP/a" push -q --force origin "$(rival_lease "$OTHER" "$NOW" 9999999999999999):refs/claims/feat/hugettl"

run A feat/hugettl --me "$ME" --now "$NOW"
want 2 "a wrapping ttl is 2, not 0 (a live lease must not read as expired)"

run A --ttl 9999999999999999 --acquire feat/ttlflag --me "$ME" --now "$NOW"
want 2 "--ttl is bounded too, so no such marker can be written in the first place"

run A --ttl 0 --acquire feat/ttlzero --me "$ME" --now "$NOW"
want 2 "--ttl 0 is rejected rather than stamping an already-expired lease"

# --- identity on the check path (the pre-push self-block) -------------------
# .githooks/pre-push runs `claim-branch.sh <branch> --quiet-if-free` with no
# --me, because it has no session id to pass. Without a fallback, acquiring a
# lease on your own branch blocks your own next push and the report names your
# own session as "another session". These cases pin the fallback and, just as
# importantly, pin what it must NOT relax.
must git -C "$TMP/a" checkout -q -b feat/selfpush
printf 'p\n' > "$TMP/a/p.txt"
must git -C "$TMP/a" add p.txt
must git -C "$TMP/a" commit -qm 'my own work'
must git -C "$TMP/a" push -q origin feat/selfpush
must git -C "$TMP/a" checkout -q main

run A --acquire feat/selfpush --me "$ME" --harness claude-code --now "$NOW"
want 0 "A leases its own branch"

SELF_ID="$(git -C "$TMP/a" rev-parse --absolute-git-dir)/claim-session-id"

# The hook's exact invocation: no --me, no identity ANYWHERE. The id file is
# removed explicitly - the --acquire above writes one, so without this the case
# would pass through the file and stop testing the thing its name claims.
rm -f "$SELF_ID"
OUT="$( ( cd "$TMP/a" && env -u PROJECT_SESSION_ID bash "$SCRIPT" feat/selfpush --quiet-if-free --now "$NOW" ) 2>&1 )"; ACTUAL=$?
want 1 "no --me, no env and no id file: a live lease still reads as HELD (unknown is not free)"

OUT="$( ( cd "$TMP/a" && PROJECT_SESSION_ID="$ME" bash "$SCRIPT" feat/selfpush --quiet-if-free --now "$NOW" ) 2>&1 )"; ACTUAL=$?
want 0 "PROJECT_SESSION_ID matching the holder: my own push is not blocked"

# A DIFFERENT session's id in the environment must not unlock someone's lease.
OUT="$( ( cd "$TMP/a" && PROJECT_SESSION_ID="$OTHER" bash "$SCRIPT" feat/selfpush --quiet-if-free --now "$NOW" ) 2>&1 )"; ACTUAL=$?
want 1 "PROJECT_SESSION_ID of another session: still CLAIMED"

# PRECEDENCE, and it is the safety property rather than a preference: the env
# var cannot be made per-session, so a stray machine-wide value must NOT be able
# to suppress the per-worktree file. Here the file says this worktree is the
# holder and the environment lies that it is someone else; the file has to win,
# or one global export would hand every session one identity.
printf '%s\n' "$ME" > "$SELF_ID"
OUT="$( ( cd "$TMP/a" && PROJECT_SESSION_ID="$OTHER" bash "$SCRIPT" feat/selfpush --quiet-if-free --now "$NOW" ) 2>&1 )"; ACTUAL=$?
want 0 "the id file outranks a stray machine-wide PROJECT_SESSION_ID"
rm -f "$SELF_ID"

# The fallback is CHECK-ONLY. Acquiring must keep naming itself explicitly, or
# the environment becomes an implicit identity.
OUT="$( ( cd "$TMP/a" && PROJECT_SESSION_ID="$ME" bash "$SCRIPT" --acquire feat/selfpush --now "$NOW" ) 2>&1 )"; ACTUAL=$?
want 2 "--acquire still requires an explicit --me; the env var does not satisfy it"

must git -C "$TMP/a" push -q --force origin ":refs/claims/feat/selfpush"

# --- the per-worktree session-id file ---------------------------------------
# The env var cannot be per-session: a harness settings file's env block is
# static and machine-wide, and a SessionStart hook's exports never reach the
# shell that runs git push. So --acquire records the id in the worktree's OWN
# git dir, which IS the session boundary, and the check reads it when no --me
# and no env var is given.
must git -C "$TMP/a" checkout -q -b feat/idfile
printf 'i\n' > "$TMP/a/i.txt"
must git -C "$TMP/a" add i.txt
must git -C "$TMP/a" commit -qm 'idfile work'
must git -C "$TMP/a" push -q origin feat/idfile
must git -C "$TMP/a" checkout -q main

ID_FILE="$SELF_ID"
rm -f "$ID_FILE"

run A --acquire feat/idfile --me "$ME" --harness claude-code --now "$NOW"
want 0 "A acquires feat/idfile"

if [ -f "$ID_FILE" ]; then ok "--acquire records the session id in this worktree"
else bad "--acquire records the session id in this worktree" "no file at $ID_FILE"; fi

if [ "$(tr -d '[:space:]' < "$ID_FILE")" = "$ME" ]; then ok "the recorded id is the acquiring session"
else bad "the recorded id is the acquiring session" "got '$(cat "$ID_FILE")'"; fi

# THE case the whole mechanism exists for: the pre-push hook's exact
# invocation, no --me and no env var, must not be blocked by my own lease.
OUT="$( ( cd "$TMP/a" && env -u PROJECT_SESSION_ID bash "$SCRIPT" feat/idfile --quiet-if-free --now "$NOW" ) 2>&1 )"; ACTUAL=$?
want 0 "the id file alone unblocks the holder's own push (no --me, no env var)"

# It must not unblock ANYONE - a different session's worktree has its own file.
OTHER_WT="$TMP/b"
OTHER_ID="$(git -C "$OTHER_WT" rev-parse --absolute-git-dir)/claim-session-id"
rm -f "$OTHER_ID"
OUT="$( ( cd "$OTHER_WT" && env -u PROJECT_SESSION_ID bash "$SCRIPT" feat/idfile --quiet-if-free --now "$NOW" ) 2>&1 )"; ACTUAL=$?
want 1 "a different clone with no id file still sees the lease as CLAIMED"

# A file naming a DIFFERENT session must not unlock the lease either.
printf '%s\n' "$OTHER" > "$OTHER_ID"
OUT="$( ( cd "$OTHER_WT" && env -u PROJECT_SESSION_ID bash "$SCRIPT" feat/idfile --quiet-if-free --now "$NOW" ) 2>&1 )"; ACTUAL=$?
want 1 "an id file naming another session does not unlock the lease"
rm -f "$OTHER_ID"

# --me still outranks the file.
OUT="$( ( cd "$TMP/a" && env -u PROJECT_SESSION_ID bash "$SCRIPT" feat/idfile --me "$OTHER" --quiet-if-free --now "$NOW" ) 2>&1 )"; ACTUAL=$?
want 1 "--me outranks the id file"

# --release clears it, so the file never outlives the lease it vouches for.
run A --release feat/idfile --me "$ME" --now "$NOW"
want 0 "A releases feat/idfile"
if [ ! -f "$ID_FILE" ]; then ok "--release clears the recorded session id"
else bad "--release clears the recorded session id" "file still at $ID_FILE"; fi

# A STALE file (lease gone) must not manufacture an identity that matters. With
# no lease the branch is free anyway; the point is that it does not error.
printf '%s\n' "$ME" > "$ID_FILE"
OUT="$( ( cd "$TMP/a" && env -u PROJECT_SESSION_ID bash "$SCRIPT" feat/idfile --quiet-if-free --now "$NOW" ) 2>&1 )"; ACTUAL=$?
want 0 "a stale id file on a released branch is harmless"
rm -f "$ID_FILE"

# --- per-WORKTREE isolation, which is the whole design ----------------------
# Every case above uses separate CLONES, and for a plain clone --absolute-git-dir
# and --git-common-dir name the SAME directory. So none of them can tell the two
# apart, and swapping one for the other in session_id_path leaves them all green.
#
# The distinction only appears between linked WORKTREES of one repo, which is
# exactly the arrangement parallel sessions run in. With the common dir, one id
# file would be visible to every worktree and two sessions would answer MINE to
# each other's leases - the defect the lease exists to prevent, reintroduced by
# a one-flag mistake.
must git -C "$TMP/a" worktree add -q -b wt-session-a "$TMP/wt-a"
must git -C "$TMP/a" worktree add -q -b wt-session-b "$TMP/wt-b"

WT_A_ID="$(git -C "$TMP/wt-a" rev-parse --absolute-git-dir)/claim-session-id"
WT_B_ID="$(git -C "$TMP/wt-b" rev-parse --absolute-git-dir)/claim-session-id"
rm -f "$WT_A_ID" "$WT_B_ID"

# Sanity: the fixture must actually BE the layout under test, or the cases below
# assert nothing. A worktree whose git dir equals the common dir would make the
# isolation checks pass for the wrong reason.
if [ "$(git -C "$TMP/wt-a" rev-parse --absolute-git-dir)" != "$(git -C "$TMP/wt-b" rev-parse --absolute-git-dir)" ]; then
  ok "fixture sanity: the two worktrees have distinct git dirs"
else
  bad "fixture sanity: the two worktrees have distinct git dirs" "both resolve to the same path"
fi

OUT="$( ( cd "$TMP/wt-a" && env -u PROJECT_SESSION_ID bash "$SCRIPT" --acquire feat/wtlease --me "$ME" --harness claude-code --now "$NOW" ) 2>&1 )"; ACTUAL=$?
want 0 "worktree A acquires feat/wtlease"

if [ -f "$WT_A_ID" ]; then ok "the id lands in worktree A's own git dir"
else bad "the id lands in worktree A's own git dir" "no file at $WT_A_ID"; fi

# Asserting only that B's OWN path is empty is nearly vacuous: it is satisfied
# whether the id landed in A's git dir or in the SHARED common dir, and the
# common dir is exactly where the wrong flag would put it. Measured - swapping
# --absolute-git-dir for --git-common-dir left this case green until the second
# assertion was added. Check the shared location too.
# Resolved by cd + pwd rather than `rev-parse --path-format=absolute`, which
# only exists from git 2.31. Older git does not reject the unknown option: it
# echoes it as a positional result and still exits 0, so COMMON_ID would be a
# multi-line non-path, the -f test would be false, and this assertion would pass
# without ever looking at the file it names. Raised by review.
COMMON_ID="$( cd "$TMP/wt-b" && cd "$(git rev-parse --git-common-dir)" && pwd )/claim-session-id"
if [ ! -f "$WT_B_ID" ] && [ ! -f "$COMMON_ID" ]; then
  ok "the id is in NEITHER worktree B's git dir nor the shared common dir"
else
  bad "the id is in NEITHER worktree B's git dir nor the shared common dir" \
      "found at $([ -f "$WT_B_ID" ] && printf '%s ' "$WT_B_ID"; [ -f "$COMMON_ID" ] && printf '%s' "$COMMON_ID")"
fi

# The verdict, which is what actually matters: B must be told the branch is held.
OUT="$( ( cd "$TMP/wt-b" && env -u PROJECT_SESSION_ID bash "$SCRIPT" feat/wtlease --quiet-if-free --now "$NOW" ) 2>&1 )"; ACTUAL=$?
want 1 "a sibling worktree cannot inherit A's identity and sees CLAIMED"

OUT="$( ( cd "$TMP/wt-a" && env -u PROJECT_SESSION_ID bash "$SCRIPT" feat/wtlease --quiet-if-free --now "$NOW" ) 2>&1 )"; ACTUAL=$?
want 0 "worktree A is still unblocked by its own id file"

OUT="$( ( cd "$TMP/wt-a" && env -u PROJECT_SESSION_ID bash "$SCRIPT" --release feat/wtlease --me "$ME" --now "$NOW" ) 2>&1 )"; ACTUAL=$?
want 0 "worktree A releases feat/wtlease"

# --- the lease push must survive the green gate -----------------------------
# Every case above runs in a fixture with NO hooks installed, so none of them
# could see that .githooks/pre-push refuses a lease outright: it demands a green
# marker for the tree being pushed, and a lease commit's tree is the EMPTY tree,
# which nothing ever verifies. A feature can be entirely green in this file and
# unusable in a real repo.
#
# Modelled rather than imported: a hook that refuses unless PROJECT_SKIP_VERIFY=1
# captures the contract the real gate has, without this suite depending on the
# real gate's source. A deletion sends an all-zero local sha and is skipped,
# because there is no tree to vouch for - a stand-in stricter than the thing it
# stands in for manufactures failures no user can hit.
GATEHOOK="$TMP/a/.git/hooks/pre-push"
cat > "$GATEHOOK" <<'EOG'
#!/usr/bin/env bash
while read -r _local_ref local_sha _remote_ref _remote_sha; do
  [ -n "${local_sha:-}" ] || continue
  case "$local_sha" in
    *[!0]*) ;;
    *) continue ;;
  esac
  [ "${PROJECT_SKIP_VERIFY:-}" = "1" ] || {
    echo "BLOCKED: no green verification for this tree" >&2
    exit 1
  }
done
exit 0
EOG
must chmod +x "$GATEHOOK"

run A --acquire feat/gated --me "$ME" --harness claude-code --now "$NOW"
want 0 "--acquire succeeds under a green-gate style pre-push hook"

OUT="$( ( cd "$TMP/a" && git ls-remote origin refs/claims/feat/gated ) 2>&1 )"
case "$OUT" in
  *refs/claims/feat/gated*) ok "the lease ref actually reached the remote through the hook" ;;
  *)                        bad "the lease ref actually reached the remote through the hook" "ls-remote: $OUT" ;;
esac

# The bypass must NOT leak to ordinary pushes: a normal branch push through the
# same hook still has to be refused, or claim-branch.sh would have quietly
# disabled the green gate for everything it touches.
must git -C "$TMP/a" checkout -q -b feat/gated-code
printf 'c\n' > "$TMP/a/c.txt"
must git -C "$TMP/a" add c.txt
must git -C "$TMP/a" commit -qm 'ordinary code'
if git -C "$TMP/a" push -q origin feat/gated-code 2>/dev/null; then
  bad "the bypass does not leak to ordinary code pushes" "an unverified branch push went through"
else
  ok "the bypass does not leak to ordinary code pushes"
fi
must git -C "$TMP/a" checkout -q main

run A --release feat/gated --me "$ME" --now "$NOW"
want 0 "--release also works through the hook (a deletion sends no tree)"

must rm -f "$GATEHOOK"

# --- could not tell must never read as free ---------------------------------
run A --acquire feat/z --now "$NOW"
want 2 "--acquire without --me is 2, not 0"

run A feat/x --me "$ME" --now 'not-a-timestamp'
want 2 "an invalid --now is 2, not 0"

# A missing perl is a MISSING TOOL, not a bad timestamp. Both exit 2, so the
# exit code cannot tell them apart and only the text can - and the text is an
# instruction, so getting it wrong sends the operator to fix a --now value that
# is already correct. Asserted BOTH ways: the tool message must appear and the
# timestamp message must not, or a script that printed both would pass.
PERLSHIM="$TMP/perlshim"
must mkdir -p "$PERLSHIM"
printf '#!/usr/bin/env bash\nexit 127\n' > "$PERLSHIM/perl"
must chmod +x "$PERLSHIM/perl"
OUT="$( ( cd "$TMP/a" && PATH="$PERLSHIM:$PATH" bash "$SCRIPT" feat/x --me "$ME" --now "$NOW" ) 2>&1 )"; ACTUAL=$?
want 2 "an unusable perl is 2, not 0"
case "$OUT" in
  *"needs perl"*) ok "an unusable perl is reported as a missing TOOL" ;;
  *)              bad "an unusable perl is reported as a missing TOOL" "got: $OUT" ;;
esac
case "$OUT" in
  *"not valid ISO-8601"*) bad "a missing tool is NOT blamed on the --now value" "got: $OUT" ;;
  *)                      ok "a missing tool is NOT blamed on the --now value" ;;
esac

run A feat/x --me "$ME" --now '2026-99-99T00:00:00Z'
want 2 "a calendar-invalid --now is 2, not 0"

# An unusable awk is could-not-tell too, and this is the one that bites hardest:
# swapping `grep -c . || true` for awk fixes the construct and leaves the
# fail-open direction it exists to close. With no awk the count is empty,
# `[ "$bot_n" -gt 0 ]` errors into the ELSE branch, and the script prints
# `free: '<b>' has  commit(s)` and exits 0 - a blank number inside the one
# verdict this script must never get wrong. feat/idfile carries only my own
# commits, so it reaches the counting path rather than stopping at the lease or
# at another author.
AWKSHIM="$TMP/awkshim"
must mkdir -p "$AWKSHIM"
printf '#!/usr/bin/env bash\nexit 127\n' > "$AWKSHIM/awk"
must chmod +x "$AWKSHIM/awk"
OUT="$( ( cd "$TMP/a" && PATH="$AWKSHIM:$PATH" bash "$SCRIPT" feat/idfile --me "$ME" --now "$NOW" ) 2>&1 )"; ACTUAL=$?
want 2 "an unusable awk is 2, not a free verdict with a blank count"
case "$OUT" in
  *"could not count"*) ok "an unusable awk is reported as a failed count" ;;
  *)                   bad "an unusable awk is reported as a failed count" "got: $OUT" ;;
esac
# The failure that would actually ship is a FREE verdict, so assert its absence
# directly rather than trusting the exit code alone to have moved.
case "$OUT" in
  *"free:"*) bad "an unusable awk does NOT print a free verdict" "got: $OUT" ;;
  *)         ok "an unusable awk does NOT print a free verdict" ;;
esac

# An awk that exits 0 and prints NOTHING is the harder half, and the exit-status
# check alone does not catch it: the assignment succeeds and the count is empty,
# which is the blank-number free verdict all over again. That is why count_lines
# checks the SHAPE of what it got as well as the status. Without this case the
# shape check is unproven - measured, the status check alone covers the shim
# above just fine.
printf '#!/usr/bin/env bash\nexit 0\n' > "$AWKSHIM/awk"
must chmod +x "$AWKSHIM/awk"
OUT="$( ( cd "$TMP/a" && PATH="$AWKSHIM:$PATH" bash "$SCRIPT" feat/idfile --me "$ME" --now "$NOW" ) 2>&1 )"; ACTUAL=$?
want 2 "an awk that exits 0 printing NOTHING is 2, not a blank count"
case "$OUT" in
  *"free:"*) bad "a silent awk does NOT print a free verdict" "got: $OUT" ;;
  *)         ok "a silent awk does NOT print a free verdict" ;;
esac

run A feat/x --me --quiet --now "$NOW"
want 2 "--me swallowing the next flag as its value is 2, not 0"

# A lease ref whose commit message is not a parseable marker is UNKNOWN. It is
# emphatically not "no lease": something put it there.
must git -C "$TMP/a" push -q --force origin HEAD:refs/claims/feat/garbled
run A feat/garbled --me "$ME" --now "$NOW"
want 2 "an unparseable lease marker is 2, not 0"

# An origin that cannot be reached at all.
must git clone -q "$ORIGIN" "$TMP/broken"
must git -C "$TMP/broken" config user.email "$EMAIL"
must git -C "$TMP/broken" remote set-url origin "$TMP/no-such-repo.git"
OUT="$( ( cd "$TMP/broken" && bash "$SCRIPT" feat/x --me "$ME" --now "$NOW" ) 2>&1 )"; ACTUAL=$?
want 2 "unreachable origin is 2, not 0"

OUT="$( ( cd "$TMP/broken" && bash "$SCRIPT" --acquire feat/x --me "$ME" --now "$NOW" ) 2>&1 )"; ACTUAL=$?
want 2 "unreachable origin under --acquire is 2, not 0"

# --- a refused lease push is not proof somebody beat us ---------------------
# On a takeover the CAS is pinned to the sha we read, so if the push fails and
# the ref STILL reads that same sha, nothing moved: the push failed for its own
# reasons. Reporting that as CLAIMED sends the operator to coordinate with a
# session that is not there. The "the network died, so the re-read would have
# failed too" argument does not hold - the push and the re-read are separate
# calls and only one has to fail, which is what this shim models.
must git -C "$TMP/a" push -q --force origin "$(rival_lease "$OTHER" "$NOW" 4):refs/claims/feat/pushfail"

SHIM5="$TMP/shim5"
must mkdir -p "$SHIM5"
cat > "$SHIM5/git" <<EOS5
#!/usr/bin/env bash
# Fail ONLY a push that targets this branch's lease ref. ls-remote and fetch
# name the same ref, so the subcommand has to be matched too, or the read side
# would break and the case would pass as an ordinary could-not-tell.
is_push=0; hits_ref=0
for a in "\$@"; do
  [ "\$a" = "push" ] && is_push=1
  case "\$a" in *refs/claims/feat/pushfail*) hits_ref=1 ;; esac
done
[ "\$is_push" = 1 ] && [ "\$hits_ref" = 1 ] && exit 1
exec "$REAL_GIT" "\$@"
EOS5
must chmod +x "$SHIM5/git"

OUT="$( ( cd "$TMP/a" && PATH="$SHIM5:$PATH" bash "$SCRIPT" --acquire feat/pushfail \
  --me "$ME" --harness claude-code --now "$EXPIRED" ) 2>&1 )"; ACTUAL=$?
want 2 "a lease push that fails while the lease does NOT move is 2, not CLAIMED"
case "$OUT" in
  *"has not moved"*) ok "the refusal says the push failed, not that someone holds it" ;;
  *)                 bad "the refusal says the push failed, not that someone holds it" "got: $OUT" ;;
esac
case "$OUT" in
  *"leased by another session"*) bad "a failed push is NOT reported as another session's lease" "got: $OUT" ;;
  *)                             ok "a failed push is NOT reported as another session's lease" ;;
esac

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
