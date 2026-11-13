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
#                                      (enabled but paused is reported OFF)
#   secret-scanning                    finds keys that were committed
#   push-protection                    refuses the push that contains a key
#   default-branch-protection          no rule lets anyone force-push to or
#                                      delete the default branch. Classic
#                                      protection and rulesets are both read,
#                                      and they add up. A protection that
#                                      allows force pushes, a ruleset that only
#                                      asks for a review, and a ruleset with
#                                      somebody on its bypass list are reported
#                                      OFF: none of them stops everyone.
#   delete-branch-on-merge             merged branches are removed for you
#   workflow-token-read-only           CI's built-in token cannot write by default
#   private-vulnerability-reporting    a private way to report a security bug
#                                      (public repositories only)
#   dependabot-config                  .github/dependabot.yml has at least one
#                                      entry, and the ON line names what it
#                                      watches (a local file check)
#
# States: ON, OFF, SKIP (does not apply, or your GitHub plan does not offer it),
# UNKNOWN (could not be read). A refusal counts as SKIP only when GitHub says
# the plan is the reason; any other refusal is a token that may not look, and
# what it may not see is UNKNOWN. One SKIP is read from an absence instead:
# secret scanning on a private repository, where GitHub leaves the fields out
# for a plan without it and says nothing. That is only reached after the admin
# check below, which is the other reason those fields go missing.
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
# where that repository's checkout is. --root alone checks the repository
# that checkout pushes to, wherever the script was started from.
#
# --porcelain prints `check<TAB>state<TAB>note`, one line per check.
# Needs the GitHub CLI (`gh`), signed in.
# =============================================================================
set -uo pipefail

REPO=""; ROOT=""; PORCELAIN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo|--root)
      # Checked before the shift: `shift 2` with one argument left fails and
      # shifts nothing, and this loop would then read the same option for ever.
      if [ $# -lt 2 ] || [ -z "$2" ]; then
        echo "check-repo-settings: $1 needs a value" >&2; exit 2
      fi
      case "$1" in --repo) REPO="$2" ;; --root) ROOT="$2" ;; esac
      shift 2 ;;
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
  # From inside the checkout, so --root reads the settings and the file of the
  # same repository. (ROOT is always set here: by --root, or by git above.)
  REPO="$(cd "$ROOT" 2>/dev/null && gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" || REPO=""
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
  # stdin from /dev/null: one caller sits inside a `while read` loop, and gh
  # must not be handed the lines that loop is reading.
  if [ -n "$jq" ]; then
    API_OUT="$(gh api "$path" --jq "$jq" 2>"$err" </dev/null)" || rc=$?
  else
    API_OUT="$(gh api "$path" 2>"$err" </dev/null)" || rc=$?
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
# One call, six fields, joined with | because an empty TSV field collapses
# under `read`. null becomes the word none, so "absent" stays distinguishable
# from false.
api "repos/$REPO" '[.private, .default_branch, .permissions.admin, .delete_branch_on_merge, .security_and_analysis.secret_scanning.status, .security_and_analysis.secret_scanning_push_protection.status] | map(if . == null then "none" else tostring end) | join("|")'
if [ "$API_CODE" != 200 ]; then
  echo "check-repo-settings: could not read $REPO (${API_OUT:-no response}) - nothing was checked." >&2
  exit 2
fi
PRIVATE=""; BRANCH=""; ADMIN=""; DELETE_ON_MERGE=""; SS=""; PP=""; EXTRA=""
IFS='|' read -r PRIVATE BRANCH ADMIN DELETE_ON_MERGE SS PP EXTRA <<FIELDS
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

# The branch name goes into two API paths as it stands. GitHub allows
# characters in a branch name that change what a URL means (`#`, `?`, `%`), so
# a name outside the plain set is never sent: asking about another path and
# reporting its answer would be worse than not asking.
BRANCH_OK=1
case "$BRANCH" in *[!A-Za-z0-9._/-]*) BRANCH_OK=0 ;; esac
branch_api() { # as api, or no call at all when the name cannot be sent
  if [ "$BRANCH_OK" -eq 1 ]; then api "$@"; else API_OUT=""; API_CODE=0; fi
}

onoff() { # $1 check, $2 value, $3 on-value, $4 off-value, $5 fix
  if [ "$2" = "$3" ]; then record "$1" ON ""
  elif [ "$2" = "$4" ]; then record "$1" OFF "$5"
  else record "$1" UNKNOWN "GitHub returned '${2:-nothing}'"
  fi
}

# --- dependabot alerts: 204 on, 404 "Vulnerability alerts are disabled." off --
# A 404 counts as off only with that message. GitHub can also answer 404 to a
# token that may not look, and that is not the same fact.
api "repos/$REPO/vulnerability-alerts"
case "$API_CODE" in
  200) record dependabot-alerts ON "" ;;
  404)
    case "$API_OUT" in
      *"alerts are disabled"*) record dependabot-alerts OFF "gh api -X PUT repos/$REPO/vulnerability-alerts" ;;
      *) record dependabot-alerts UNKNOWN "${API_OUT:-no response}" ;;
    esac ;;
  *)   record dependabot-alerts UNKNOWN "${API_OUT:-no response}" ;;
esac

# --- dependabot security updates ----------------------------------------------
# From its own endpoint, not from the repository's security block: GitHub
# leaves that whole block out for a private repository on a plan without
# secret scanning, and this setting does not depend on that plan. Two fields,
# because a paused setting still answers enabled:true and opens nothing.
# GitHub pauses it by itself when a Dependabot pull request has been open for
# 90 days with nobody acting on one, and resumes it when somebody does.
api "repos/$REPO/automated-security-fixes" '[.enabled, .paused] | map(if . == null then "none" else tostring end) | join("|")'
if [ "$API_CODE" = 200 ]; then
  case "$API_OUT" in
    'true|false') record dependabot-security-updates ON "" ;;
    'true|true')  record dependabot-security-updates OFF "merge or close one of Dependabot's open pull requests and GitHub resumes them (they are enabled but paused: GitHub pauses them when its pull requests sit untouched for 90 days)" ;;
    'false|'*)    record dependabot-security-updates OFF "gh api -X PUT repos/$REPO/automated-security-fixes" ;;
    *)            record dependabot-security-updates UNKNOWN "GitHub returned '${API_OUT:-nothing}'" ;;
  esac
else
  record dependabot-security-updates UNKNOWN "${API_OUT:-no response}"
fi

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
# The question is narrow: can anyone force-push to the default branch, or
# delete it? Two routes can say no, classic branch protection and rulesets, and
# they add up - one may stop force pushes while the other stops deletion.
# Asking only one reports a protected branch as bare. Counting either as
# "protected" because it exists reports a bare branch as protected: a classic
# protection can allow force pushes, a ruleset can hold nothing but a review
# rule, and a ruleset can name people who may bypass it.
#
# Each route ends up read, absent, plan (GitHub says the plan does not offer
# it) or unreadable, and only affirmative evidence moves it off unreadable:
#   classic  200 with both allow fields -> read
#            404 "Branch not protected" -> absent
#   rules    200 with a list of rules, every page of it -> read (an empty
#            list is a read, not an absence)
#   either   403 on a private repository whose message names the plan -> plan
# A 403 that does not name the plan is a token that may not look. The
# protection may be there, so that is unreadable, never a SKIP.
#
# What is not read: an organisation's custom roles. GitHub says a role with
# the "bypass branch protections" permission is exempt from a classic
# protection's restrictions, and this script cannot see who holds one.
plan_refusal() { # $1 status, $2 gh's message
  [ "$PRIVATE" = true ] && [ "$1" = 403 ] || return 1
  case "$2" in *"Upgrade to GitHub"*) return 0 ;; esac
  return 1
}

# Classic. allow_force_pushes and allow_deletions say whether each is ALLOWED
# (true means open). GitHub's settings page lists both under "Rules applied to
# everyone including administrators", so they count as they stand. lock_branch
# makes the branch read-only and undeletable, but it sits with the settings an
# administrator bypasses unless enforce_admins ("Do not allow bypassing the
# above settings") is on, so a lock counts only with it. A lock or enforce
# field that is absent counts as false: either can only add protection.
C_STATE=unreadable; C_FORCE=""; C_DELETE=""; C_LOCK=""; C_ENFORCE=""; C_EXTRA=""
branch_api "repos/$REPO/branches/$BRANCH/protection" '[.allow_force_pushes.enabled, .allow_deletions.enabled, .lock_branch.enabled, .enforce_admins.enabled] | map(if . == null then "none" else tostring end) | join("|")'
case "$API_CODE" in
  200)
    IFS='|' read -r C_FORCE C_DELETE C_LOCK C_ENFORCE C_EXTRA <<FIELDS
$API_OUT
FIELDS
    case "$C_FORCE/$C_DELETE" in
      true/true|true/false|false/true|false/false)
        [ -n "$C_ENFORCE" ] && [ -z "$C_EXTRA" ] && C_STATE="read" ;;
    esac ;;
  404) case "$API_OUT" in *"Branch not protected"*) C_STATE=absent ;; esac ;;
  403) plan_refusal "$API_CODE" "$API_OUT" && C_STATE=plan ;;
esac

# Rules: the active rules that apply to the branch, every page of them. Each
# page comes back as a count of its entries, then one `type ruleset-id` line
# per blocking rule. An entry that is not a rule, or a blocking rule that does
# not say which ruleset it is from, fails the read: an answer this script does
# not understand is not an answer with no blocking rule in it. GitHub sends 30
# entries a page unless asked, and a first page with no blocking rule says
# nothing about the next one. Ten pages of a hundred is the cap, so a server
# that never sends a short page cannot keep this running.
R_STATE=unreadable; R_RULES=""
# shellcheck disable=SC2016  # $r is jq's variable, not the shell's
RULES_JQ='if type == "array" then (map(if type == "object" and (.type | type) == "string" then . else error("an entry that is not a rule") end)) as $r | [($r | length | tostring)] + [$r[] | select(.type == "non_fast_forward" or .type == "deletion") | if (.ruleset_id | type) == "number" then "\(.type) \(.ruleset_id)" else error("a rule with no ruleset") end] | join("\n") else error("not a list") end'
page=1
while [ "$page" -le 10 ]; do
  branch_api "repos/$REPO/rules/branches/$BRANCH?per_page=100&page=$page" "$RULES_JQ"
  if [ "$API_CODE" != 200 ]; then
    [ "$page" -eq 1 ] && plan_refusal "$API_CODE" "$API_OUT" && R_STATE=plan
    break
  fi
  count="$(printf '%s\n' "$API_OUT" | head -n 1)"
  case "$count" in ''|*[!0-9]*) break ;; esac
  R_RULES="$R_RULES$(printf '%s\n' "$API_OUT" | tail -n +2)
"
  if [ "$count" -lt 100 ]; then R_STATE="read"; break; fi
  page=$((page + 1))
done

# A ruleset can name people, teams, roles or apps that may bypass it, and a
# rule they can walk past does not stop everyone. So each ruleset holding a
# blocking rule is read once, and its rules count only when the bypass list is
# there and nobody on it can push past the rules. `pull_request` is the one
# bypass that does not matter here: GitHub says such an actor can bypass rules
# only on pull requests, which is neither a force-push nor a deletion. Any
# other mode, or none given, counts as a way through.
# GitHub leaves the list out for someone who may not edit the ruleset (one set
# above the repository, for example). Absent is not empty: that is unread.
# bypass_for <ruleset id> -> BYPASS: none, some or unread.
BYPASS=""; RS_SEEN=""
bypass_for() {
  local id="$1" v
  case "$RS_SEEN " in
    *" $id="*) v="${RS_SEEN#* "$id"=}"; BYPASS="${v%% *}"; return ;;
  esac
  BYPASS=unread
  api "repos/$REPO/rulesets/$id" 'if (.bypass_actors | type) == "array" then [.bypass_actors[] | select(.bypass_mode != "pull_request")] | length | tostring else error("no bypass list") end'
  if [ "$API_CODE" = 200 ]; then
    case "$API_OUT" in
      0) BYPASS=none ;;
      ''|*[!0-9]*) ;;
      *) BYPASS=some ;;
    esac
  fi
  RS_SEEN="$RS_SEEN $id=$BYPASS"
}
add_id() { # $1 list, $2 id -> ADDED: the list with the id in it once
  case " $1 " in *" $2 "*) ADDED="$1" ;; *) ADDED="${1:+$1 }$2" ;; esac
}
R_FORCE=0; R_DELETE=0; R_BYPASSED=""; R_UNREAD=""; ADDED=""
if [ "$R_STATE" = read ]; then
  while read -r rtype rid; do
    [ -n "$rtype" ] || continue
    case "$rid" in ''|*[!0-9]*) R_STATE=unreadable; break ;; esac
    bypass_for "$rid"
    case "$BYPASS" in
      none) case "$rtype" in non_fast_forward) R_FORCE=1 ;; deletion) R_DELETE=1 ;; esac ;;
      some) add_id "$R_BYPASSED" "$rid"; R_BYPASSED="$ADDED" ;;
      *)    add_id "$R_UNREAD" "$rid"; R_UNREAD="$ADDED" ;;
    esac
  done <<RULES
$R_RULES
RULES
fi

FORCE_BLOCKED=0; DELETE_BLOCKED=0; C_LOCKED=0
if [ "$C_STATE" = read ]; then
  [ "$C_LOCK" = true ] && [ "$C_ENFORCE" = true ] && C_LOCKED=1
  { [ "$C_FORCE" = false ] || [ "$C_LOCKED" -eq 1 ]; } && FORCE_BLOCKED=1
  { [ "$C_DELETE" = false ] || [ "$C_LOCKED" -eq 1 ]; } && DELETE_BLOCKED=1
fi
if [ "$R_STATE" = read ]; then
  [ "$R_FORCE" -eq 1 ] && FORCE_BLOCKED=1
  [ "$R_DELETE" -eq 1 ] && DELETE_BLOCKED=1
fi
OPEN=""
[ "$FORCE_BLOCKED" -eq 1 ] || OPEN="force pushes are allowed"
[ "$DELETE_BLOCKED" -eq 1 ] || OPEN="${OPEN:+$OPEN, }deletion is allowed"
# Why a protection that is there did not count, for the OFF line.
WHY=""
[ -z "$R_BYPASSED" ] || WHY="; ruleset $R_BYPASSED would block this but has a bypass list, and whoever is on it can still do it"
if [ "$C_STATE" = read ] && [ "$C_LOCK" = true ] && [ "$C_LOCKED" -eq 0 ]; then
  WHY="$WHY; the branch is locked, but administrators can bypass the lock"
fi
PROTECT_FIX="open https://github.com/$REPO/settings/rules and add a ruleset for the default branch that blocks force pushes and deletion, with its enforcement set to Active and nobody on its bypass list"
if [ -z "$OPEN" ]; then
  # Both blocked by what could be read. An unreadable route cannot undo that.
  record default-branch-protection ON ""
elif [ "$C_STATE" = unreadable ] || [ "$R_STATE" = unreadable ]; then
  # The route that could not be read may be the one doing the blocking.
  if [ "$BRANCH_OK" -eq 1 ]; then
    record default-branch-protection UNKNOWN "could not read the branch rules for '$BRANCH'"
  else
    record default-branch-protection UNKNOWN "the branch name '$BRANCH' has a character this script will not put in a URL - look at https://github.com/$REPO/settings/branches yourself"
  fi
elif [ -n "$R_UNREAD" ]; then
  # A blocking rule is there, and whether anyone may walk past it is not known.
  record default-branch-protection UNKNOWN "could not read the bypass list of ruleset $R_UNREAD, so its rules may not bind everyone - look at https://github.com/$REPO/settings/rules yourself"
elif [ "$C_STATE" = plan ] && [ "$R_STATE" = plan ]; then
  record default-branch-protection SKIP "your GitHub plan does not offer branch protection on a private repository"
else
  record default-branch-protection OFF "$PROTECT_FIX (now: $OPEN$WHY)"
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
  # The file being there does not mean it watches anything, and the template
  # ships one that watches only its own CI's actions. So ON names what is
  # watched, and a file with no entry is OFF. Comment lines do not count.
  DEP_FILE="$ROOT/.github/dependabot.yml"
  [ -f "$DEP_FILE" ] || DEP_FILE="$ROOT/.github/dependabot.yaml"
  WATCHES="$(sed -n 's/^[[:space:]]*-\{0,1\}[[:space:]]*package-ecosystem:[[:space:]]*//p' "$DEP_FILE" \
    | tr -d "\"'\r" | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//' | tr '\n' ' ' | sed 's/ *$//')"
  if [ -n "$WATCHES" ]; then
    record dependabot-config ON "watches: $WATCHES"
  else
    record dependabot-config OFF "$DEP_FILE has no package-ecosystem entry, so it watches nothing - add one (the comments in the template's file show how)"
  fi
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
    ON)      if [ -n "$note" ]; then printf '  on       %s - %s\n' "$name" "$note"
             else printf '  on       %s\n' "$name"; fi ;;
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
