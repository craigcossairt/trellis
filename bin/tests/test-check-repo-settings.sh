#!/usr/bin/env bash
# =============================================================================
# test-check-repo-settings.sh - behavioral tests for bin/check-repo-settings.sh
# =============================================================================
# The script reads a GitHub repository's safety settings and says which are
# off. Four ways it can lie, and each is pinned here:
#
#   1. It says ON for something it could not read. An API error, a missing
#      field or a missing `gh` must come out UNKNOWN and exit 2, never ON and
#      never a silent skip. Unknown must not resolve to green. That includes a
#      403: GitHub answers 403 both when a plan does not offer a feature and
#      when a token may not read it, and only the first is a SKIP.
#   2. It says OFF for something that is on by another route. A default branch
#      covered by a ruleset has no classic branch protection, and the reverse.
#   3. It says ON for protection that protects nothing. A classic protection
#      that allows force pushes, a ruleset whose only rule asks for a review,
#      or a ruleset with somebody on its bypass list leaves the branch open.
#      So does a rule the script never read: GitHub hands rules out a page at
#      a time, and a first page with no blocking rule says nothing about the
#      second.
#   4. It changes something. The script is read-only: every `gh api` call it
#      makes is a GET. The fake `gh` below answers only the two read shapes
#      the script uses and records anything else, and the last case fails if
#      one was ever made.
#
# The fake `gh` answers by API path from a JSON body and runs the script's own
# `--jq` expression over it with the real `jq`, so the expressions are
# exercised here. It pages a list the way GitHub does: 30 entries unless
# `per_page` asks for more, and `page=N` is the Nth slice. The
# classic-protection and rules bodies are cut down from real GitHub responses.
#
# WHAT THIS SUITE DOES NOT PROVE. `gh` evaluates `--jq` with its built-in
# gojq, not with `jq`, and the two are not the same program. One difference is
# known, and the fake copies it: gh prints a null result as an empty line where
# `jq -r` prints the word null (seen with a real `gh api` call, 2026-11-13).
# Every expression the script sends turns null into a word of its own before
# printing, except two single-field reads, which take anything but their two
# known values as UNKNOWN. That the two programs agree on the rest is an
# assumption, not a result. The ruleset body (its bypass list) is written from
# GitHub's API reference, as are the bodies not named above. Both halves are
# checked by running the script against a real repository (it is read-only, so
# that is safe); the PR that added it records such a run.
#
# Hermetic: a fake `gh` on PATH, temp dirs, no network. Needs `jq`.
#
# Run:  bash bin/tests/test-check-repo-settings.sh
# =============================================================================
set -uo pipefail

HERE="$(CDPATH='' cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SCRIPT="$ROOT/bin/check-repo-settings.sh"
[ -f "$SCRIPT" ] || { echo "missing $SCRIPT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "this suite needs jq on PATH (the fake gh runs the script's --jq expressions with it)" >&2; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     %s\n' "$1" "$(printf '%s' "$2" | head -6 | tr '\n' '|')"; }

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t reposettings)"
trap 'rm -rf "$TMP"' EXIT

# --- the fake gh --------------------------------------------------------------
# Fixture layout, under $GH_FIX:
#   repo-view            body for `gh repo view` (absent -> exit 1)
#   api/<path>           one file per API path, `/` written as `__`
#                        line 1: HTTP status (200, 204, 403, 404, 500)
#                        rest:   for a 2xx, the JSON body; `--jq EXPR` is run
#                                over it with jq -r, as gh does
#                                for anything else, the message gh would print
#   DISALLOWED           appended to on any call that is not one of the two
#                        read shapes the script may send (see the fake)
#   REPO_VIEW_CWD        the directory `gh repo view` was run from
#   CALLS                every invocation, one line each
# jq on Windows writes CRLF; gh does not, so the fake strips the CR.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_FIX/CALLS"
# An allow-list, not a list of write flags. The script may send two shapes:
#   gh repo view --json nameWithOwner --jq .nameWithOwner
#   gh api <path> [--jq <expr>]
# Anything else is recorded, whatever it is. A list of flags to refuse misses
# every spelling it did not think of: `--method=PUT`, `-XPUT`, `--raw-field`,
# and any other subcommand (`gh repo edit ...`) all walked past the first
# version of this fake with every case green.
allowed=0
if [ $# -eq 6 ] && [ "$1" = repo ] && [ "$2" = view ] && [ "$3" = --json ] \
   && [ "$4" = nameWithOwner ] && [ "$5" = --jq ] && [ "$6" = .nameWithOwner ]; then allowed=1; fi
if [ "${1:-}" = api ]; then
  case $# in
    2) allowed=1 ;;
    4) [ "$3" = --jq ] && allowed=1 ;;
  esac
  case "${2:-}" in ''|-*) allowed=0 ;; esac
fi
[ "$allowed" -eq 1 ] || printf '%s\n' "$*" >> "$GH_FIX/DISALLOWED"
if [ "${1:-}" = repo ] && [ "${2:-}" = view ]; then
  pwd > "$GH_FIX/REPO_VIEW_CWD"
  [ -f "$GH_FIX/repo-view" ] || { echo "gh: no git remotes found" >&2; exit 1; }
  cat "$GH_FIX/repo-view"; exit 0
fi
if [ "${1:-}" = api ]; then
  path="${2:-}"; expr=""
  shift 2
  while [ $# -gt 0 ]; do
    case "$1" in --jq) expr="${2:-}"; shift 2 ;; *) shift ;; esac
  done
  # GitHub pages a list: 30 entries unless per_page says otherwise, and
  # page=N is the Nth slice. The fixture holds the whole list and the fake
  # cuts it the same way, so a script that reads one page sees one page.
  query=""; per=30; page=1
  case "$path" in *\?*) query="${path#*\?}"; path="${path%%\?*}" ;; esac
  case "&$query" in *"&per_page="*) per="&$query"; per="${per##*&per_page=}"; per="${per%%&*}" ;; esac
  case "&$query" in *"&page="*) page="&$query"; page="${page##*&page=}"; page="${page%%&*}" ;; esac
  case "$per$page" in ''|*[!0-9]*) echo "fake gh: cannot read the query '$query'" >&2; exit 64 ;; esac
  key=$(printf '%s' "$path" | sed 's|/|__|g')
  f="$GH_FIX/api/$key"
  [ -f "$f" ] || { echo "gh: fixture missing for $path (HTTP 500)" >&2; exit 1; }
  status=$(head -n 1 "$f")
  rest=$(tail -n +2 "$f")
  case "$status" in
    2*)
      if [ -n "$expr" ] && [ -n "$rest" ]; then
        # The last sed is gh's one known difference from jq -r: a null result
        # is printed as an empty line, not as the word null.
        printf '%s\n' "$rest" \
          | jq -r "(if type == \"array\" then .[$(( (page - 1) * per )):$(( page * per ))] else . end) | ($expr)" \
          | tr -d '\r' | sed 's/^null$//'
        exit "${PIPESTATUS[1]}"
      fi
      printf '%s' "$rest"; [ -n "$rest" ] && echo
      exit 0 ;;
    403) echo "gh: ${rest:-Forbidden} (HTTP 403)" >&2; exit 1 ;;
    404) echo "gh: ${rest:-Not Found} (HTTP 404)" >&2; exit 1 ;;
    *)   echo "gh: ${rest:-Server Error} (HTTP $status)" >&2; exit 1 ;;
  esac
fi
echo "fake gh: unhandled: $*" >&2; exit 64
FAKE
chmod +x "$TMP/bin/gh"

# --- fixtures -------------------------------------------------------------------
N=0
FIX=""; PROJ=""
PLAN='Upgrade to GitHub Pro or make this repository public to enable this feature.'
ALERTS_OFF='Vulnerability alerts are disabled.'
DENIED='Resource not accessible by personal access token'
UNPROTECTED='Branch not protected'
api() { # $1 path, $2 status, $3 optional body (2xx) or message (anything else)
  local key; key=$(printf '%s' "$1" | sed 's|/|__|g')
  { printf '%s\n' "$2"; [ $# -ge 3 ] && printf '%s\n' "$3"; } > "$FIX/api/$key"
  return 0
}
unapi() { local key; key=$(printf '%s' "$1" | sed 's|/|__|g'); rm -f "$FIX/api/$key"; }
# The repository body, as GitHub returns it to an admin. "none none" gives a
# null security block, which is what a real private repository on a plan
# without secret scanning returned (read 2026-11-13).
repo() { # private default_branch admin delete_branch_on_merge ss pp
  jq -cn --arg p "$1" --arg b "$2" --arg a "$3" --arg d "$4" --arg ss "$5" --arg pp "$6" '
    def st($v): if $v == "none" then null else {status: $v} end;
    {private: ($p == "true"), default_branch: $b, permissions: {admin: ($a == "true")},
     delete_branch_on_merge: ($d == "true"),
     security_and_analysis: (if $ss == "none" and $pp == "none" then null
       else {secret_scanning: st($ss), secret_scanning_push_protection: st($pp)} end)}' | tr -d '\r'
}
# Classic protection, cut down from a real response. $1/$2: are force pushes /
# deletions ALLOWED (true means the branch is open to them). $3: is the branch
# locked; left out, the answer has no lock field at all. $4: do the settings
# bind administrators (enforce_admins), true unless given.
classic() {
  local lock=""
  [ $# -ge 3 ] && lock="\"lock_branch\":{\"enabled\":$3},"
  printf '{"url":"https://api.github.com/repos/me/proj/branches/main/protection","enforce_admins":{"enabled":%s},%s"allow_force_pushes":{"enabled":%s},"allow_deletions":{"enabled":%s}}' "${4:-true}" "$lock" "$1" "$2"
}
# The active rules that apply to a branch: one object per rule, by type. They
# come from ruleset 1 unless RS says otherwise.
rules() {
  local out="[" sep="" t
  for t in "$@"; do out="$out$sep{\"type\":\"$t\",\"ruleset_source_type\":\"Repository\",\"ruleset_id\":${RS:-1}}"; sep=","; done
  printf '%s]' "$out"
}
both() { # two lists of rules as one
  printf '%s\n%s\n' "$1" "$2" | jq -cs 'add' | tr -d '\r'
}
many() { # $1 how many review rules, then the types of the rules after them
  local n="$1"; shift
  jq -cn --argjson n "$n" --arg t "$*" '
    def r($t): {type: $t, ruleset_source_type: "Repository", ruleset_id: 1};
    [range($n) | r("pull_request")] + [$t | split(" ")[] | select(. != "") | r(.)]' | tr -d '\r'
}
# One ruleset, as `GET /repos/{owner}/{repo}/rulesets/{id}` answers an admin.
# $2 is its bypass list as JSON, or the word absent for an answer without one
# (what GitHub sends to someone who may not edit the ruleset).
BYPASS_ADMIN='[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"always"}]'
ruleset() {
  if [ "$2" = absent ]; then api "repos/me/proj/rulesets/$1" 200 "{\"id\":$1,\"enforcement\":\"active\"}"
  else api "repos/me/proj/rulesets/$1" 200 "{\"id\":$1,\"enforcement\":\"active\",\"bypass_actors\":$2}"; fi
}
healthy() { # a public repo with everything on; the branch is covered by a ruleset
  N=$((N + 1)); FIX="$TMP/fix$N"; PROJ="$TMP/proj$N"
  mkdir -p "$FIX/api" "$PROJ/.github"
printf 'version: 2\nupdates:\n  - package-ecosystem: "github-actions"\n    directory: "/"\n' > "$PROJ/.github/dependabot.yml"
  echo 'me/proj' > "$FIX/repo-view"
  api repos/me/proj 200 "$(repo false main true true enabled enabled)"
  api repos/me/proj/vulnerability-alerts 204
  api repos/me/proj/automated-security-fixes 200 '{"enabled":true,"paused":false}'
  api repos/me/proj/branches/main/protection 404 "$UNPROTECTED"
  api repos/me/proj/rules/branches/main 200 "$(rules deletion non_fast_forward pull_request)"
  ruleset 1 '[]'
  api repos/me/proj/actions/permissions/workflow 200 '{"default_workflow_permissions":"read","can_approve_pull_request_reviews":false}'
  api repos/me/proj/private-vulnerability-reporting 200 '{"enabled":true}'
}

OUT=""; RC=0
run() { # args passed to the script; porcelain unless told otherwise
  RC=0
  OUT=$(GH_FIX="$FIX" PATH="$TMP/bin:$PATH" bash "$SCRIPT" --root "$PROJ" "$@" 2>&1) || RC=$?
}
# Run with a ten-second cap. RC=124 means it had to be killed: a loop that
# never ends is a result here, not a hung suite.
bounded() {
  local pid i=0
  GH_FIX="$FIX" PATH="$TMP/bin:$PATH" bash "$SCRIPT" "$@" > "$TMP/bounded.out" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; RC=124
  else
    RC=0; wait "$pid" || RC=$?
  fi
  OUT=$(cat "$TMP/bounded.out")
}
state() { # $1 check name -> its state in porcelain OUT
  printf '%s\n' "$OUT" | awk -F'\t' -v c="$1" '$1==c{print $2}'
}
note() { # $1 check name -> its note in porcelain OUT
  printf '%s\n' "$OUT" | awk -F'\t' -v c="$1" '$1==c{print $3}'
}
expect() { # $1 label, $2 want rc, then pairs: check state
  local label="$1" want="$2" got; shift 2
  if [ "$RC" != "$want" ]; then bad "$label" "rc=$RC want $want :: $OUT"; return; fi
  while [ $# -ge 2 ]; do
    got=$(state "$1")
    if [ "$got" != "$2" ]; then bad "$label" "$1 is '$got', want '$2' :: $OUT"; return; fi
    shift 2
  done
  ok "$label"
}

echo "== everything on"
healthy; run --porcelain
expect "healthy public repo exits 0, every check ON" 0 \
  dependabot-alerts ON dependabot-security-updates ON secret-scanning ON \
  push-protection ON default-branch-protection ON delete-branch-on-merge ON \
  workflow-token-read-only ON private-vulnerability-reporting ON dependabot-config ON

echo "== one thing off at a time"
healthy; api repos/me/proj/vulnerability-alerts 404 "$ALERTS_OFF"; run --porcelain
expect "alerts endpoint says they are disabled -> OFF, exit 1" 1 dependabot-alerts OFF dependabot-security-updates ON

healthy; api repos/me/proj/automated-security-fixes 200 '{"enabled":false,"paused":false}'; run --porcelain
expect "security updates disabled -> OFF" 1 dependabot-security-updates OFF secret-scanning ON

# A paused setting still answers enabled:true, and opens nothing.
healthy; api repos/me/proj/automated-security-fixes 200 '{"enabled":true,"paused":true}'; run --porcelain
expect "security updates enabled but paused -> OFF" 1 dependabot-security-updates OFF secret-scanning ON
case "$(note dependabot-security-updates)" in
  *paused*) ok "and the note says they are paused" ;;
  *) bad "and the note says they are paused" "$OUT" ;;
esac

healthy; api repos/me/proj 200 "$(repo false main true true disabled enabled)"; run --porcelain
expect "secret scanning disabled -> OFF" 1 secret-scanning OFF push-protection ON

healthy; api repos/me/proj 200 "$(repo false main true true enabled disabled)"; run --porcelain
expect "push protection disabled -> OFF" 1 push-protection OFF secret-scanning ON

healthy; api repos/me/proj 200 "$(repo false main true false enabled enabled)"; run --porcelain
expect "delete-branch-on-merge false -> OFF" 1 delete-branch-on-merge OFF

healthy; api repos/me/proj/actions/permissions/workflow 200 '{"default_workflow_permissions":"write"}'; run --porcelain
expect "workflow token write -> OFF" 1 workflow-token-read-only OFF

healthy; api repos/me/proj/private-vulnerability-reporting 200 '{"enabled":false}'; run --porcelain
expect "private vulnerability reporting false -> OFF" 1 private-vulnerability-reporting OFF

healthy; rm -f "$PROJ/.github/dependabot.yml"; run --porcelain
expect "no dependabot.yml -> OFF" 1 dependabot-config OFF

healthy; mv "$PROJ/.github/dependabot.yml" "$PROJ/.github/dependabot.yaml"; run --porcelain
expect ".yaml spelling of the config counts" 0 dependabot-config ON

# The file being there is not the same as it watching anything. ON names what
# it watches, so "on" is not read as "my app's packages are covered" when the
# only entry is the one the template shipped for its own CI.
healthy; run --porcelain
case "$(note dependabot-config)" in
  "watches: github-actions") ok "the ON line names the one ecosystem the file watches" ;;
  *) bad "the ON line names the one ecosystem the file watches" "$(note dependabot-config)" ;;
esac

healthy; printf "    - package-ecosystem: 'npm'\n  - package-ecosystem: pip\n# - package-ecosystem: \"cargo\"\n" >> "$PROJ/.github/dependabot.yml"; run --porcelain
case "$(note dependabot-config)" in
  "watches: github-actions npm pip") ok "every entry is named, quoted any way, and a commented-out one is not" ;;
  *) bad "every entry is named, quoted any way, and a commented-out one is not" "$(note dependabot-config)" ;;
esac

healthy; run
case "$OUT" in
  *"on       dependabot-config - watches: github-actions"*) ok "human output shows what the file watches" ;;
  *) bad "human output shows what the file watches" "$OUT" ;;
esac

healthy; echo 'version: 2' > "$PROJ/.github/dependabot.yml"; run --porcelain
expect "a dependabot.yml with no package-ecosystem entry watches nothing -> OFF" 1 dependabot-config OFF

healthy; printf 'version: 2\n# - package-ecosystem: "npm"\n' > "$PROJ/.github/dependabot.yml"; run --porcelain
expect "an entry that is only a comment does not count -> OFF" 1 dependabot-config OFF

echo "== default branch: either route protects it"
healthy; api repos/me/proj/rules/branches/main 200 '[]'; run --porcelain
expect "no classic protection and no rules -> OFF" 1 default-branch-protection OFF

healthy; api repos/me/proj/rules/branches/main 200 '[]'
api repos/me/proj/branches/main/protection 200 "$(classic false false)"; run --porcelain
expect "classic protection that blocks both, no rules -> ON" 0 default-branch-protection ON

healthy; api repos/me/proj 200 "$(repo false trunk true true enabled enabled)"
api repos/me/proj/branches/trunk/protection 404 "$UNPROTECTED"
api repos/me/proj/rules/branches/trunk 200 "$(rules non_fast_forward deletion)"
api repos/me/proj/rules/branches/main 200 '[]'; run --porcelain
expect "the DEFAULT branch is the one checked, whatever its name" 0 default-branch-protection ON

# GitHub lists the two allow settings under "Rules applied to everyone
# including administrators", so they count without enforce_admins.
healthy; api repos/me/proj/rules/branches/main 200 '[]'
api repos/me/proj/branches/main/protection 200 "$(classic false false false false)"; run --porcelain
expect "classic blocks both and administrators may bypass the rest -> still ON" 0 default-branch-protection ON

# A locked branch is read-only and cannot be deleted, whatever the two allow
# settings say. The lock is one of the settings an administrator bypasses
# unless enforce_admins is on, so it counts only with it.
healthy; api repos/me/proj/rules/branches/main 200 '[]'
api repos/me/proj/branches/main/protection 200 "$(classic true true true true)"; run --porcelain
expect "a locked branch that binds administrators -> ON" 0 default-branch-protection ON

healthy; api repos/me/proj/rules/branches/main 200 '[]'
api repos/me/proj/branches/main/protection 200 "$(classic true true true false)"; run --porcelain
expect "a locked branch administrators can bypass -> OFF" 1 default-branch-protection OFF
case "$(note default-branch-protection)" in
  *locked*administrators*) ok "and the note says the lock does not bind administrators" ;;
  *) bad "and the note says the lock does not bind administrators" "$OUT" ;;
esac

# The two routes add up: one may stop force pushes and the other deletion.
healthy; api repos/me/proj/branches/main/protection 200 "$(classic false true)"
api repos/me/proj/rules/branches/main 200 "$(rules deletion)"; run --porcelain
expect "classic blocks force pushes, a rule blocks deletion -> ON" 0 default-branch-protection ON

# A branch name goes into two API paths, and GitHub allows characters in one
# that change what a URL means. `we#ird` would ask about the branch `we`.
healthy; api repos/me/proj 200 "$(repo false 'we#ird' true true enabled enabled)"; run --porcelain
expect "a branch name that would change the URL -> UNKNOWN, exit 2" 2 default-branch-protection UNKNOWN dependabot-alerts ON
if grep -q 'branches/we' "$FIX/CALLS"; then bad "a branch name that would change the URL is never sent" "$(grep 'branches/we' "$FIX/CALLS")"
else ok "a branch name that would change the URL is never sent"; fi

healthy; api repos/me/proj 200 "$(repo false release/1.x true true enabled enabled)"
api repos/me/proj/branches/release/1.x/protection 404 "$UNPROTECTED"
api repos/me/proj/rules/branches/release/1.x 200 "$(rules non_fast_forward deletion)"; run --porcelain
expect "a branch name with a slash and a dot is asked about as it is" 0 default-branch-protection ON

echo "== default branch: protection that protects nothing is OFF"
healthy; api repos/me/proj/rules/branches/main 200 '[]'
api repos/me/proj/branches/main/protection 200 "$(classic true false)"; run --porcelain
expect "classic protection that ALLOWS force pushes -> OFF" 1 default-branch-protection OFF
case "$(note default-branch-protection)" in
  *"force pushes are allowed"*) ok "and the note says force pushes are what is open" ;;
  *) bad "and the note says force pushes are what is open" "$OUT" ;;
esac

healthy; api repos/me/proj/rules/branches/main 200 '[]'
api repos/me/proj/branches/main/protection 200 "$(classic false true)"; run --porcelain
expect "classic protection that ALLOWS deletion -> OFF" 1 default-branch-protection OFF

# Seen on a real public repository: the one active rule was a review rule.
healthy; api repos/me/proj/rules/branches/main 200 "$(rules copilot_code_review)"; run --porcelain
expect "a ruleset whose only rule is a review -> OFF" 1 default-branch-protection OFF

healthy; api repos/me/proj/rules/branches/main 200 "$(rules non_fast_forward pull_request)"; run --porcelain
expect "rules stop force pushes but not deletion -> OFF" 1 default-branch-protection OFF
case "$(note default-branch-protection)" in
  *"deletion is allowed"*) ok "and the note says deletion is what is open" ;;
  *) bad "and the note says deletion is what is open" "$OUT" ;;
esac
case "$(note default-branch-protection)" in
  *"force pushes are allowed"*) bad "and it does not claim force pushes are open" "$OUT" ;;
  *) ok "and it does not claim force pushes are open" ;;
esac

healthy; api repos/me/proj/rules/branches/main 200 "$(rules deletion pull_request)"; run --porcelain
expect "rules stop deletion but not force pushes -> OFF" 1 default-branch-protection OFF
case "$(note default-branch-protection)" in
  *"force pushes are allowed"*) ok "and the note says force pushes are what is open" ;;
  *) bad "and the note says force pushes are what is open" "$OUT" ;;
esac

echo "== default branch: a ruleset somebody can bypass does not count"
healthy; ruleset 1 "$BYPASS_ADMIN"; run --porcelain
expect "the ruleset's bypass list names a role that may always bypass -> OFF" 1 default-branch-protection OFF
case "$(note default-branch-protection)" in
  *"ruleset 1"*bypass*) ok "and the note names the ruleset and its bypass list" ;;
  *) bad "and the note names the ruleset and its bypass list" "$OUT" ;;
esac

healthy; ruleset 1 '[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"exempt"}]'; run --porcelain
expect "an actor the rules are never run for (exempt) -> OFF" 1 default-branch-protection OFF

healthy; ruleset 1 '[{"actor_id":5,"actor_type":"RepositoryRole"}]'; run --porcelain
expect "a bypass entry that does not say how -> OFF, not assumed harmless" 1 default-branch-protection OFF

# "pull_request" lets an actor merge a pull request past the rules. It does not
# let them push, so it opens neither a force-push nor a deletion.
healthy; ruleset 1 '[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"pull_request"}]'; run --porcelain
expect "a bypass that works only through a pull request -> still ON" 0 default-branch-protection ON

# GitHub leaves the bypass list out for someone who may not edit the ruleset
# (one set above the repository, say). Absent is not empty.
healthy; ruleset 1 absent; run --porcelain
expect "the ruleset's answer has no bypass list -> UNKNOWN, exit 2" 2 default-branch-protection UNKNOWN
case "$(note default-branch-protection)" in
  *"ruleset 1"*) ok "and the note names the ruleset it could not read" ;;
  *) bad "and the note names the ruleset it could not read" "$OUT" ;;
esac

healthy; api repos/me/proj/rulesets/1 500; run --porcelain
expect "the ruleset cannot be read at all -> UNKNOWN" 2 default-branch-protection UNKNOWN

healthy; api repos/me/proj/rulesets/1 500
api repos/me/proj/branches/main/protection 200 "$(classic false false)"; run --porcelain
expect "ruleset unreadable but classic protection blocks both -> ON" 0 default-branch-protection ON

healthy; ruleset 2 "$BYPASS_ADMIN"
api repos/me/proj/rules/branches/main 200 "$(both "$(rules non_fast_forward)" "$(RS=2 rules deletion)")"; run --porcelain
expect "force pushes blocked by a clean ruleset, deletion by one with a bypass list -> OFF" 1 default-branch-protection OFF
case "$(note default-branch-protection)" in
  *"deletion is allowed"*) ok "and the note says deletion is what is open" ;;
  *) bad "and the note says deletion is what is open" "$OUT" ;;
esac
case "$(note default-branch-protection)" in
  *"force pushes are allowed"*) bad "and it does not claim force pushes are open" "$OUT" ;;
  *) ok "and it does not claim force pushes are open" ;;
esac

healthy; ruleset 9 "$BYPASS_ADMIN"
api repos/me/proj/rules/branches/main 200 "$(both "$(RS=9 rules pull_request)" "$(rules non_fast_forward deletion)")"; run --porcelain
expect "a bypass list on a ruleset that holds neither blocking rule does not matter -> ON" 0 default-branch-protection ON

echo "== default branch: every page of rules is read"
healthy; api repos/me/proj/rules/branches/main 200 "$(many 100 non_fast_forward deletion)"; run --porcelain
expect "the blocking rules are on the second page -> ON" 0 default-branch-protection ON

healthy; api repos/me/proj/rules/branches/main 200 "$(many 1001)"; run --porcelain
expect "more rules than ten pages hold -> UNKNOWN, never OFF on a partial read" 2 default-branch-protection UNKNOWN

echo "== fix commands name the right endpoint and are only printed"
healthy; api repos/me/proj/vulnerability-alerts 404 "$ALERTS_OFF"
api repos/me/proj/actions/permissions/workflow 200 '{"default_workflow_permissions":"write"}'; run
case "$OUT" in
  *"gh api -X PUT repos/me/proj/vulnerability-alerts"*"gh api -X PUT repos/me/proj/actions/permissions/workflow"*) ok "human output prints each fix command" ;;
  *) bad "human output prints each fix command" "$OUT" ;;
esac
case "$OUT" in
  *"Nothing was changed"*) ok "human output says nothing was changed" ;;
  *) bad "human output says nothing was changed" "$OUT" ;;
esac

echo "== unknown is never green"
healthy; api repos/me/proj/vulnerability-alerts 500; run --porcelain
expect "alerts endpoint errors -> UNKNOWN, exit 2" 2 dependabot-alerts UNKNOWN dependabot-security-updates ON

# A 404 is "off" only when GitHub says so. A token that may not look can be
# answered 404 as well, and that is not the same fact.
healthy; api repos/me/proj/vulnerability-alerts 404; run --porcelain
expect "alerts 404 without GitHub's 'disabled' message -> UNKNOWN" 2 dependabot-alerts UNKNOWN

healthy; api repos/me/proj/automated-security-fixes 500; run --porcelain
expect "security updates endpoint errors -> UNKNOWN" 2 dependabot-security-updates UNKNOWN

healthy; api repos/me/proj/automated-security-fixes 200 '{"paused":false}'; run --porcelain
expect "security updates answer without its field -> UNKNOWN" 2 dependabot-security-updates UNKNOWN

healthy; api repos/me/proj/automated-security-fixes 200 '{"enabled":true}'; run --porcelain
expect "security updates enabled, with no word on whether they are paused -> UNKNOWN" 2 dependabot-security-updates UNKNOWN

healthy; api repos/me/proj/actions/permissions/workflow 200 '{"can_approve_pull_request_reviews":false}'; run --porcelain
expect "workflow permissions answer without its field -> UNKNOWN" 2 workflow-token-read-only UNKNOWN

healthy; api repos/me/proj/private-vulnerability-reporting 200 '{}'; run --porcelain
expect "vulnerability reporting answer without its field -> UNKNOWN" 2 private-vulnerability-reporting UNKNOWN

healthy; api repos/me/proj/rules/branches/main 500; run --porcelain
expect "rules endpoint errors and no classic protection -> UNKNOWN" 2 default-branch-protection UNKNOWN

healthy; api repos/me/proj/rules/branches/main 200 '{"message":"not a list"}'; run --porcelain
expect "rules answer that is not a list -> UNKNOWN" 2 default-branch-protection UNKNOWN

# An entry that is not a rule is an answer this script does not understand.
# Counting it as "not a blocking rule" would turn that into OFF.
healthy; api repos/me/proj/rules/branches/main 200 '[{}]'; run --porcelain
expect "a rule entry with no type -> UNKNOWN, not 'no blocking rule'" 2 default-branch-protection UNKNOWN

healthy; api repos/me/proj/rules/branches/main 200 '[{"type":"non_fast_forward"},{"type":"deletion","ruleset_id":1}]'; run --porcelain
expect "a blocking rule that does not say which ruleset it is from -> UNKNOWN" 2 default-branch-protection UNKNOWN

healthy; api repos/me/proj/rules/branches/main 200 '[]'
api repos/me/proj/branches/main/protection 200 '{"url":"https://x"}'; run --porcelain
expect "classic answer without the force-push and deletion fields -> UNKNOWN" 2 default-branch-protection UNKNOWN

# A 404 that does not say "Branch not protected" is not evidence of anything.
healthy; api repos/me/proj/rules/branches/main 200 '[]'
api repos/me/proj/branches/main/protection 404; run --porcelain
expect "classic 404 without GitHub's 'not protected' message -> UNKNOWN" 2 default-branch-protection UNKNOWN

# The readable route settles it, so the unreadable one does not matter.
healthy; api repos/me/proj/branches/main/protection 500; run --porcelain
expect "classic unreadable but rules block both -> ON" 0 default-branch-protection ON

# A 403 is a plan refusal only on a private repository AND only when GitHub
# says so. Anything else is a token that may not look.
healthy; api repos/me/proj/branches/main/protection 403 "$PLAN"
api repos/me/proj/rules/branches/main 403 "$PLAN"; run --porcelain
expect "public repo, 403 on both routes -> UNKNOWN, never SKIP" 2 default-branch-protection UNKNOWN

healthy; api repos/me/proj 200 "$(repo true main true true none none)"
unapi repos/me/proj/private-vulnerability-reporting
api repos/me/proj/branches/main/protection 403 "$DENIED"
api repos/me/proj/rules/branches/main 403 "$DENIED"; run --porcelain
expect "private repo, 403 that is a permission refusal -> UNKNOWN, never SKIP" 2 default-branch-protection UNKNOWN

healthy; api repos/me/proj 200 "$(repo true main true true none none)"
unapi repos/me/proj/private-vulnerability-reporting
api repos/me/proj/branches/main/protection 403 "$DENIED"
api repos/me/proj/rules/branches/main 200 '[]'; run --porcelain
expect "classic refused for permission, rules empty -> UNKNOWN, not OFF" 2 default-branch-protection UNKNOWN

healthy; api repos/me/proj/actions/permissions/workflow 200 '{"default_workflow_permissions":""}'; run --porcelain
expect "empty workflow permission -> UNKNOWN" 2 workflow-token-read-only UNKNOWN

healthy; api repos/me/proj 200 "$(repo false main true true none none)"; run --porcelain
expect "absent security block on a public repo -> UNKNOWN, not OFF and not ON" 2 \
  secret-scanning UNKNOWN push-protection UNKNOWN

healthy; api repos/me/proj/vulnerability-alerts 500
api repos/me/proj/actions/permissions/workflow 200 '{"default_workflow_permissions":"write"}'; run --porcelain
expect "unknown beside off: exit 2 wins, the OFF is still reported" 2 \
  dependabot-alerts UNKNOWN workflow-token-read-only OFF

healthy; api repos/me/proj 500; run --porcelain
if [ "$RC" = 2 ] && ! printf '%s\n' "$OUT" | grep -q "$(printf '\t')ON"; then
  ok "repository unreadable -> exit 2 and nothing reported ON"
else bad "repository unreadable -> exit 2 and nothing reported ON" "rc=$RC :: $OUT"; fi

healthy; api repos/me/proj 200 "$(repo false main false true enabled enabled)"; run --porcelain
if [ "$RC" = 2 ] && printf '%s' "$OUT" | grep -qi 'admin'; then
  ok "no admin access -> exit 2, and the message says why"
else bad "no admin access -> exit 2, and the message says why" "rc=$RC :: $OUT"; fi

# A value that holds the character the script joins its fields with. The seven
# fields it reads are all present and all say "on", and an eighth follows, so
# only the shape check stands between this answer and a clean report.
healthy; api repos/me/proj 200 "$(repo false main true true enabled 'enabled|surprise')"; run --porcelain
if [ "$RC" = 2 ]; then ok "repository answer with an unexpected field -> exit 2"
else bad "repository answer with an unexpected field -> exit 2" "rc=$RC :: $OUT"; fi

healthy; rm -f "$FIX/repo-view"; run --porcelain
if [ "$RC" = 2 ]; then ok "no GitHub remote -> exit 2"
else bad "no GitHub remote -> exit 2" "rc=$RC :: $OUT"; fi

healthy
# PATH holds nothing at all, so this also pins that the gh check comes before
# the script's first external command.
RC=0; OUT=$(GH_FIX="$FIX" PATH="$TMP/empty-bin" "$BASH" "$SCRIPT" --root "$PROJ" --porcelain 2>&1) || RC=$?
if [ "$RC" = 2 ] && printf '%s' "$OUT" | grep -q 'not installed'; then ok "gh not installed -> exit 2, and says so"
else bad "gh not installed -> exit 2, and says so" "rc=$RC :: $OUT"; fi

healthy; run --porcelain --bogus
if [ "$RC" = 2 ]; then ok "unknown argument -> exit 2"
else bad "unknown argument -> exit 2" "rc=$RC :: $OUT"; fi

echo "== an option with its value missing"
# `shift 2` with one argument left fails and shifts nothing, so without a
# check the option is read again, for ever.
healthy; bounded --root "$PROJ" --porcelain --repo
if [ "$RC" = 2 ]; then ok "--repo with no value -> exit 2, and it returns"
else bad "--repo with no value -> exit 2, and it returns" "rc=$RC (124 = killed after 10s) :: $OUT"; fi

healthy; bounded --porcelain --root
if [ "$RC" = 2 ]; then ok "--root with no value -> exit 2, and it returns"
else bad "--root with no value -> exit 2, and it returns" "rc=$RC (124 = killed after 10s) :: $OUT"; fi

healthy; bounded --root "$PROJ" --porcelain --repo ''
if [ "$RC" = 2 ] && printf '%s' "$OUT" | grep -q 'needs a value'; then ok "--repo '' -> exit 2, not a silent fall back to this checkout's repository"
else bad "--repo '' -> exit 2, not a silent fall back to this checkout's repository" "rc=$RC :: $OUT"; fi

healthy; bounded --porcelain --root ''
if [ "$RC" = 2 ] && printf '%s' "$OUT" | grep -q 'needs a value'; then ok "--root '' -> exit 2, not a silent fall back to the current directory"
else bad "--root '' -> exit 2, not a silent fall back to the current directory" "rc=$RC :: $OUT"; fi

echo "== private repositories"
# GitHub leaves the whole security block out for a private repository on a
# plan without secret scanning. Security updates are not part of that plan
# question, so they are read from their own endpoint and still reported.
healthy; api repos/me/proj 200 "$(repo true main true true none none)"
unapi repos/me/proj/private-vulnerability-reporting
api repos/me/proj/automated-security-fixes 200 '{"enabled":false,"paused":false}'; run --porcelain
expect "private repo with no security block: security updates are still read (OFF)" 1 \
  dependabot-security-updates OFF secret-scanning SKIP push-protection SKIP

healthy; api repos/me/proj 200 "$(repo true main true true none none)"
unapi repos/me/proj/private-vulnerability-reporting; run --porcelain
expect "private repo: secret scanning and reporting are SKIP, not findings" 0 \
  secret-scanning SKIP push-protection SKIP private-vulnerability-reporting SKIP \
  dependabot-security-updates ON

healthy; api repos/me/proj 200 "$(repo true main true true enabled enabled)"
unapi repos/me/proj/private-vulnerability-reporting; run --porcelain
expect "private repo on a plan that has secret scanning: reported as ON" 0 \
  secret-scanning ON push-protection ON

healthy; api repos/me/proj 200 "$(repo true main true true none none)"
unapi repos/me/proj/private-vulnerability-reporting
api repos/me/proj/branches/main/protection 403 "$PLAN"
api repos/me/proj/rules/branches/main 403 "$PLAN"; run --porcelain
expect "private repo, GitHub says the plan has no branch protection -> SKIP, exit 0" 0 default-branch-protection SKIP

healthy; api repos/me/proj 200 "$(repo true main true true none none)"
unapi repos/me/proj/private-vulnerability-reporting
api repos/me/proj/branches/main/protection 403 "$PLAN"
api repos/me/proj/rules/branches/main 200 '[]'; run --porcelain
expect "plan refuses one route, the other is readable and empty -> OFF, not SKIP" 1 default-branch-protection OFF

echo "== --repo"
healthy; rm -f "$FIX/repo-view"; run --porcelain --repo me/proj
expect "--repo skips the remote lookup" 0 dependabot-alerts ON
healthy; run --porcelain --repo 'me/proj;rm -rf x'
if [ "$RC" = 2 ] && printf '%s' "$OUT" | grep -q 'not an OWNER/NAME'; then ok "--repo refuses a name that is not owner/name"
else bad "--repo refuses a name that is not owner/name" "rc=$RC :: $OUT"; fi

# No --root: the repository asked about is not this checkout, so the file check
# must not be answered from whatever directory the script happens to run in.
healthy; mkdir -p "$TMP/elsewhere/.github"; echo 'version: 2' > "$TMP/elsewhere/.github/dependabot.yml"
RC=0; OUT=$(cd "$TMP/elsewhere" && GH_FIX="$FIX" PATH="$TMP/bin:$PATH" bash "$SCRIPT" --porcelain --repo me/proj 2>&1) || RC=$?
expect "--repo without --root: the local file check is SKIP" 0 dependabot-config SKIP dependabot-alerts ON

# --root says where the checkout is, so that is where the repository is looked
# up from. Looked up from wherever the script was started, --root would read
# one repository's settings and another one's file.
healthy; run --porcelain
if [ "$(cat "$FIX/REPO_VIEW_CWD" 2>/dev/null)" = "$(cd "$PROJ" && pwd)" ]; then ok "--root: the repository is looked up from inside that checkout"
else bad "--root: the repository is looked up from inside that checkout" "looked up from: $(cat "$FIX/REPO_VIEW_CWD" 2>/dev/null)"; fi

echo "== read-only"
# Every run above, checked once: nothing left the script except the two read
# shapes the fake allows. The count of runs guards the check itself: a loop
# over no fixtures would pass this with nothing looked at.
disallowed=0; looked=0
for d in "$TMP"/fix*; do
  [ -d "$d" ] || continue
  looked=$((looked + 1))
  [ -f "$d/DISALLOWED" ] && disallowed=$((disallowed + 1))
done
if [ "$looked" -ge 70 ] && [ "$disallowed" -eq 0 ]; then ok "no run sent anything but the two read shapes ($looked runs checked)"
else bad "no run sent anything but the two read shapes" "runs checked: $looked :: $(cat "$TMP"/fix*/DISALLOWED 2>/dev/null)"; fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
