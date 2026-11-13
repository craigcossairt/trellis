#!/usr/bin/env bash
# =============================================================================
# check-repo-settings.sh - which of this GitHub repository's safety settings
# are off?
# =============================================================================
# READ-ONLY. Every call it makes is a GET. It prints the command that would
# turn each missing setting on and runs none of them: changing a repository's
# settings is the owner's decision, one setting at a time.
#
# Why it exists. "Use this template" copies files, not settings, so a new
# repository starts from GitHub's defaults, and nobody who is new to this knows
# to go looking. The template's own guardrails stop at the edge of the checkout:
# a push gate does nothing about a force-push to the default branch, and a
# secret-file hook does nothing about a key that was pasted into a commit on
# another machine. These settings are the half that lives on GitHub.
#
#   check                              what it is
#   dependabot-alerts                  tells you when a dependency has a known hole
#   dependabot-security-updates        opens the pull request that fixes it
#   secret-scanning                    finds keys that were committed
#   push-protection                    refuses the push that contains a key
#   default-branch-protection          no force-push or deletion of the default
#                                      branch (classic protection OR a ruleset)
#   delete-branch-on-merge             merged branches are removed for you
#   workflow-token-read-only           CI's built-in token cannot write by default
#   private-vulnerability-reporting    a private way to report a security bug
#                                      (public repositories only)
#   dependabot-config                  .github/dependabot.yml exists, so version
#                                      updates are configured (a local file check)
#
# States: ON, OFF, SKIP (does not apply, or your GitHub plan does not offer it),
# UNKNOWN (could not be read).
#
# Exit: 0 nothing is off / 1 at least one setting is OFF / 2 could not tell.
# 2 never means clean, and it wins over 1: a report with a hole in it is not a
# report of what is off. Reading settings needs admin access to the repository;
# without it GitHub omits the fields rather than refusing, so the script stops
# there instead of reporting the absences as OFF.
#
# Usage:
#   check-repo-settings.sh [--repo OWNER/NAME] [--root DIR] [--porcelain]
#
# With no arguments it checks the repository this checkout pushes to. --repo
# names another one; the local file check is then skipped unless --root says
# where that repository's checkout is.
#
# --porcelain prints `check<TAB>state<TAB>note`, one line per check.
# Needs the GitHub CLI (`gh`), signed in.
# =============================================================================
set -uo pipefail

REPO=""; ROOT=""; PORCELAIN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --root) ROOT="${2:-}"; shift 2 ;;
    --porcelain) PORCELAIN=1; shift ;;
    -h|--help)
      while IFS= read -r line; do
        case "$line" in
          '#!'*) continue ;;
          '#'*) line="${line#\#}"; echo "${line# }" ;;
          *) break ;;
        esac
      done < "$0"
      exit 0 ;;
    *) echo "check-repo-settings: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

# Before the first external command, on purpose: a missing gh must be reported
# as a missing gh, not as whatever the first pipeline happens to print.
command -v gh >/dev/null 2>&1 || {
  echo "check-repo-settings: the GitHub CLI (gh) is not installed or not on PATH - nothing was checked. Install it from https://cli.github.com and run 'gh auth login'." >&2
  exit 2
}

# With --repo and no --root the repository asked about is not this checkout, so
# the one local check is skipped rather than answered from the wrong tree.
LOCAL=1
if [ -z "$ROOT" ]; then
  if [ -n "$REPO" ]; then
    LOCAL=0
  else
    ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
      echo "check-repo-settings: not inside a git repository, and no --root given" >&2; exit 2; }
  fi
fi
if [ "$LOCAL" -eq 1 ] && [ ! -d "$ROOT" ]; then
  echo "check-repo-settings: no such directory: $ROOT" >&2; exit 2
fi

if [ -z "$REPO" ]; then
  REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" || REPO=""
  if [ -z "$REPO" ]; then
    echo "check-repo-settings: could not work out which GitHub repository this is (no GitHub remote, or gh is not signed in: try 'gh auth status') - nothing was checked." >&2
    exit 2
  fi
fi
# The name goes into API paths and into commands printed for a person to paste.
case "$REPO" in
  */*/*|/*|*/|*[!A-Za-z0-9._/-]*) echo "check-repo-settings: '$REPO' is not an OWNER/NAME repository name" >&2; exit 2 ;;
  */*) ;;
  *) echo "check-repo-settings: '$REPO' is not an OWNER/NAME repository name" >&2; exit 2 ;;
esac

# api <path> [jq] -> API_OUT, API_CODE (200 on success, else the HTTP status gh
# reported, or 0 when gh failed without naming one).
API_OUT=""; API_CODE=0
api() {
  local path="$1" jq="${2:-}" err rc=0
  err="$(mktemp 2>/dev/null || mktemp -t reposet)"
  if [ -n "$jq" ]; then
    API_OUT="$(gh api "$path" --jq "$jq" 2>"$err")" || rc=$?
  else
    API_OUT="$(gh api "$path" 2>"$err")" || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    API_CODE=200
  else
    API_CODE="$(sed -n 's/.*(HTTP \([0-9][0-9][0-9]\)).*/\1/p' "$err" | head -n 1)"
    [ -n "$API_CODE" ] || API_CODE=0
    API_OUT="$(head -n 1 "$err")"
  fi
  rm -f "$err"
}

TAB="$(printf '\t')"
RESULTS=""
record() { RESULTS="${RESULTS}${1}${TAB}${2}${TAB}${3}
"; }

# --- the repository itself ---------------------------------------------------
# One call, seven fields, joined with | because an empty TSV field collapses
# under `read`. null becomes the word none, so "absent" stays distinguishable
# from false.
api "repos/$REPO" '[.private, .default_branch, .permissions.admin, .delete_branch_on_merge, .security_and_analysis.dependabot_security_updates.status, .security_and_analysis.secret_scanning.status, .security_and_analysis.secret_scanning_push_protection.status] | map(if . == null then "none" else tostring end) | join("|")'
if [ "$API_CODE" != 200 ]; then
  echo "check-repo-settings: could not read $REPO (${API_OUT:-no response}) - nothing was checked." >&2
  exit 2
fi
PRIVATE=""; BRANCH=""; ADMIN=""; DELETE_ON_MERGE=""; DSU=""; SS=""; PP=""; EXTRA=""
IFS='|' read -r PRIVATE BRANCH ADMIN DELETE_ON_MERGE DSU SS PP EXTRA <<FIELDS
$API_OUT
FIELDS
case "$PRIVATE" in true|false) ;; *) PRIVATE="" ;; esac
if [ -z "$PRIVATE" ] || [ -z "$BRANCH" ] || [ -z "$PP" ] || [ -n "$EXTRA" ]; then
  echo "check-repo-settings: GitHub's answer for $REPO was not in the expected shape - nothing was checked." >&2
  exit 2
fi
if [ "$ADMIN" != true ]; then
  echo "check-repo-settings: you do not have admin access to $REPO. GitHub leaves the security settings out of its answer for anyone else, so they cannot be told apart from 'off' - nothing was checked." >&2
  exit 2
fi

onoff() { # $1 check, $2 value, $3 on-value, $4 off-value, $5 fix
  if [ "$2" = "$3" ]; then record "$1" ON ""
  elif [ "$2" = "$4" ]; then record "$1" OFF "$5"
  else record "$1" UNKNOWN "GitHub returned '${2:-nothing}'"
  fi
}

# --- dependabot alerts: 204 on, 404 off --------------------------------------
api "repos/$REPO/vulnerability-alerts"
case "$API_CODE" in
  200) record dependabot-alerts ON "" ;;
  404) record dependabot-alerts OFF "gh api -X PUT repos/$REPO/vulnerability-alerts" ;;
  *)   record dependabot-alerts UNKNOWN "${API_OUT:-no response}" ;;
esac

onoff dependabot-security-updates "$DSU" enabled disabled \
  "gh api -X PUT repos/$REPO/automated-security-fixes"

# --- secret scanning ----------------------------------------------------------
# Free and automatic on a public repository. On a private one it needs a paid
# GitHub plan, and without that plan the fields are simply absent - which on a
# public repository would be an UNKNOWN, and here is a SKIP.
if [ "$PRIVATE" = true ] && [ "$SS" = none ]; then
  record secret-scanning SKIP "private repository: needs a paid GitHub plan"
  record push-protection SKIP "private repository: needs a paid GitHub plan"
else
  onoff secret-scanning "$SS" enabled disabled \
    "gh api -X PATCH repos/$REPO -f 'security_and_analysis[secret_scanning][status]=enabled'"
  onoff push-protection "$PP" enabled disabled \
    "gh api -X PATCH repos/$REPO -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled'"
fi

# --- default branch -----------------------------------------------------------
# Two routes protect a branch and either is enough: classic branch protection,
# or a ruleset. Asking only one reports a protected branch as bare.
#   classic: 200 protected, 404 not, 403 the plan does not offer it
#   rules:   a count of the active rules that apply to the branch
api "repos/$REPO/branches/$BRANCH/protection" '.url'
CLASSIC="$API_CODE"
api "repos/$REPO/rules/branches/$BRANCH" 'length'
RULES_CODE="$API_CODE"; RULES="$API_OUT"
if [ "$RULES_CODE" = 200 ]; then
  case "$RULES" in ''|*[!0-9]*) RULES_CODE=0 ;; esac
fi
PROTECT_FIX="open https://github.com/$REPO/settings/rules and add a ruleset for the default branch that blocks force pushes and deletion"
if [ "$CLASSIC" = 200 ] || { [ "$RULES_CODE" = 200 ] && [ "$RULES" -gt 0 ]; }; then
  record default-branch-protection ON ""
elif [ "$CLASSIC" = 403 ] && [ "$RULES_CODE" = 403 ]; then
  record default-branch-protection SKIP "your GitHub plan does not offer branch protection on a private repository"
elif { [ "$CLASSIC" = 404 ] || [ "$CLASSIC" = 403 ]; } && [ "$RULES_CODE" = 200 ]; then
  record default-branch-protection OFF "$PROTECT_FIX"
elif [ "$CLASSIC" = 404 ] && [ "$RULES_CODE" = 403 ]; then
  record default-branch-protection OFF "$PROTECT_FIX"
else
  record default-branch-protection UNKNOWN "could not read the branch rules for '$BRANCH'"
fi

onoff delete-branch-on-merge "$DELETE_ON_MERGE" true false \
  "gh api -X PATCH repos/$REPO -F delete_branch_on_merge=true"

# --- workflow token -----------------------------------------------------------
api "repos/$REPO/actions/permissions/workflow" '.default_workflow_permissions'
if [ "$API_CODE" = 200 ]; then
  onoff workflow-token-read-only "$API_OUT" read write \
    "gh api -X PUT repos/$REPO/actions/permissions/workflow -f default_workflow_permissions=read"
else
  record workflow-token-read-only UNKNOWN "${API_OUT:-no response}"
fi

# --- private vulnerability reporting: public repositories only ----------------
if [ "$PRIVATE" = true ]; then
  record private-vulnerability-reporting SKIP "private repository: nobody outside can see it to report on it"
else
  api "repos/$REPO/private-vulnerability-reporting" '.enabled'
  if [ "$API_CODE" = 200 ]; then
    onoff private-vulnerability-reporting "$API_OUT" true false \
      "gh api -X PUT repos/$REPO/private-vulnerability-reporting"
  else
    record private-vulnerability-reporting UNKNOWN "${API_OUT:-no response}"
  fi
fi

# --- dependabot config: a file in the checkout, not a setting -----------------
if [ "$LOCAL" -eq 0 ]; then
  record dependabot-config SKIP "a file check: run this from that repository's checkout, or pass --root"
elif [ -f "$ROOT/.github/dependabot.yml" ] || [ -f "$ROOT/.github/dependabot.yaml" ]; then
  record dependabot-config ON ""
else
  record dependabot-config OFF "add .github/dependabot.yml (the template ships one; see SETUP.md)"
fi

# --- report -------------------------------------------------------------------
OFFS=0; UNKNOWNS=0
while IFS="$TAB" read -r name st note; do
  [ -n "$name" ] || continue
  case "$st" in
    OFF) OFFS=$((OFFS + 1)) ;;
    UNKNOWN) UNKNOWNS=$((UNKNOWNS + 1)) ;;
  esac
  [ "$PORCELAIN" -eq 1 ] && continue
  case "$st" in
    ON)      printf '  on       %s\n' "$name" ;;
    SKIP)    printf '  skipped  %s - %s\n' "$name" "$note" ;;
    UNKNOWN) printf '  UNKNOWN  %s - %s\n' "$name" "$note" ;;
    OFF)     printf '  OFF      %s\n             to turn on: %s\n' "$name" "$note" ;;
  esac
done <<REPORT
$RESULTS
REPORT

if [ "$PORCELAIN" -eq 1 ]; then
  printf '%s' "$RESULTS"
else
  echo
  echo "Repository: $REPO (default branch: $BRANCH)"
  echo "Nothing was changed. This script only reads; each line above is yours to run or not."
  [ "$UNKNOWNS" -eq 0 ] || echo "$UNKNOWNS setting(s) could not be read, so this is not a full report."
fi

[ "$UNKNOWNS" -eq 0 ] || exit 2
[ "$OFFS" -eq 0 ] || exit 1
exit 0
