#!/usr/bin/env bash
# =============================================================================
# trellis-survey.sh - what this copy actually has, and what is actually wired
# =============================================================================
# READ-ONLY. It writes nothing, deletes nothing, and fixes nothing. Everything
# it finds is reported for a person to decide about.
#
# The question it answers is not "what does the template ship" - the README says
# that. It is "what does THIS copy still have, and is any of it running?", which
# drifts apart from the first answer within a week of setup. Someone deletes a
# skill and leaves its Cursor router behind. Someone adds a hook script and
# never wires it into settings.json. A git hook loses its executable bit and git
# skips it with no output. Setup gets abandoned three steps in and fourteen
# FILL-IN markers stay in AGENTS.md forever.
#
# Every one of those looks EXACTLY like a working setup from the outside, which
# is the failure this whole template keeps legislating against: a guardrail that
# stops running and says nothing is worse than one that fails loudly. Nothing
# else in here notices any of them, because the hooks that would notice are the
# ones that are not running.
#
# Exit: 0 nothing to report / 1 findings / 2 could not run.
# 2 never means clean. A survey that could not read the tree found nothing
# because it looked at nothing.
#
# Usage:
#   trellis-survey.sh [--root DIR] [--porcelain]
# =============================================================================
set -uo pipefail

CR=$(printf '\r')
ROOT=""; PORCELAIN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --porcelain) PORCELAIN=1; shift ;;
    -h|--help) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "trellis-survey: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "trellis-survey: not inside a git repository, and no --root given" >&2; exit 2; }
fi
[ -d "$ROOT" ] || { echo "trellis-survey: no such directory: $ROOT" >&2; exit 2; }

work="$(mktemp -d 2>/dev/null || mktemp -d -t trellissurvey)"
trap 'rm -rf "$work"' EXIT
: > "$work/findings"

# kind <TAB> subject <TAB> note
finding() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$work/findings"; }

# A survey that examined nothing must not report clean. Each section that CAN
# run bumps this; if none did, the answer is 2 rather than 0.
examined=0

# --- 1. skills and their Cursor routers -------------------------------------
# A skill with no router is invisible to Cursor; a router pointing at a skill
# that was deleted is a dangling pointer that fails only when someone uses it.
if [ -d "$ROOT/.claude/skills" ] || [ -d "$ROOT/.cursor/skills" ]; then
  examined=$((examined + 1))
  for canon in "$ROOT"/.claude/skills/*/SKILL.md; do
    [ -e "$canon" ] || continue
    name="$(basename "$(dirname "$canon")")"
    [ -e "$ROOT/.cursor/skills/$name/SKILL.md" ] \
      || finding "skill-no-router" "$name" "Claude can use it; Cursor cannot see it"
  done
  for canon in "$ROOT"/.claude/commands/*.md; do
    [ -e "$canon" ] || continue
    name="$(basename "$canon" .md)"
    [ -e "$ROOT/.cursor/skills/$name/SKILL.md" ] \
      || finding "command-no-router" "$name" "Claude can use it; Cursor cannot see it"
  done
  for router in "$ROOT"/.cursor/skills/*/SKILL.md; do
    [ -e "$router" ] || continue
    name="$(basename "$(dirname "$router")")"
    [ -e "$ROOT/.claude/skills/$name/SKILL.md" ] || [ -e "$ROOT/.claude/commands/$name.md" ] \
      || finding "router-dangling" "$name" "router points at a skill that is not here"
  done
fi

# --- 2. hook scripts: present vs wired --------------------------------------
# Matched by BASENAME against settings.json, not by parsing JSON, because there
# is no jq guarantee on a fresh machine and a missing jq must not turn this
# section into a silent pass. The cost is that a hook wired under a different
# path but the same basename reads as wired; that is stated rather than hidden.
#
# The two directions are checked SEPARATELY. They were once behind a single
# `&&`, so either side going missing skipped BOTH: delete .claude/hooks/ while
# settings.json still names those scripts, and the survey came back clean while
# the harness called a hook that did not exist on every tool call. One-sided
# drift is exactly what this section is for, so a condition requiring both
# sides to be present was the wrong shape.
SETTINGS="$ROOT/.claude/settings.json"
settings_text=""
[ -f "$SETTINGS" ] && settings_text="$(tr -d "$CR" < "$SETTINGS")"

# Direction one: a script on disk that nothing invokes. Inert, not dangerous,
# but it reads as protection that does not exist.
if [ -d "$ROOT/.claude/hooks" ]; then
  examined=$((examined + 1))
  for h in "$ROOT"/.claude/hooks/*.sh; do
    [ -e "$h" ] || continue
    base="$(basename "$h")"
    case "$base" in hook-file-path.sh) continue ;; esac   # a helper, sourced by others
    printf '%s' "$settings_text" | grep -qF "$base" \
      || finding "hook-unwired" ".claude/hooks/$base" "on disk but nothing in settings.json runs it"
  done
fi

# Direction two: settings.json naming a script that is not here. Worse - the
# harness tries to run it, the hook does nothing, and nothing says so.
#
# Written as a for-loop over command substitution rather than the obvious
# `grep ... | while read`, because a pipeline runs its last stage in a
# SUBSHELL: every `finding` call inside one appends to the temp file from a
# child, and on a shell where that child's writes are buffered or the file is
# reopened, the parent reads none of them back. A check that collects findings
# nobody can see is indistinguishable from a clean result.
if [ -n "$settings_text" ]; then
  examined=$((examined + 1))
  for ref in $(printf '%s' "$settings_text" | grep -o '[A-Za-z0-9_-]*\.sh' | sort -u); do
    found=0
    for cand in "$ROOT/.claude/hooks/$ref" "$ROOT/brain/hooks/$ref" "$ROOT/bin/$ref"; do
      [ -e "$cand" ] && found=1 && break
    done
    [ "$found" -eq 1 ] || finding "hook-missing" "$ref" "settings.json runs it; it is not in the tree"
  done
fi

# --- 3. git hooks: installed and executable ---------------------------------
# git runs a missing or non-executable hook as exit 0 with NO output. Nothing
# inside a hook can report this, which is exactly why it is surveyed here.
if [ -d "$ROOT/.githooks" ]; then
  examined=$((examined + 1))
  hookspath="$(git -C "$ROOT" config core.hooksPath 2>/dev/null)"
  if [ -z "$hookspath" ]; then
    finding "githooks-not-installed" "core.hooksPath" \
      "the hooks in .githooks/ never run; install with bin/install-git-hooks.sh"
  else
    # Non-empty is not the same as pointing HERE. A core.hooksPath aimed at
    # another directory means git ignores $ROOT/.githooks entirely, and
    # checking only for non-empty suppressed the finding and then went on to
    # test exec bits on hooks git will never run - a clean-looking report over
    # a dormant layer. Relative values resolve against the worktree top level,
    # per git's own rule, and both sides are normalised through cd/pwd because
    # `.githooks`, `./.githooks` and an absolute path are all the same place.
    # A Windows drive prefix is detected by stripping "?:" rather than by a
    # case pattern containing a backslash: every layer between here and the
    # file has eaten one of those at least once, and an escape that silently
    # collapses turns this into a literal-asterisk match that never fires.
    hp_abs="$ROOT/$hookspath"
    case "$hookspath" in /*) hp_abs="$hookspath" ;; esac
    [ "${hookspath#?:}" != "$hookspath" ] && hp_abs="$hookspath"
    hp_real="$(cd "$hp_abs" 2>/dev/null && pwd -P)"
    want_real="$(cd "$ROOT/.githooks" 2>/dev/null && pwd -P)"
    if [ -z "$hp_real" ]; then
      finding "githooks-elsewhere" "core.hooksPath=$hookspath" \
        "points at a directory that does not exist, so no hook here runs"
    elif [ "$hp_real" != "$want_real" ]; then
      finding "githooks-elsewhere" "core.hooksPath=$hookspath" \
        "git runs that directory, not this project's .githooks/"
    fi
  fi
  for h in "$ROOT"/.githooks/*; do
    [ -f "$h" ] || continue
    [ -x "$h" ] || finding "githook-not-executable" ".githooks/$(basename "$h")" \
      "git skips a non-executable hook silently"
  done
fi

# --- 4. setup completeness ---------------------------------------------------
# A FILL-IN marker left behind is not cosmetic: it is a question the agent will
# answer by guessing, in every session, forever.
#
# Except in the TEMPLATE itself, where those markers are the shipped product and
# reporting them would make this command permanently noisy in the one repo whose
# maintainer runs it most - which is how a check stops being read. Same identity
# test as trellis-manifest.sh --write: origin is the upstream, on GitHub.
is_template=0
if [ -f "$ROOT/.trellis/source" ]; then
  _declared="$(sed -n 's/^upstream=//p' "$ROOT/.trellis/source" | tr -d "$CR" | head -1)"
  _url="$(git -C "$ROOT" remote get-url origin 2>/dev/null)"
  _path="$(printf '%s' "$_url" | sed -e 's#^git@[^:]*:#/#' -e 's#^[a-z+]*://[^/]*/##' -e 's#\.git$##' -e 's#^/##')"
  _host="$(printf '%s' "$_url" | sed -n -e 's#^git@\([^:]*\):.*#\1#p' -e 's#^[a-z+]*://\([^/@]*@\)\{0,1\}\([^/]*\)/.*#\2#p' | head -1)"
  [ -n "$_declared" ] && [ "$_host" = "github.com" ] && [ "$_declared" = "$_path" ] && is_template=1
fi

for f in AGENTS.md DESIGN.md docs/about-me.md; do
  [ -f "$ROOT/$f" ] || continue
  examined=$((examined + 1))
  [ "$is_template" -eq 1 ] && continue
  n="$(grep -c 'FILL IN' "$ROOT/$f" 2>/dev/null || true)"
  [ "${n:-0}" -gt 0 ] && finding "setup-incomplete" "$f" "$n FILL-IN marker(s) left; run /setup"
done

# --- 5. template state -------------------------------------------------------
if [ -f "$ROOT/.trellis/manifest" ]; then
  examined=$((examined + 1))
  ver="$(sed -n 's/^version=//p' "$ROOT/.trellis/source" 2>/dev/null | tr -d "$CR" | head -1)"
  [ -n "$ver" ] || finding "template-version-unknown" ".trellis/source" \
    "no version recorded, so sync cannot say what you are behind"
  # Template files this copy no longer has. Deliberate deletion is the common
  # reason and is fine; it is listed so that "I thought that was still here"
  # has an answer.
  gone=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    p="${line#* }"
    [ -e "$ROOT/$p" ] || gone=$((gone + 1))
  done < <(tr -d "$CR" < "$ROOT/.trellis/manifest")
  [ "$gone" -gt 0 ] && finding "template-files-removed" ".trellis/manifest" \
    "$gone file(s) the template shipped are not here; assumed deliberate"
else
  finding "no-manifest" ".trellis/manifest" \
    "this copy predates the sync mechanism or was not made from the template"
fi

# --- report ------------------------------------------------------------------
if [ "$examined" -eq 0 ]; then
  echo "trellis-survey: found nothing to examine in $ROOT." >&2
  echo "  No .claude/, no .githooks/, no context files. That is a could-not-run," >&2
  echo "  not a clean survey." >&2
  exit 2
fi

total="$(grep -c . "$work/findings" 2>/dev/null || true)"; total="${total:-0}"

if [ "$PORCELAIN" -eq 1 ]; then
  cat "$work/findings"
  [ "$total" -gt 0 ] && exit 1
  exit 0
fi

echo "trellis-survey"
echo "  examined: $ROOT"
echo
if [ "$total" -eq 0 ]; then
  echo "Nothing to report. Everything present is wired, and setup has no markers left."
  exit 0
fi

section() { # $1 extended-regex of kinds, $2 heading
  # grep -E, not `case "$kind" in $1)`. A `|` inside a case pattern separates
  # alternatives only when it is written literally in the source: arriving via
  # a variable it is an ordinary character, so every multi-kind section matched
  # NOTHING while the total at the bottom still counted those findings. The
  # report said "5 finding(s)" and printed two. Caught by running it against a
  # real copy with induced drift, not by reading it - and shellcheck's SC2254
  # was pointing straight at it, which is worth remembering before disabling a
  # warning on the grounds that the glob behaviour is intended.
  local matched
  matched="$(grep -E "^($1)	" "$work/findings" 2>/dev/null || true)"
  [ -n "$matched" ] || return 0
  echo "$2"
  printf '%s
' "$matched" | while IFS="$(printf '	')" read -r _kind subject note; do
    printf '    %-44s %s
' "$subject" "$note"
  done
  echo
}

section 'hook-missing'                  "NOT RUNNING - the harness calls these and they are not here:"
section 'githook-not-executable|githooks-not-installed|githooks-elsewhere' "NOT RUNNING - git will skip these without a word:"
section 'hook-unwired'                  "PRESENT BUT INERT - nothing invokes these:"
section 'skill-no-router|command-no-router|router-dangling' "HARNESS COVERAGE - reachable from one tool but not another:"
section 'setup-incomplete'              "SETUP UNFINISHED - the agent will guess at these every session:"
section 'no-manifest|template-version-unknown|template-files-removed' "TEMPLATE STATE:"

echo "$total finding(s). Nothing here has been changed - every one is yours to decide."
exit 1
