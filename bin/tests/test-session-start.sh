#!/usr/bin/env bash
# =============================================================================
# test-session-start.sh - behavioral tests for .claude/hooks/session-start.sh
# =============================================================================
# This hook looks like a pile of echoes, which is why it went unpinned. It is
# not: it picks its own root, branches on whether that root is a git repo, caps
# a list with arithmetic, and shells out to the installer that wires the real
# git pre-push hook. Each of those can break quietly, and the failure mode of a
# SessionStart hook is silence - you get a session with no context and nothing
# says so.
#
# What is pinned, and why each one matters:
#
#   1. It always exits 0. A session hook that fails takes the session's opening
#      context with it.
#   2. Both markers print, always, in and out of a git repo. They are how a
#      reader (and the model) knows the block is complete rather than truncated.
#   3. It honours CLAUDE_PROJECT_DIR and falls back to the working directory.
#      Getting this wrong reports another repo's state, which is worse than
#      reporting none - it is confidently wrong.
#   4. `.git` as a FILE is still a git repo. That is a linked worktree, which is
#      how this template tells you to do all branch work, so dropping that check
#      would blind the hook in the exact place it is most used.
#   5. The 15-line cap and its "... and N more" arithmetic, on both sides of the
#      boundary. An off-by-one here is invisible in ordinary use.
#   6. It self-heals the git hook wiring, and survives that installer being
#      absent.
#
# Hermetic: temp git repos, no network, global git config neutralised.
#
# Needs jq: the adapter cases read each reply with a JSON parser, the way the
# tool itself does. Without jq this stops here, before any case runs, rather
# than two thirds of the way through with no totals.
#
# Run:  bash bin/tests/test-session-start.sh
# =============================================================================
set -uo pipefail

command -v jq >/dev/null 2>&1 || {
  echo "FIXTURE FAILED: jq is needed to parse the adapter's replies (sections I and J)." >&2
  echo "  Skipping those cases would report replies nobody parsed as replies that parse." >&2
  exit 1
}

HERE="$(CDPATH='' cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
HOOK="$ROOT/.claude/hooks/session-start.sh"
INSTALLER="$ROOT/bin/install-git-hooks.sh"
for f in "$HOOK" "$INSTALLER"; do
  [ -f "$f" ] || { echo "missing $f" >&2; exit 1; }
done

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     %s\n' "$1" "$(printf '%s' "$2" | head -4 | tr '\n' '|')"; }
must() { "$@" >/dev/null 2>&1 || { echo "FIXTURE FAILED: $*" >&2; exit 1; }; }
# A fixture that yields an empty path must abort, not silently make `cd ""` a
# no-op that runs the hook against this repo. That is how the first draft of the
# cap cases "passed" against the wrong tree.
needdir() { [ -n "${1:-}" ] && [ -d "$1" ] || { echo "FIXTURE FAILED: empty or missing fixture dir" >&2; exit 1; }; }

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t sesstart)"
trap 'rm -rf "$TMP"' EXIT

new_repo() { # $1 dir -> an initialised repo with one commit
  must git init -q "$1"
  must git -C "$1" config user.email 'me@example.com'
  must git -C "$1" config user.name 'Me'
  must git -C "$1" config commit.gpgsign false
  must git -C "$1" config core.autocrlf false
  echo seed > "$1/seed.txt"
  must git -C "$1" add seed.txt
  must git -C "$1" commit -q -m 'seed commit'
}

OUT=""; RC=0
run() { # $1 dir to run in, $2 optional CLAUDE_PROJECT_DIR ("-" for unset)
  local dir="$1" proj="${2:--}"
  if [ "$proj" = "-" ]; then
    OUT="$(cd "$dir" && env -u CLAUDE_PROJECT_DIR bash "$HOOK" 2>&1)"
  else
    OUT="$(cd "$dir" && CLAUDE_PROJECT_DIR="$proj" bash "$HOOK" 2>&1)"
  fi
  RC=$?
}

# Assertion helpers, not `cond && ok || bad`: in that construct `bad` also runs
# when `ok` itself fails, so a bookkeeping slip turns into a phantom failure.
# SC2015 flags exactly that, and is right to.
#
# (Note the wording above: a comment whose first word is the linter's own name
# is read as a malformed directive, and it stops checking the rest of the file
# from that line on - fewer findings, which reads as a pass. Start such a line
# with any other word.)
has()    { printf '%s' "$OUT" | grep -qE "$1"; }
hasnot() { ! printf '%s' "$OUT" | grep -qE "$1"; }
c_has()    { if has "$2";    then ok "$1"; else bad "$1" "$OUT"; fi; }
c_hasnot() { if hasnot "$2"; then ok "$1"; else bad "$1" "$OUT"; fi; }
c_rc()     { if [ "$RC" -eq "$2" ]; then ok "$1"; else bad "$1" "exit $RC"; fi; }
c_eq()     { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got [$2] want [$3]"; fi; }

# --- Fixtures ----------------------------------------------------------------
REPO="$TMP/repo";      new_repo "$REPO"
must git -C "$REPO" checkout -q -b feature/widget
EMPTY="$TMP/plain";    mkdir -p "$EMPTY"       # not a git repo at all
OTHER="$TMP/other";    new_repo "$OTHER"
must git -C "$OTHER" checkout -q -b other/branch

echo "== A. it always completes =="
run "$REPO"
c_rc "exits 0 inside a git repo" 0
run "$EMPTY"
c_rc "exits 0 outside a git repo" 0

echo "== B. the block is always complete =="
run "$REPO"
c_has "prints the opening marker" '=== SESSION CONTEXT ==='
c_has "prints the closing marker" '=== END SESSION CONTEXT ==='
c_has "prints Quick References" 'Quick References'
run "$EMPTY"
c_has "opening marker outside a repo" '=== SESSION CONTEXT ==='
c_has "closing marker outside a repo" '=== END SESSION CONTEXT ==='
c_has "Quick References outside a repo" 'Quick References'
c_hasnot "no Git State section outside a repo" '## Git State'

echo "== C. git state =="
run "$REPO"
c_has "reports the current branch" 'Branch: feature/widget'
c_has "reports recent commits" 'seed commit'
c_hasnot "clean tree shows no changes block" 'Uncommitted changes'

echo "== D. it reads the root it was told to read =="
# The dangerous failure is not "no output" - it is reporting a DIFFERENT repo's
# branch, which reads as correct. So both directions are asserted by name.
run "$EMPTY" "$REPO"
c_has "CLAUDE_PROJECT_DIR wins over the working dir" 'Branch: feature/widget'
run "$OTHER" "$REPO"
c_has "reports the told root, not the cwd repo" 'Branch: feature/widget'
c_hasnot "does not leak the cwd repo's branch" 'Branch: other/branch'
run "$OTHER"
c_has "falls back to the working dir when unset" 'Branch: other/branch'

echo "== E. a linked worktree is still a git repo =="
# In a worktree, .git is a FILE containing a gitdir: pointer, not a directory.
# All branch work in this template happens in worktrees, so losing this check
# would blind the hook exactly where it is used most.
WT="$TMP/wt"
must git -C "$REPO" worktree add -q -b wt/branch "$WT"
[ -f "$WT/.git" ] || { echo "FIXTURE FAILED: expected .git to be a file in a worktree" >&2; exit 1; }
run "$WT"
c_has "worktree gets a Git State section" '## Git State'
c_has "worktree reports its own branch" 'Branch: wt/branch'

echo "== F. the uncommitted-changes cap =="
# Both sides of the boundary. An off-by-one here never shows up in normal use.
cap_repo() { # $1 count -> fresh repo with N untracked files at the root
  # Two statements on purpose: `local a="$1" b="$a"` does not reliably see `a`
  # in the same declaration, and under `set -u` that aborts the function and
  # returns an empty path - which made `run ""` fall back to the real repo and
  # assert against this checkout instead of the fixture.
  local n="$1"
  local d="$TMP/cap$n"
  rm -rf "$d"; new_repo "$d"
  local i=1
  while [ "$i" -le "$n" ]; do : > "$d/file$i.txt"; i=$((i + 1)); done
  printf '%s' "$d"
}
D="$(cap_repo 3)"; needdir "$D"; run "$D"
c_has "3 changes: shows the changes block" 'Uncommitted changes'
c_hasnot "3 changes: no overflow line" 'more files'

D="$(cap_repo 15)"; needdir "$D"; run "$D"
c_hasnot "15 changes: exactly at the cap, no overflow line" 'more files'
c_eq "15 changes: all 15 listed" "$(printf '%s' "$OUT" | grep -cE '^\?\? file[0-9]+\.txt$')" 15

D="$(cap_repo 16)"; needdir "$D"; run "$D"
c_has "16 changes: reports exactly 1 more" 'and 1 more'
c_eq "16 changes: list is capped at 15" "$(printf '%s' "$OUT" | grep -cE '^\?\? file[0-9]+\.txt$')" 15

D="$(cap_repo 20)"; needdir "$D"; run "$D"
c_has "20 changes: reports exactly 5 more" 'and 5 more'

echo "== G. it self-heals the git hook wiring =="
SH_REPO="$TMP/selfheal"; new_repo "$SH_REPO"
must mkdir -p "$SH_REPO/bin" "$SH_REPO/.githooks"
must cp "$INSTALLER" "$SH_REPO/bin/install-git-hooks.sh"
: > "$SH_REPO/.githooks/pre-push"
[ -z "$(git -C "$SH_REPO" config --get core.hooksPath || true)" ] \
  || { echo "FIXTURE FAILED: core.hooksPath was already set" >&2; exit 1; }
run "$SH_REPO"
c_eq "wires core.hooksPath when unset" "$(git -C "$SH_REPO" config --get core.hooksPath || true)" ".githooks"

# With no argument the installer finds its repo from its OWN location. Run by a
# RELATIVE path with CDPATH exported, `cd bin` resolves through CDPATH and
# echoes the directory, so an unguarded `$(cd "$(dirname ...)" && pwd)` capture
# held two lines, the repo root could not be resolved, and nothing was wired -
# silently, since the installer exits 0 on a repo it cannot find. The case above
# goes through session-start, which passes the repo explicitly.
REL_REPO="$TMP/relative-installer"; new_repo "$REL_REPO"
must mkdir -p "$REL_REPO/bin" "$REL_REPO/.githooks"
must cp "$INSTALLER" "$REL_REPO/bin/install-git-hooks.sh"
: > "$REL_REPO/.githooks/pre-push"
( cd "$REL_REPO" && CDPATH=. bash bin/install-git-hooks.sh >/dev/null 2>&1 )
c_eq "relative + CDPATH=. with no argument still wires its own repo" \
  "$(git -C "$REL_REPO" config --get core.hooksPath || true)" ".githooks"

# Run from inside a git hook (or `git rebase --exec`), the session inherits
# GIT_DIR, GIT_WORK_TREE and GIT_INDEX_FILE, and `git -C` does not override
# them. Aimed here at a SENTINEL repo: unisolated, the Git State section prints
# the sentinel's branch, and the installer wires the sentinel and leaves the
# session's own repo with no pre-push hook and no message.
SENT="$TMP/env-sentinel"; new_repo "$SENT"
must git -C "$SENT" checkout -q -b sentinel-branch
ENV_REPO="$TMP/env-session"; new_repo "$ENV_REPO"
must git -C "$ENV_REPO" checkout -q -b session-branch
must mkdir -p "$ENV_REPO/bin" "$ENV_REPO/.githooks"
must cp "$INSTALLER" "$ENV_REPO/bin/install-git-hooks.sh"
: > "$ENV_REPO/.githooks/pre-push"
OUT="$(cd "$ENV_REPO" && GIT_DIR="$SENT/.git" GIT_WORK_TREE="$SENT" GIT_INDEX_FILE="$SENT/.git/index" \
  CLAUDE_PROJECT_DIR="$ENV_REPO" bash "$HOOK" 2>&1)"; RC=$?
c_has    "inherited GIT_DIR: Git State names the session's branch" 'Branch: session-branch'
c_hasnot "inherited GIT_DIR: Git State does not name the sentinel's branch" 'sentinel-branch'
c_eq "inherited GIT_DIR: the session's repo is wired" \
  "$(git -C "$ENV_REPO" config --get core.hooksPath || true)" ".githooks"
c_eq "inherited GIT_DIR: the sentinel repo is left alone" \
  "$(git -C "$SENT" config --get core.hooksPath || true)" ""

# The installer isolates itself too, since it is also run on its own.
INST_REPO="$TMP/env-installer"; new_repo "$INST_REPO"
must mkdir -p "$INST_REPO/bin" "$INST_REPO/.githooks"
must cp "$INSTALLER" "$INST_REPO/bin/install-git-hooks.sh"
: > "$INST_REPO/.githooks/pre-push"
( GIT_DIR="$SENT/.git" GIT_WORK_TREE="$SENT" GIT_INDEX_FILE="$SENT/.git/index" \
  bash "$INST_REPO/bin/install-git-hooks.sh" "$INST_REPO" >/dev/null 2>&1 )
c_eq "installer under an inherited GIT_DIR wires the repo it was given" \
  "$(git -C "$INST_REPO" config --get core.hooksPath || true)" ".githooks"
c_eq "installer under an inherited GIT_DIR leaves the sentinel alone" \
  "$(git -C "$SENT" config --get core.hooksPath || true)" ""

# An installer someone deleted during the prune step must not break the session.
NOINST="$TMP/noinstaller"; new_repo "$NOINST"
run "$NOINST"
c_rc "survives a missing installer" 0
c_has "still completes with no installer" '=== END SESSION CONTEXT ==='

echo "== H. the project brain: stale, or its last refresh failed =="
# A scheduled refresh fails where nobody is looking, so this section is the
# alarm. Ages are set with `touch -t` on the stamp file: the hook reads the
# file's modification time, never the date written inside it.
brain_repo() { # $1 name -> a repo with brain/ but no stamp
  local d="$TMP/brain-$1"
  rm -rf "$d"; new_repo "$d"
  must mkdir -p "$d/brain"
  printf '%s' "$d"
}
run_env() { # $1 dir, then VAR=value pairs for the hook's environment
  local dir="$1"; shift
  OUT="$(cd "$dir" && env -u CLAUDE_PROJECT_DIR "$@" bash "$HOOK" 2>&1)"
  RC=$?
}

D="$(brain_repo never)"; needdir "$D"; run "$D"
c_hasnot "brain never set up: no brain section" 'Project brain'

D="$(brain_repo fresh)"; needdir "$D"
echo "2026-01-01T00:00:00Z" > "$D/brain/.last-ingest"
run "$D"
c_hasnot "ingested just now: no brain section" 'Project brain'

D="$(brain_repo old)"; needdir "$D"
echo "2020-01-01T00:00:00Z" > "$D/brain/.last-ingest"
must touch -t 202001010000 "$D/brain/.last-ingest"
run "$D"
c_has "ingested years ago: says the brain is stale" '## Project brain is stale'
c_has "stale: shows the recorded ingest date" 'Last ingest: 2020-01-01T00:00:00Z'
c_has "stale: names the refresh command" 'bash brain/scripts/refresh\.sh'
# This text lands in the agent's context at the top of every stale session. An
# imperative there ("schedule that line") reads as an instruction, and creating
# a scheduled job on someone's computer is theirs to say yes to.
c_has "stale: tells the agent to ask before scheduling anything" 'Do not create a scheduled job without asking'
c_hasnot "stale: no bare instruction to schedule it" 'Schedule that line'
c_rc  "stale: still exits 0" 0
c_has "stale: the block still closes" '=== END SESSION CONTEXT ==='

run_env "$D" PROJECT_BRAIN_STALE_DAYS=99999
c_hasnot "threshold raised past the file's age: not stale" 'Project brain'
run_env "$D" PROJECT_BRAIN_STALE_DAYS=0
c_hasnot "threshold 0 turns the staleness line off" 'Project brain'
run_env "$D" PROJECT_BRAIN_STALE_DAYS=soon
c_has "a threshold that is not a number falls back to the default" '## Project brain is stale'
run_env "$D" PROJECT_BRAIN_DISABLE=1
c_hasnot "the brain's kill switch silences the section" 'Project brain'
# 08 and 09 are not octal numbers. Read as one, the threshold is an arithmetic
# error and the staleness line is lost with nothing on screen to say why.
run_env "$D" PROJECT_BRAIN_STALE_DAYS=08
c_has "a threshold written 08 is eight days, and the line still prints" '08? or more days ago|8 or more days ago'
c_hasnot "a threshold written 08 is not an arithmetic error" 'too great for base'

# Both sides of the threshold, an hour or two out. The two ages every other
# case uses (now, and 2020) are both far from it, so an off-by-one-day in the
# comparison passed them all.
hours_ago() { # $1 hours -> a `touch -t` stamp that far back (GNU date, then BSD)
  date -d "$1 hours ago" '+%Y%m%d%H%M' 2>/dev/null || date -v "-${1}H" '+%Y%m%d%H%M'
}
D="$(brain_repo edge)"; needdir "$D"
echo "2026-01-01T00:00:00Z" > "$D/brain/.last-ingest"
must touch -t "$(hours_ago 166)" "$D/brain/.last-ingest"
run "$D"
c_hasnot "ingested 6 days 22 hours ago: not stale yet" 'Project brain'
must touch -t "$(hours_ago 170)" "$D/brain/.last-ingest"
run "$D"
c_has "ingested 7 days 2 hours ago: stale" '## Project brain is stale'

D="$(brain_repo failed)"; needdir "$D"
echo "2026-01-01T00:00:00Z" > "$D/brain/.last-ingest"
printf '2026-03-01 09:00 - the ingest step failed (exit 1).
second line
' > "$D/brain/.refresh-failed"
run "$D"
c_has "failure marker: says the refresh FAILED" '## Project brain: the last refresh FAILED'
c_has "failure marker: prints its first line" 'the ingest step failed'
c_hasnot "failure marker: prints only the first line" 'second line'
c_has "failure marker: the block still closes" '=== END SESSION CONTEXT ==='

# The marker's text goes straight into the session's context, so it is cut to
# printable characters and to 200 of them. A terminal escape or a megabyte of
# output in that file is otherwise the first thing every session reads.
D="$(brain_repo dirty)"; needdir "$D"
echo "2026-01-01T00:00:00Z" > "$D/brain/.last-ingest"
printf '2026-03-01 09:00 - bad \033[31mred\033[0m %s\n' "$(printf 'x%.0s' 1 2 3 4 5 6 7 8 9 10)$(head -c 300 /dev/zero | tr '\0' 'y')" > "$D/brain/.refresh-failed"
run "$D"
case "$OUT" in
  *"$(printf '\033')"*) bad "failure marker: escape characters are stripped" "$(printf '%s' "$OUT" | cat -v | grep bad)" ;;
  *) ok "failure marker: escape characters are stripped" ;;
esac
MLINE="$(printf '%s\n' "$OUT" | grep '2026-03-01 09:00 - bad')"
if [ "${#MLINE}" -ge 150 ] && [ "${#MLINE}" -le 200 ]; then ok "failure marker: a long line is cut at 200 characters"
else bad "failure marker: a long line is cut at 200 characters" "length ${#MLINE}"; fi

# A marker left behind in a tree whose brain was never set up means nothing:
# refresh.sh cannot have written it there.
D="$(brain_repo orphan)"; needdir "$D"
echo "stray" > "$D/brain/.refresh-failed"
run "$D"
c_hasnot "marker without a set-up brain: no brain section" 'Project brain'

# Both at once: the failure is the cause, so it is the one reported.
D="$(brain_repo both)"; needdir "$D"
echo "2020-01-01T00:00:00Z" > "$D/brain/.last-ingest"
must touch -t 202001010000 "$D/brain/.last-ingest"
echo "2020-01-02 09:00 - the index step failed (exit 3)." > "$D/brain/.refresh-failed"
run "$D"
c_has "stale and failed: reports the failure" 'the last refresh FAILED'
c_hasnot "stale and failed: not also the staleness line" 'Project brain is stale'

echo "== I. through the Cursor and Grok adapter =="
# Neither tool reads this hook's plain stdout. Cursor takes the text from an
# `additional_context` field; Grok reads only a top-level `systemMessage` from
# a SessionStart hook's reply and ignores anything else. Printed raw, the block
# reaches nobody and nothing says so: the hook ran, exited 0, and the session
# opened without it. The adapter derives its root from its own location, so it
# is copied into a throwaway repo beside a copy of the hook.
ADAPTER="$ROOT/bin/run-claude-hook.sh"
[ -f "$ADAPTER" ] || { echo "missing $ADAPTER" >&2; exit 1; }
ADP="$TMP/adapter"; new_repo "$ADP"
must mkdir -p "$ADP/bin" "$ADP/.claude/hooks"
must cp "$ADAPTER" "$ADP/bin/run-claude-hook.sh"
must cp "$HOOK" "$ADP/.claude/hooks/session-start.sh"
# A commit subject holding the two characters a JSON string must escape. The
# hook prints recent subjects, so they land inside the reply.
must git -C "$ADP" commit -q --allow-empty -m 'say "hi" to C:\dir'
AOUT=""; ARC=0
adapter() { # $1 harness, $2 optional repo (default: the real hook's)
  AOUT="$(cd "${2:-$ADP}" && printf '{}' | bash bin/run-claude-hook.sh "$1" session-start 2>/dev/null)"
  ARC=$?
}
one_line() { [ "$(printf '%s\n' "$AOUT" | wc -l | tr -d ' ')" = 1 ]; }
# The reply is read by a JSON parser in the tool, so one reads it here (jq,
# checked for at the top of this file). A match on how the text starts and
# ends passes a reply no parser accepts.
parses() { printf '%s' "$AOUT" | jq -e "$1" >/dev/null 2>&1; } # $1 a jq test that must hold
c_parses() { if parses "$2"; then ok "$1"; else bad "$1" "$AOUT"; fi; }
HELD='contains("=== END SESSION CONTEXT ===") and contains("say \"hi\" to C:\\dir")'

adapter grok
c_eq "grok: the adapter exits 0" "$ARC" 0
case "$AOUT" in
  '{"systemMessage":"'*'"}') ok "grok: the reply is one object with a top-level systemMessage" ;;
  *) bad "grok: the reply is one object with a top-level systemMessage" "$AOUT" ;;
esac
case "$AOUT" in
  *'=== SESSION CONTEXT ==='*'=== END SESSION CONTEXT ==='*) ok "grok: the whole block is inside it, both markers" ;;
  *) bad "grok: the whole block is inside it, both markers" "$AOUT" ;;
esac
if one_line; then ok "grok: newlines are escaped (one line of JSON)"
else bad "grok: newlines are escaped (one line of JSON)" "$AOUT"; fi
c_parses "grok: the reply parses, and systemMessage holds the block and a quoted subject" \
  ".systemMessage | $HELD"

adapter cursor
c_eq "cursor: the adapter exits 0" "$ARC" 0
case "$AOUT" in
  '{"additional_context":"'*'"}') ok "cursor: the reply carries additional_context" ;;
  *) bad "cursor: the reply carries additional_context" "$AOUT" ;;
esac
if one_line; then ok "cursor: newlines are escaped (one line of JSON)"
else bad "cursor: newlines are escaped (one line of JSON)" "$AOUT"; fi
c_parses "cursor: the reply parses, and additional_context holds the block and a quoted subject" \
  ".additional_context | $HELD"

# The same adapter over a stub hook whose text is known to the byte: a tab, a
# carriage return, a line break, a quote and a backslash. With jq the text must
# come back exactly. Without jq the adapter flattens it by hand, and there a
# tab or a carriage return left in place is a raw control character inside a
# JSON string - a reply no parser accepts, on exactly the machines (a bare
# Windows, a minimal container) where nobody would think to look.
STUB="$TMP/stub"
must mkdir -p "$STUB/bin" "$STUB/.claude/hooks"
must cp "$ADAPTER" "$STUB/bin/run-claude-hook.sh"
cat > "$STUB/.claude/hooks/session-start.sh" <<'STUBHOOK'
#!/bin/bash
printf 'one\ttab\r\nq"uote back\\slash\n'
STUBHOOK

adapter grok "$STUB"
# The carriage return is left out of the comparison: a native Windows jq reads
# its input as text and drops the CR of a CR-LF pair before the adapter's
# filter sees it. Everything else must come back to the byte.
c_parses "grok, with jq: the text comes back as written (tab, line break, quote, backslash)" \
  '(.systemMessage | gsub("\r"; "")) == "one\ttab\nq\"uote back\\slash"'

# The prompt hook through the same adapter. Cursor's schema for it is
# {"continue": bool} and carries no context, so the adapter always answers
# with that. Grok discards whatever an allowing prompt hook prints, so nothing
# is printed for it.
must mkdir -p "$STUB/brain/hooks"
cat > "$STUB/brain/hooks/context-enrichment.sh" <<'STUBHOOK'
#!/bin/bash
printf 'context from the brain\n'
STUBHOOK
AOUT="$(cd "$STUB" && printf '{}' | bash bin/run-claude-hook.sh cursor brain-enrich 2>/dev/null)"; ARC=$?
c_eq "cursor prompt hook: the reply is exactly the continue object" "$AOUT" '{"continue":true}'
c_eq "cursor prompt hook: exit 0" "$ARC" 0
# Exit 2 from a prompt hook blocks the prompt in Grok, and an empty reply looks
# the same whether the adapter ran and stayed silent or never ran. The Cursor
# case above proves the stub was reached; the exit status proves this one
# ended as an allow.
AOUT="$(cd "$STUB" && printf '{}' | bash bin/run-claude-hook.sh grok brain-enrich 2>/dev/null)"; ARC=$?
c_eq "grok prompt hook: nothing is printed" "$AOUT" ''
c_eq "grok prompt hook: exit 0" "$ARC" 0

# A PATH with jq gone and the adapter's other tools still there, built the way
# test-block-sensitive-files.sh builds its own and verified before use: first
# by dropping jq's directory, then by a directory of links to just these tools.
ADAPTER_TOOLS="bash cat mktemp rm tr sed dirname"
nojq_usable() { # $1 candidate PATH -> jq absent and every tool present
  PATH="$1" command -v jq >/dev/null 2>&1 && return 1
  local t
  for t in $ADAPTER_TOOLS; do
    PATH="$1" command -v "$t" >/dev/null 2>&1 || return 1
  done
  return 0
}
NOJQ_PATH=""; cand="$PATH"
for _ in 1 2 3 4 5; do
  PATH="$cand" command -v jq >/dev/null 2>&1 || break
  d="$(CDPATH='' cd -- "$(dirname "$(PATH="$cand" command -v jq)")" >/dev/null && pwd)"
  cand="$(printf '%s' "$cand" | tr ':' '\n' | grep -vxF "$d" | paste -sd: -)"
done
nojq_usable "$cand" && NOJQ_PATH="$cand"
if [ -z "$NOJQ_PATH" ]; then
  must mkdir -p "$TMP/nojq-bin"
  for t in $ADAPTER_TOOLS; do
    src="$(command -v "$t" 2>/dev/null)" || continue
    ln -sf "$src" "$TMP/nojq-bin/$t" 2>/dev/null || cp "$src" "$TMP/nojq-bin/$t" 2>/dev/null || true
  done
  nojq_usable "$TMP/nojq-bin" && NOJQ_PATH="$TMP/nojq-bin"
fi
[ -n "$NOJQ_PATH" ] || {
  echo "FIXTURE FAILED: could not build a PATH with jq absent and the adapter's tools present." >&2
  echo "  The no-jq case would have run through jq and passed for the wrong reason." >&2
  exit 1
}
AOUT="$(cd "$STUB" && printf '{}' | PATH="$NOJQ_PATH" bash bin/run-claude-hook.sh cursor session-start 2>/dev/null)"
c_parses "cursor, without jq: the flattened text is still JSON (each control character a space)" \
  '.additional_context == "one tab  q\"uote back\\slash"'

echo "== J. the adapter and a sensitive-file check that did not run =="
# Both tools' hook files mark the sensitive-file check failClosed. That setting
# covers the adapter failing to start. Once the adapter is running, what it
# prints IS the answer, so an adapter that printed "allow" for a check that
# crashed would undo the setting from the inside. It allows an edit only when
# the check finished and said yes (exit 0). A check that is missing, or that
# ends any other way than 0 or 2, comes back as a refusal that says so.
# The other hooks stay open: a session must still start.
check_stub() { # $1 the body of a stand-in for the sensitive-file check
  printf '#!/bin/bash\ncat >/dev/null\n%s\n' "$1" > "$STUB/.claude/hooks/block-sensitive-files.sh"
}
AERR=""
guard() { # $1 harness -> AOUT, ARC, AERR for one edit sent through the check
  AOUT="$(cd "$STUB" && printf '{"file_path":"src/a.ts"}' | bash bin/run-claude-hook.sh "$1" block-sensitive-files 2>"$TMP/guard.err")"
  ARC=$?
  AERR="$(cat "$TMP/guard.err")"
}

check_stub 'exit 0'
guard cursor
c_parses "cursor: a check that says yes -> allow" '.permission == "allow"'
c_eq "cursor: and the adapter exits 0" "$ARC" 0
guard grok
c_parses "grok: a check that says yes -> allow" '.decision == "allow"'

check_stub 'echo "no: that is a secret" >&2; exit 2'
guard cursor
c_parses "cursor: a check that says no -> deny, with the check's own reason" \
  '.permission == "deny" and (.user_message | contains("that is a secret"))'
c_eq "cursor: and the adapter exits 2" "$ARC" 2
c_parses "cursor: and a refusal by the check is not reported as a check that failed to run"   '.user_message | contains("did not finish") | not'

for rc in 1 127; do
  check_stub "exit $rc"
  guard cursor
  c_parses "cursor: a check that ends with exit $rc -> deny, and the reply says it did not finish" \
    ".permission == \"deny\" and (.user_message | contains(\"did not finish (exit $rc)\"))"
  c_eq "cursor: exit $rc from the check -> the adapter exits 2" "$ARC" 2
done
check_stub 'echo "jq: command not found" >&2; exit 1'
guard grok
c_parses "grok: a check that ends with exit 1 -> deny, with what the check printed" \
  '.decision == "deny" and (.reason | contains("did not finish (exit 1)")) and (.reason | contains("jq: command not found"))'
c_eq "grok: and the adapter exits 2" "$ARC" 2

check_stub 'kill -9 $$'
guard cursor
c_parses "cursor: a check that is killed -> deny" '.permission == "deny"'

must rm -f "$STUB/.claude/hooks/block-sensitive-files.sh"
guard cursor
c_parses "cursor: the check's file is missing -> deny, and the reply says it is missing" \
  '.permission == "deny" and (.user_message | contains("is missing"))'
c_eq "cursor: and the adapter exits 2" "$ARC" 2
case "$AERR" in
  *"was refused"*) ok "cursor: and the reason is on stderr as well" ;;
  *) bad "cursor: and the reason is on stderr as well" "$AERR" ;;
esac
guard grok
c_parses "grok: the check's file is missing -> deny" '.decision == "deny"'

# What stays open. A session hook that crashes, or is not there, must not stop
# the session from starting, and a format hook that is not there formats
# nothing.
cat > "$STUB/.claude/hooks/session-start.sh" <<'STUBHOOK'
#!/bin/bash
exit 3
STUBHOOK
adapter cursor "$STUB"
c_eq "cursor: a session hook that crashes -> the adapter still exits 0" "$ARC" 0
c_eq "cursor: and nothing is printed" "$AOUT" ''
must rm -f "$STUB/.claude/hooks/session-start.sh"
adapter grok "$STUB"
c_eq "grok: a session hook that is missing -> the adapter exits 0" "$ARC" 0
c_eq "grok: and nothing is printed" "$AOUT" ''
AOUT="$(cd "$STUB" && printf '{}' | bash bin/run-claude-hook.sh cursor format-on-edit 2>/dev/null)"; ARC=$?
c_eq "cursor: a format hook that is missing -> exit 0, nothing printed" "$ARC|$AOUT" '0|'

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
