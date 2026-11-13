#!/usr/bin/env bash
# =============================================================================
# check-repo-settings.sh - which of this GitHub repository's safety settings
# are off?
# =============================================================================
# READ-ONLY. Every request is a plain `gh api <path>`, which gh sends as a GET,
# and gh is asked for nothing else. It prints the command that would
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
#                                      entry, every entry has the keys GitHub
#                                      requires (a directory, and a schedule
#                                      or a group that has one), and the ON
#                                      line names what it watches. A local
#                                      file check, read as text: GitHub's own
#                                      verdict on the file is not asked for
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
# With no arguments it checks the repository this checkout pushes to: the
# push address of its `origin` remote, which has to be on github.com. --repo
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
  # The repository this checkout pushes to: the push address of its `origin`
  # remote, as git gives it, read from inside --root's checkout so the settings
  # and the file are the same repository's. (ROOT is always set here: by
  # --root, or by git above.)
  # gh is not asked. In a checkout that also has a remote named `upstream`, as
  # every fork does, `gh repo view` answers for that one (seen with gh 2.89.0),
  # and the report would be the parent project's settings under this one's
  # name.
  # Only a github.com address is taken. Any other host, an SSH alias included,
  # is not guessed at: gh would be asked about a repository of the same name on
  # github.com, which is a different one. The address is never printed: an
  # https one can carry a token.
  URL="$(git -C "$ROOT" remote get-url --push origin 2>/dev/null)" || URL=""
  case "$URL" in
    https://*)
      REST="${URL#https://}"; HOST="${REST%%/*}"
      case "$HOST" in github.com|*@github.com) REPO="${REST#*/}" ;; esac ;;
    ssh://git@github.com/*) REPO="${URL#ssh://git@github.com/}" ;;
    git@github.com:*) REPO="${URL#git@github.com:}" ;;
  esac
  REPO="${REPO%/}"; REPO="${REPO%.git}"
  if [ -z "$REPO" ]; then
    echo "check-repo-settings: could not work out which GitHub repository this checkout pushes to: it has no 'origin' remote, or that remote is not a github.com address. Nothing was checked. Name the repository yourself: --repo OWNER/NAME" >&2
    exit 2
  fi
  # gh sends its requests to $GH_HOST when that is set, and the address just
  # read is on github.com.
  case "${GH_HOST:-github.com}" in
    github.com) ;;
    *) echo "check-repo-settings: GH_HOST points gh at '$GH_HOST', and this checkout's origin is on github.com. Nothing was checked. Unset GH_HOST, or name the repository yourself: --repo OWNER/NAME" >&2
       exit 2 ;;
  esac
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
# One call, seven fields, joined with | because an empty TSV field collapses
# under `read`. null becomes the word none, so "absent" stays distinguishable
# from false.
api "repos/$REPO" '[.full_name, .private, .default_branch, .permissions.admin, .delete_branch_on_merge, .security_and_analysis.secret_scanning.status, .security_and_analysis.secret_scanning_push_protection.status] | map(if . == null then "none" else tostring end) | join("|")'
if [ "$API_CODE" != 200 ]; then
  echo "check-repo-settings: could not read $REPO (${API_OUT:-no response}) - nothing was checked." >&2
  exit 2
fi
FULL=""; PRIVATE=""; BRANCH=""; ADMIN=""; DELETE_ON_MERGE=""; SS=""; PP=""; EXTRA=""
IFS='|' read -r FULL PRIVATE BRANCH ADMIN DELETE_ON_MERGE SS PP EXTRA <<FIELDS
$API_OUT
FIELDS
case "$PRIVATE" in true|false) ;; *) PRIVATE="" ;; esac
# The name as GitHub has it now. It goes into API paths and printed commands,
# so it is held to the same shape as a name given by hand.
case "$FULL" in
  */*/*|/*|*/|*[!A-Za-z0-9._/-]*) FULL="" ;;
  */*) ;;
  *) FULL="" ;;
esac
if [ -z "$FULL" ] || [ -z "$PRIVATE" ] || [ -z "$BRANCH" ] || [ -z "$PP" ] || [ -n "$EXTRA" ]; then
  echo "check-repo-settings: GitHub's answer for $REPO was not in the expected shape - nothing was checked." >&2
  exit 2
fi
# GitHub answers under an old name after a rename or a move. Everything from
# here on, the printed commands included, uses the name the repository has now.
REPO="$FULL"
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

# Rules: the active rules that apply to the branch, every page of them. Three
# types count. `non_fast_forward` blocks force pushes and `deletion` blocks
# deletion. `update` ("Restrict updates") lets only people with bypass
# permission push to the branch at all, which stops a force push with every
# other push and says nothing about deletion. `pull_request` is not counted:
# it stops commits arriving outside a pull request, and whether it stops a
# push that only moves the branch backwards was not established.
# Each page comes back as a count of its entries, then one `type ruleset-id`
# line per blocking rule. An entry that is not a rule, or a blocking rule that does
# not say which ruleset it is from, fails the read: an answer this script does
# not understand is not an answer with no blocking rule in it. GitHub sends 30
# entries a page unless asked, and a first page with no blocking rule says
# nothing about the next one. Ten pages of a hundred is the cap, so a server
# that never sends a short page cannot keep this running.
R_STATE=unreadable; R_RULES=""
# shellcheck disable=SC2016  # $r is jq's variable, not the shell's
RULES_JQ='if type == "array" then (map(if type == "object" and (.type | type) == "string" then . else error("an entry that is not a rule") end)) as $r | [($r | length | tostring)] + [$r[] | select(.type == "non_fast_forward" or .type == "update" or .type == "deletion") | if (.ruleset_id | type) == "number" then "\(.type) \(.ruleset_id)" else error("a rule with no ruleset") end] | join("\n") else error("not a list") end'
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
# blocking rule is read once. `pull_request` is the one bypass that does not
# matter here: GitHub says such an actor can bypass rules only on pull
# requests, which is neither a force-push nor a deletion. Any other mode, or
# none given, counts as a way through.
# GitHub leaves the list out for someone who may not edit the ruleset (one set
# above the repository, for example). Absent is not empty: that is unread.
# bypass_for <ruleset id> -> BYPASS: `-` when nobody can push past it, `?`
# when the list could not be read, else who can, as `type:id` entries joined
# with commas. jq percent-encodes each entry (@uri), so whatever GitHub sends,
# no entry holds a comma or a space, and two entries are compared whole.
BYPASS=""; RS_SEEN=""
bypass_for() {
  local id="$1" v
  case "$RS_SEEN " in
    *" $id="*) v="${RS_SEEN#* "$id"=}"; BYPASS="${v%% *}"; return ;;
  esac
  BYPASS='?'
  api "repos/$REPO/rulesets/$id" 'if (.bypass_actors | type) == "array" then [.bypass_actors[] | select(.bypass_mode != "pull_request") | "\(.actor_type):\(.actor_id)" | @uri] | join(",") else error("no bypass list") end'
  [ "$API_CODE" = 200 ] && BYPASS="${API_OUT:--}"
  RS_SEEN="$RS_SEEN $id=$BYPASS"
}

# Rulesets layer: every one that applies is enforced, so somebody gets past a
# rule only by being on the bypass list of EVERY ruleset that holds it. For
# each question (force pushes, deletion) the rulesets that hold a rule for it
# come out as one of:
#   blocked   one of them has nobody who can push past it
#   bypassed  each has a list, and one entry is on all of them: whoever that
#             entry is can still do it
#   unsure    each has a list and no entry is on all of them. Two different
#             entries can still be the same person (a team and a role, say),
#             and this script cannot see inside either
#   unread    none is clean, and at least one list could not be read
#   none      no ruleset holds such a rule
# kind <rule type>... -> K_ST, and K_IDS: the rulesets it is about.
K_ST=none; K_IDS=""
kind() {
  local rtype rid a keep seen="" lists="" unread="" common="" blocked=0
  while read -r rtype rid; do
    case " $* " in *" $rtype "*) ;; *) continue ;; esac
    case " $seen " in *" $rid "*) continue ;; esac
    seen="$seen $rid"
    bypass_for "$rid"
    case "$BYPASS" in
      -)  blocked=1 ;;
      \?) unread="${unread:+$unread }$rid" ;;
      *)
        if [ -z "$lists" ]; then
          common="$BYPASS"
        else
          keep=""
          for a in $(printf '%s' "$common" | tr ',' ' '); do
            case ",$BYPASS," in *",$a,"*) keep="${keep:+$keep,}$a" ;; esac
          done
          common="$keep"
        fi
        lists="${lists:+$lists }$rid" ;;
    esac
  done <<RULES
$R_RULES
RULES
  K_IDS=""
  if [ "$blocked" -eq 1 ]; then K_ST=blocked
  elif [ -n "$unread" ]; then K_ST=unread; K_IDS="$unread"
  elif [ -z "$lists" ]; then K_ST=none
  elif [ -n "$common" ]; then K_ST=bypassed; K_IDS="$lists"
  else K_ST=unsure; K_IDS="$lists"
  fi
}

F_ST=none; F_IDS=""; D_ST=none; D_IDS=""; C_LOCKED=0
if [ "$R_STATE" = read ]; then
  kind non_fast_forward update; F_ST="$K_ST"; F_IDS="$K_IDS"
  kind deletion; D_ST="$K_ST"; D_IDS="$K_IDS"
fi
if [ "$C_STATE" = read ]; then
  [ "$C_LOCK" = true ] && [ "$C_ENFORCE" = true ] && C_LOCKED=1
  { [ "$C_FORCE" = false ] || [ "$C_LOCKED" -eq 1 ]; } && F_ST=blocked
  { [ "$C_DELETE" = false ] || [ "$C_LOCKED" -eq 1 ]; } && D_ST=blocked
fi

# What goes on the line. OPEN is what is certainly allowed, WHY names a
# protection that is there and did not count, and HOLE is what could not be
# settled.
OPEN=""; WHY=""; HOLE=""
tell() { # $1 status, $2 its rulesets, $3 and $4 the words for what it is about
  case "$1" in
    none) OPEN="${OPEN:+$OPEN, }$3 allowed" ;;
    bypassed)
      OPEN="${OPEN:+$OPEN, }$3 allowed"
      case "$2" in
        *' '*) WHY="$WHY; rulesets $2 each block $4, but one entry is on the bypass list of every one of them, and whoever that is can still get past" ;;
        *)     WHY="$WHY; ruleset $2 blocks $4 but has a bypass list, and whoever is on it can still get past" ;;
      esac ;;
    unread) HOLE="${HOLE:+$HOLE; }could not read the bypass list of ruleset $2, so whether it stops $4 for everyone is not known" ;;
    unsure) HOLE="${HOLE:+$HOLE; }rulesets $2 each block $4 and each has a bypass list, with no entry on all of them; whether one person is on every list cannot be read from here" ;;
  esac
}
tell "$F_ST" "$F_IDS" "force pushes are" "force pushes"
tell "$D_ST" "$D_IDS" "deletion is" "deletion"
if [ "$C_STATE" = read ] && [ "$C_LOCK" = true ] && [ "$C_LOCKED" -eq 0 ]; then
  WHY="$WHY; the branch is locked, but administrators can bypass the lock"
fi
PROTECT_FIX="open https://github.com/$REPO/settings/rules and add a ruleset for the default branch that blocks force pushes and deletion, with its enforcement set to Active and nobody on its bypass list"
if [ "$F_ST" = blocked ] && [ "$D_ST" = blocked ]; then
  # Both blocked by what could be read. An unreadable route cannot undo that.
  record default-branch-protection ON ""
elif [ "$C_STATE" = unreadable ] || [ "$R_STATE" = unreadable ]; then
  # The route that could not be read may be the one doing the blocking.
  if [ "$BRANCH_OK" -eq 1 ]; then
    record default-branch-protection UNKNOWN "could not read the branch rules for '$BRANCH'"
  else
    record default-branch-protection UNKNOWN "the branch name '$BRANCH' has a character this script will not put in a URL - look at https://github.com/$REPO/settings/branches yourself"
  fi
elif [ "$C_STATE" = plan ] && [ "$R_STATE" = plan ]; then
  record default-branch-protection SKIP "your GitHub plan does not offer branch protection on a private repository"
elif [ -n "$OPEN" ]; then
  # Something is certainly open. A hole beside it does not make that unknown.
  record default-branch-protection OFF "$PROTECT_FIX (now: $OPEN$WHY${HOLE:+; $HOLE})"
else
  # Nothing is certainly open, and at least one question could not be settled.
  record default-branch-protection UNKNOWN "$HOLE - look at https://github.com/$REPO/settings/rules yourself"
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
  # watched, and a file with no entry is OFF. So is one with an entry GitHub
  # would refuse: it requires a directory and a schedule interval on each (an
  # entry in a multi-ecosystem group takes the group's schedule), and an entry
  # without them opens no pull request.
  # The file is read as text, not parsed as YAML. An entry is a `-` item
  # under `updates:`, and its keys are looked for on the lines down to the
  # next item at that depth. Comment lines do not count. A YAML anchor is not
  # followed, so an entry that looks incomplete in a file that uses one is
  # UNKNOWN rather than OFF. The third line awk prints is 0 or 1, and anything
  # else there means the file was not read at all.
  DEP_FILE="$ROOT/.github/dependabot.yml"
  [ -f "$DEP_FILE" ] || DEP_FILE="$ROOT/.github/dependabot.yaml"
  DEP_READ="$(awk -v q="'" '
    function lacks(what) { problems = problems (problems == "" ? "" : "; ") what }
    function flush() {
      if (!initem) return
      n++
      if (eco == "") lacks("entry " n " names no package-ecosystem")
      else {
        names = names (names == "" ? "" : " ") eco
        if (!dir) lacks("the entry for " eco " has no directory")
        if (!sched) lacks("the entry for " eco " has no schedule interval")
      }
      initem = 0; eco = ""; dir = 0; sched = 0
    }
    {
      line = $0
      sub(/\r$/, "", line)
      if (line ~ /^[ \t]*(#|$)/) next
      if (line ~ /<<[ \t]*:/ || line ~ /[:-][ \t]+\*[A-Za-z0-9_-]/) anchor = 1
      match(line, /^ */); ind = RLENGTH
      dash = (substr(line, ind + 1, 1) == "-")
      if (where == 0) {
        if (line ~ /^ *updates[ \t]*:[ \t]*(#.*)?$/) { where = 1; depth = -1 }
        next
      }
      if (where == 2) next
      if (depth < 0) { if (dash) depth = ind; else { where = 2; next } }
      if (ind < depth || (ind == depth && !dash)) { flush(); where = 2; next }
      if (ind == depth) { flush(); initem = 1 }
      key = line
      sub(/^ *(-[ \t]*)?/, "", key)
      if (key ~ /^package-ecosystem[ \t]*:/) {
        eco = key
        sub(/^package-ecosystem[ \t]*:[ \t]*/, "", eco)
        sub(/[ \t]+#.*$/, "", eco)
        gsub("[\"" q "]", "", eco)
        sub(/[ \t]+$/, "", eco)
      }
      if (key ~ /^(directory|directories)[ \t]*:/) dir = 1
      if (key ~ /^multi-ecosystem-group[ \t]*:/) sched = 1
      if (key ~ /(^|[{,][ \t]*)interval[ \t]*:/) sched = 1
    }
    END { flush(); print names; print problems; print anchor + 0 }
  ' "$DEP_FILE" 2>/dev/null)"
  WATCHES=""; DEP_LACKS=""; DEP_ANCHOR=""
  { IFS= read -r WATCHES; IFS= read -r DEP_LACKS; IFS= read -r DEP_ANCHOR; } <<DEP
$DEP_READ
DEP
  case "$DEP_ANCHOR" in
    0|1)
      if [ -n "$DEP_LACKS" ] && [ "$DEP_ANCHOR" = 1 ]; then
        record dependabot-config UNKNOWN "$DEP_LACKS, as far as this script reads the file - but the file uses a YAML anchor, which it does not follow, so the entry may be complete"
      elif [ -n "$DEP_LACKS" ]; then
        record dependabot-config OFF "$DEP_FILE: $DEP_LACKS. GitHub requires a directory and a schedule interval on every entry - add what is missing (the template's file shows a whole entry)"
      elif [ -n "$WATCHES" ]; then
        record dependabot-config ON "watches: $WATCHES"
      else
        record dependabot-config OFF "$DEP_FILE has no package-ecosystem entry, so it watches nothing - add one (the comments in the template's file show how)"
      fi ;;
    *) record dependabot-config UNKNOWN "could not read $DEP_FILE" ;;
  esac
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
