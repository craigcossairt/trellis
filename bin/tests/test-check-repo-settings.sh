#!/usr/bin/env bash
# =============================================================================
# test-check-repo-settings.sh - behavioral tests for bin/check-repo-settings.sh
# =============================================================================
# The script reads a GitHub repository's safety settings and says which are
# off. Three ways it can lie, and each is pinned here:
#
#   1. It says ON for something it could not read. An API error, a missing
#      field or a missing `gh` must come out UNKNOWN and exit 2, never ON and
#      never a silent skip. Unknown must not resolve to green.
#   2. It says OFF for something that is on by another route. A default branch
#      covered by a ruleset has no classic branch protection, and the reverse.
#   3. It changes something. The script is read-only: every `gh api` call it
#      makes is a GET. The fake `gh` below records any call that carries a
#      method flag, and the last case fails if one was ever made.
#
# WHAT THIS SUITE DOES NOT PROVE. The fake `gh` answers by API path and ignores
# the `--jq` expression, so the expressions themselves and the shape of
# GitHub's real responses are not exercised here. That half is checked by
# running the script against a real repository (it is read-only, so that is
# safe); the PR that added it records such a run.
#
# Hermetic: a fake `gh` on PATH, temp dirs, no network.
#
# Run:  bash bin/tests/test-check-repo-settings.sh
# =============================================================================
set -uo pipefail

HERE="$(CDPATH='' cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SCRIPT="$ROOT/bin/check-repo-settings.sh"
[ -f "$SCRIPT" ] || { echo "missing $SCRIPT" >&2; exit 1; }

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
#                        rest:   the body printed on stdout for a 2xx
#   WRITES               appended to on any call carrying -X / --method / -f / -F
#   CALLS                every invocation, one line each
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_FIX/CALLS"
case " $* " in
  *" -X "*|*" --method "*|*" -f "*|*" -F "*|*" --input "*) printf '%s\n' "$*" >> "$GH_FIX/WRITES" ;;
esac
if [ "${1:-}" = repo ] && [ "${2:-}" = view ]; then
  [ -f "$GH_FIX/repo-view" ] || { echo "gh: no git remotes found" >&2; exit 1; }
  cat "$GH_FIX/repo-view"; exit 0
fi
if [ "${1:-}" = api ]; then
  key=$(printf '%s' "${2:-}" | sed 's|/|__|g')
  f="$GH_FIX/api/$key"
  [ -f "$f" ] || { echo "gh: fixture missing for ${2:-} (HTTP 500)" >&2; exit 1; }
  status=$(head -n 1 "$f")
  case "$status" in
    2*) tail -n +2 "$f"; exit 0 ;;
    403) echo "gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)" >&2; exit 1 ;;
    404) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
    *)   echo "gh: Server Error (HTTP $status)" >&2; exit 1 ;;
  esac
fi
echo "fake gh: unhandled: $*" >&2; exit 64
FAKE
chmod +x "$TMP/bin/gh"

# --- fixtures -------------------------------------------------------------------
N=0
FIX=""; PROJ=""
api() { # $1 path, $2 status, $3 optional body
  local key; key=$(printf '%s' "$1" | sed 's|/|__|g')
  { printf '%s\n' "$2"; [ $# -ge 3 ] && printf '%s\n' "$3"; } > "$FIX/api/$key"
  return 0
}
unapi() { local key; key=$(printf '%s' "$1" | sed 's|/|__|g'); rm -f "$FIX/api/$key"; }
# repo line: private|default_branch|admin|delete_branch_on_merge|dsu|ss|pp
healthy() { # a public repo with everything on
  N=$((N + 1)); FIX="$TMP/fix$N"; PROJ="$TMP/proj$N"
  mkdir -p "$FIX/api" "$PROJ/.github"
  echo 'version: 2' > "$PROJ/.github/dependabot.yml"
  echo 'me/proj' > "$FIX/repo-view"
  api repos/me/proj 200 'false|main|true|true|enabled|enabled|enabled'
  api repos/me/proj/vulnerability-alerts 204
  api repos/me/proj/branches/main/protection 404
  api repos/me/proj/rules/branches/main 200 '2'
  api repos/me/proj/actions/permissions/workflow 200 'read'
  api repos/me/proj/private-vulnerability-reporting 200 'true'
}

OUT=""; RC=0
run() { # args passed to the script; porcelain unless told otherwise
  RC=0
  OUT=$(GH_FIX="$FIX" PATH="$TMP/bin:$PATH" bash "$SCRIPT" --root "$PROJ" "$@" 2>&1) || RC=$?
}
state() { # $1 check name -> its state in porcelain OUT
  printf '%s\n' "$OUT" | awk -F'\t' -v c="$1" '$1==c{print $2}'
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
healthy; api repos/me/proj/vulnerability-alerts 404; run --porcelain
expect "alerts endpoint 404 -> OFF, exit 1" 1 dependabot-alerts OFF dependabot-security-updates ON

healthy; api repos/me/proj 200 'false|main|true|true|disabled|enabled|enabled'; run --porcelain
expect "security updates disabled -> OFF" 1 dependabot-security-updates OFF secret-scanning ON

healthy; api repos/me/proj 200 'false|main|true|true|enabled|disabled|enabled'; run --porcelain
expect "secret scanning disabled -> OFF" 1 secret-scanning OFF push-protection ON

healthy; api repos/me/proj 200 'false|main|true|true|enabled|enabled|disabled'; run --porcelain
expect "push protection disabled -> OFF" 1 push-protection OFF secret-scanning ON

healthy; api repos/me/proj 200 'false|main|true|false|enabled|enabled|enabled'; run --porcelain
expect "delete-branch-on-merge false -> OFF" 1 delete-branch-on-merge OFF

healthy; api repos/me/proj/actions/permissions/workflow 200 'write'; run --porcelain
expect "workflow token write -> OFF" 1 workflow-token-read-only OFF

healthy; api repos/me/proj/private-vulnerability-reporting 200 'false'; run --porcelain
expect "private vulnerability reporting false -> OFF" 1 private-vulnerability-reporting OFF

healthy; rm -f "$PROJ/.github/dependabot.yml"; run --porcelain
expect "no dependabot.yml -> OFF" 1 dependabot-config OFF

healthy; rm -f "$PROJ/.github/dependabot.yml"; echo 'version: 2' > "$PROJ/.github/dependabot.yaml"; run --porcelain
expect ".yaml spelling of the config counts" 0 dependabot-config ON

echo "== default branch: either route protects it"
healthy; api repos/me/proj/rules/branches/main 200 '0'; run --porcelain
expect "no classic protection and no rules -> OFF" 1 default-branch-protection OFF

healthy; api repos/me/proj/rules/branches/main 200 '0'; api repos/me/proj/branches/main/protection 200 'https://x'; run --porcelain
expect "classic protection alone -> ON" 0 default-branch-protection ON

healthy; api repos/me/proj 200 'false|trunk|true|true|enabled|enabled|enabled'
api repos/me/proj/branches/trunk/protection 404; api repos/me/proj/rules/branches/trunk 200 '1'
api repos/me/proj/rules/branches/main 200 '0'; run --porcelain
expect "the DEFAULT branch is the one checked, whatever its name" 0 default-branch-protection ON

echo "== fix commands name the right endpoint and are only printed"
healthy; api repos/me/proj/vulnerability-alerts 404
api repos/me/proj/actions/permissions/workflow 200 'write'; run
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

healthy; api repos/me/proj/rules/branches/main 500; run --porcelain
expect "rules endpoint errors and no classic protection -> UNKNOWN" 2 default-branch-protection UNKNOWN

healthy; api repos/me/proj/rules/branches/main 200 'not-a-number'; run --porcelain
expect "rules count that is not a number -> UNKNOWN" 2 default-branch-protection UNKNOWN

healthy; api repos/me/proj/actions/permissions/workflow 200 ''; run --porcelain
expect "empty workflow permission -> UNKNOWN" 2 workflow-token-read-only UNKNOWN

healthy; api repos/me/proj 200 'false|main|true|true|none|none|none'; run --porcelain
expect "absent security fields on a public repo -> UNKNOWN, not OFF and not ON" 2 \
  dependabot-security-updates UNKNOWN secret-scanning UNKNOWN push-protection UNKNOWN

healthy; api repos/me/proj/vulnerability-alerts 500
api repos/me/proj/actions/permissions/workflow 200 'write'; run --porcelain
expect "unknown beside off: exit 2 wins, the OFF is still reported" 2 \
  dependabot-alerts UNKNOWN workflow-token-read-only OFF

healthy; api repos/me/proj 500; run --porcelain
if [ "$RC" = 2 ] && ! printf '%s\n' "$OUT" | grep -q "$(printf '\t')ON"; then
  ok "repository unreadable -> exit 2 and nothing reported ON"
else bad "repository unreadable -> exit 2 and nothing reported ON" "rc=$RC :: $OUT"; fi

healthy; api repos/me/proj 200 'false|main|false|true|enabled|enabled|enabled'; run --porcelain
if [ "$RC" = 2 ] && printf '%s' "$OUT" | grep -qi 'admin'; then
  ok "no admin access -> exit 2, and the message says why"
else bad "no admin access -> exit 2, and the message says why" "rc=$RC :: $OUT"; fi

# An eighth field. Every one of the seven the script reads is present and says
# "on", so only the shape check stands between this line and a clean report.
healthy; api repos/me/proj 200 'false|main|true|true|enabled|enabled|enabled|surprise'; run --porcelain
if [ "$RC" = 2 ]; then ok "repository line with an unexpected field -> exit 2"
else bad "repository line with an unexpected field -> exit 2" "rc=$RC :: $OUT"; fi

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

echo "== private repositories"
healthy; api repos/me/proj 200 'true|main|true|true|enabled|none|none'
unapi repos/me/proj/private-vulnerability-reporting; run --porcelain
expect "private repo: secret scanning and reporting are SKIP, not findings" 0 \
  secret-scanning SKIP push-protection SKIP private-vulnerability-reporting SKIP \
  dependabot-security-updates ON

healthy; api repos/me/proj 200 'true|main|true|true|enabled|enabled|enabled'
unapi repos/me/proj/private-vulnerability-reporting; run --porcelain
expect "private repo on a plan that has secret scanning: reported as ON" 0 \
  secret-scanning ON push-protection ON

healthy; api repos/me/proj 200 'true|main|true|true|enabled|none|none'
unapi repos/me/proj/private-vulnerability-reporting
api repos/me/proj/branches/main/protection 403; api repos/me/proj/rules/branches/main 403; run --porcelain
expect "plan refuses branch protection (403) -> SKIP, exit 0" 0 default-branch-protection SKIP

healthy; api repos/me/proj/branches/main/protection 403; api repos/me/proj/rules/branches/main 200 '0'; run --porcelain
expect "403 on one route, readable empty rules on the other -> OFF, not SKIP" 1 default-branch-protection OFF

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

echo "== read-only"
writes=0
for d in "$TMP"/fix*; do [ -f "$d/WRITES" ] && writes=$((writes + 1)); done
if [ "$writes" -eq 0 ]; then ok "no run in this suite sent a write to the API"
else bad "no run in this suite sent a write to the API" "$(cat "$TMP"/fix*/WRITES 2>/dev/null)"; fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
