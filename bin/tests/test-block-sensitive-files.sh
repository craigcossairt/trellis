#!/usr/bin/env bash
# =============================================================================
# test-block-sensitive-files.sh - behavioral tests for the sensitive-file hook
# =============================================================================
# This hook is the one that stops an agent writing to .env. Until this suite
# existed, nothing exercised it: hooks CI ran `bash -n` and shellcheck over it,
# which check that it parses and has no obvious shell smells, and say nothing
# about whether it blocks anything. A hook that no-ops looks exactly like a hook
# that passes.
#
# Four properties are pinned, and all four can fail in both directions:
#
#   1. Sensitive paths block (exit 2). Ordinary paths do not (exit 0). Testing
#      only the first half would let "block everything" pass, which is a broken
#      hook that happens to be safe.
#   2. It fails CLOSED on a payload it cannot parse, and OPEN on no payload at
#      all. Those are different situations - no stdin means this was not a hook
#      call; stdin that parses to nothing means the check could not run.
#   3. Every payload shape seen in the wild resolves: Claude Code's nested
#      snake_case, Grok's nested camelCase, Cursor's top-level key.
#   4. The two refusal messages are distinguishable, and the one a user acts on
#      says what to do. A message is an instruction, so its text is asserted.
#
# The jq branch and the sed fallback are BOTH exercised, because they do not
# agree: the fallback reads file_path/filePath only, so a payload that nests the
# path under another key parses with jq and fails closed without it. That
# asymmetry is real and pinned here rather than discovered later.
#
# Hermetic: no repo, no network, no temp git. Payloads are strings.
#
# Run:  bash bin/tests/test-block-sensitive-files.sh
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
HOOK="$ROOT/.claude/hooks/block-sensitive-files.sh"
HELPER="$ROOT/.claude/hooks/hook-file-path.sh"
for f in "$HOOK" "$HELPER"; do
  [ -f "$f" ] || { echo "missing $f" >&2; exit 1; }
done

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

# --- Build a PATH with jq removed, to exercise the sed fallback --------------
# Shadowing does not work: `command -v` resolves names, so a fake jq earlier in
# PATH is still found and the jq branch is still taken. jq has to be genuinely
# unreachable. Two strategies, because no single one is portable:
#
#   1. Drop every directory that contains a jq. Works where jq lives somewhere
#      of its own (a Windows package manager's shim directory). Useless on a
#      typical Linux box, where jq is in /usr/bin and dropping that takes sed,
#      grep and cat with it.
#   2. Build a directory of links to only the tools the fallback needs, and use
#      that as the whole PATH. Works on Linux; on Windows a copied bash cannot
#      find its DLLs, which is why strategy 1 exists.
#
# Each is VERIFIED before use - jq must be gone AND the tools must still work.
# An unverified strategy would run the fallback cases through jq and pass for
# the wrong reason, which is worse than not running them.
TMPBIN="$(mktemp -d 2>/dev/null || mktemp -d -t blocktest)"
trap 'rm -rf "$TMPBIN"' EXIT

usable() { # $1 candidate PATH -> jq absent and the fallback's tools present
  PATH="$1" command -v jq >/dev/null 2>&1 && return 1
  local t
  for t in bash sed grep head cat; do
    PATH="$1" command -v "$t" >/dev/null 2>&1 || return 1
  done
  return 0
}

NOJQ_PATH=""
if command -v jq >/dev/null 2>&1; then
  HAVE_JQ=1
  # Strategy 1: filter, recomputing from the CANDIDATE each pass. Recomputing
  # from the original PATH would keep finding the same directory and never walk
  # on to the second copy - which is exactly how this passed locally and failed
  # on a runner where /bin and /usr/bin both resolve jq.
  cand="$PATH"
  for _ in 1 2 3 4 5; do
    PATH="$cand" command -v jq >/dev/null 2>&1 || break
    d="$(cd "$(dirname "$(PATH="$cand" command -v jq)")" && pwd)"
    cand="$(printf '%s' "$cand" | tr ':' '\n' | grep -vxF "$d" | paste -sd: -)"
  done
  usable "$cand" && NOJQ_PATH="$cand"

  # Strategy 2: a directory of links to just what the fallback needs.
  if [ -z "$NOJQ_PATH" ]; then
    mkdir -p "$TMPBIN/bin"
    for t in bash sed grep head cat tr; do
      src="$(command -v "$t" 2>/dev/null)" || continue
      ln -sf "$src" "$TMPBIN/bin/$t" 2>/dev/null || cp "$src" "$TMPBIN/bin/$t" 2>/dev/null || true
    done
    usable "$TMPBIN/bin" && NOJQ_PATH="$TMPBIN/bin"
  fi

  if [ -z "$NOJQ_PATH" ]; then
    echo "FIXTURE FAILED: could not build a PATH with jq absent and sed/grep present." >&2
    echo "  The sed-fallback cases would have run through jq and passed for the wrong reason." >&2
    exit 1
  fi
else
  HAVE_JQ=0
fi
# The reverse fixture check: the jq cases must actually have jq.
if [ "$HAVE_JQ" -eq 0 ]; then
  echo "FIXTURE FAILED: jq is not installed, so the jq branch cannot be exercised." >&2
  echo "  Install jq, or run this suite where it is available. Skipping would report" >&2
  echo "  a suite that did not run as a suite that passed." >&2
  exit 1
fi

# --- Runner ------------------------------------------------------------------
RC=0; ERR=""
run() { # $1 payload, $2 optional PATH
  local path_override="${2:-$PATH}"
  ERR="$(printf '%s' "$1" | PATH="$path_override" bash "$HOOK" 2>&1 >/dev/null)"
  RC=$?
}

# Exact exit code, never "non-zero". A case that accepts any failure passes when
# the hook dies for an unrelated reason.
check() { # $1 name, $2 expected_rc, $3 payload, $4 optional PATH
  run "$3" "${4:-$PATH}"
  if [ "$RC" -eq "$2" ]; then ok "$1"; else bad "$1" "expected exit $2, got $RC (stderr: ${ERR:-none})"; fi
}

check_msg() { # $1 name, $2 payload, $3 must-match, $4 optional must-NOT-match
  run "$2"
  local why=""
  printf '%s' "$ERR" | grep -qiE "$3" || why="stderr did not match /$3/: ${ERR:-none}"
  if [ -n "${4:-}" ] && printf '%s' "$ERR" | grep -qiE "$4"; then
    why="stderr matched the forbidden /$4/: $ERR"
  fi
  if [ -z "$why" ]; then ok "$1"; else bad "$1" "$why"; fi
}

claude()  { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1"; }
grok()    { printf '{"toolName":"Edit","toolInput":{"filePath":"%s"}}' "$1"; }
cursor()  { printf '{"file_path":"%s"}' "$1"; }
nested()  { printf '{"tool_input":{"path":"%s"}}' "$1"; }

echo "== A. payload handling =="
check "no stdin at all is not a hook call (exit 0)"            0 ''
# Whitespace is NOT the same as nothing. The shipped guard is [ -n "$PAYLOAD" ],
# which a string of spaces passes, so a whitespace payload reaches the parser,
# resolves to no path, and fails closed. That is the correct side to land on -
# something was sent and could not be read - and it is pinned because the
# obvious "strip it and treat it as empty" tidy-up would turn it into exit 0.
check "whitespace-only payload fails CLOSED, not open"         2 '   '
check "payload with no path anywhere fails CLOSED"             2 '{"tool_name":"Edit","tool_input":{}}'
check "payload that is not JSON fails CLOSED"                  2 'not json at all'
check "empty string path fails CLOSED"                         2 "$(claude '')"

echo "== B. payload shapes all resolve =="
check "Claude shape: nested snake_case, sensitive"             2 "$(claude '.env')"
check "Claude shape: nested snake_case, ordinary"              0 "$(claude 'src/index.ts')"
check "Grok shape: nested camelCase, sensitive"                2 "$(grok '.env')"
check "Grok shape: nested camelCase, ordinary"                 0 "$(grok 'src/index.ts')"
check "Cursor shape: top-level key, sensitive"                 2 "$(cursor '.env')"
check "Cursor shape: top-level key, ordinary"                  0 "$(cursor 'src/index.ts')"
check "tool_input.path shape, ordinary"                        0 "$(nested 'src/index.ts')"

echo "== C. secrets block =="
for p in .env .env.local .ENV config/secrets.yml app.credentials.json server.pem \
         private.key github_pat_abc123.txt .ssh/id_rsa .ssh/id_ed25519; do
  check "blocks $p" 2 "$(claude "$p")"
done

echo "== D. lock files block =="
for p in package-lock.json pubspec.lock yarn.lock bun.lock Cargo.lock poetry.lock composer.lock; do
  check "blocks $p" 2 "$(claude "$p")"
done

echo "== E. generated files block =="
check "blocks api.generated.ts"  2 "$(claude 'api.generated.ts')"
check "blocks bundle.min.js"     2 "$(claude 'bundle.min.js')"
check "blocks styles.min.css"    2 "$(claude 'styles.min.css')"

echo "== F. ordinary files are allowed =="
# These are the cases that fail if someone widens a pattern. Each one is a near
# miss of a real pattern, so a rule that loses its anchor shows up here.
check "allows src/index.ts"            0 "$(claude 'src/index.ts')"
check "allows README.md"               0 "$(claude 'README.md')"
# Each of these CONTAINS a blocked pattern without ending in it, so it goes red
# the moment a `$` anchor is dropped. An unrelated name (keyboard.js, minify.js)
# looks like it tests the anchor and does not - it never matched in the first
# place, so it passes whatever the anchor does. Found by mutation, not by review.
check "allows config.keys.json (.key must END the path)"      0 "$(claude 'config.keys.json')"
check "allows yarn.lock.bak (lock patterns must END the path)" 0 "$(claude 'yarn.lock.bak')"
check "allows app.min.js.map (.min.js must END the path)"     0 "$(claude 'app.min.js.map')"
check "allows src/generated/foo.ts (pattern needs the dots)"  0 "$(claude 'src/generated/foo.ts')"
check "allows docs/env-setup.md"       0 "$(claude 'docs/env-setup.md')"

echo "== G. template carve-out =="
check "allows .env.example"        0 "$(claude '.env.example')"
# Deliberately a path that a block pattern WOULD match, so the case fails when
# the carve-out is removed. A neutral name like config.sample passes either way
# and proves nothing about the carve-out.
check "allows api.credentials.sample" 0 "$(claude 'api.credentials.sample')"
check "allows secrets.template (carve-out wins over the secrets rule)" 0 "$(claude 'secrets.template')"
check "still blocks .env.example.bak (carve-out is a suffix, not a substring)" 2 "$(claude '.env.example.bak')"

echo "== H. refusal messages are distinguishable and actionable =="
check_msg "pattern refusal names the category and says what to do" \
  "$(claude '.env')" 'sensitive, lock, or generated' 'could not parse'
check_msg "parse refusal says the check could not run, not that the file is sensitive" \
  '{"tool_input":{}}' 'could not parse' 'this is a sensitive'
check_msg "both refusals tell the user to confirm before editing" \
  "$(claude 'package-lock.json')" 'confirm with the user'
# One per payload shape. Exit 2 alone cannot tell "the path was read and matched
# a rule" from "the path could not be read at all", so without these a shape
# whose parsing breaks still shows green on its sensitive case. The message is
# the only place the two are distinguishable.
check_msg "Claude shape blocks on the RULE, not on a parse failure" \
  "$(claude '.env')" 'sensitive, lock, or generated' 'could not parse'
check_msg "Grok shape blocks on the RULE, not on a parse failure" \
  "$(grok '.env')" 'sensitive, lock, or generated' 'could not parse'
check_msg "Cursor shape blocks on the RULE, not on a parse failure" \
  "$(cursor '.env')" 'sensitive, lock, or generated' 'could not parse'

echo "== I. sed fallback (jq removed from PATH) =="
check "fallback: Claude shape, sensitive"   2 "$(claude '.env')"        "$NOJQ_PATH"
check "fallback: Claude shape, ordinary"    0 "$(claude 'src/index.ts')" "$NOJQ_PATH"
check "fallback: Cursor shape, sensitive"   2 "$(cursor '.env')"        "$NOJQ_PATH"
# Ordinary, not sensitive, on purpose. Exit 2 is what BOTH "recognized and
# blocked" and "could not parse, failed closed" produce, so a sensitive path
# here would pass whether or not the fallback resolves anything. Exit 0 can
# only happen if the path was actually read.
check "fallback: Grok camelCase resolves"   0 "$(grok 'src/index.ts')"  "$NOJQ_PATH"
check "fallback: no path still fails CLOSED" 2 '{"tool_input":{}}'      "$NOJQ_PATH"
# The documented asymmetry. With jq this parses and is allowed; without jq the
# fallback cannot see a path nested under `path`, so the hook refuses rather
# than waving an unchecked edit through. Both answers are correct; they differ,
# and that is the point of the pair.
check "tool_input.path resolves WITH jq"          0 "$(nested 'src/index.ts')"
check "tool_input.path fails CLOSED without jq"   2 "$(nested 'src/index.ts')" "$NOJQ_PATH"

echo "== J. a broken jq is not a free pass =="
# Reuses TMPBIN rather than taking its own temp dir: a second `trap ... EXIT`
# REPLACES the first, so the earlier directory would never be cleaned up.
BROKEN="$TMPBIN/brokenjq"; mkdir -p "$BROKEN"
printf '#!/bin/sh\nexit 1\n' > "$BROKEN/jq"; chmod +x "$BROKEN/jq"
# jq resolves but fails: the helper takes the jq branch, gets nothing back, and
# the hook must refuse rather than allow.
check "jq present but failing fails CLOSED" 2 "$(claude 'src/index.ts')" "$BROKEN:$NOJQ_PATH"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
