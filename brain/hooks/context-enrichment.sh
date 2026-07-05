#!/bin/bash
# UserPromptSubmit hook: injects project-brain context into every Claude Code prompt.
#
# Reads the prompt from stdin (Claude Code hook JSON spec), runs a BM25 keyword
# search against the indexed project corpus, and emits a <project-brain-context>
# block to stdout. Claude Code merges stdout into the prompt as additional context.
#
# Budget: ~2s wallclock. BM25 is fast. Vector search (slow model load) is NOT used
# here — the agent can invoke `qmd vsearch` manually when it needs semantic retrieval.
#
# Fails silent by design: if the brain isn't initialized yet, this exits 0 with no
# output and the prompt proceeds untouched.
#
# Kill switch: set PROJECT_BRAIN_DISABLE=1 to short-circuit.
# Debug:       set PROJECT_BRAIN_DEBUG=1 to log to brain/hooks/debug.log

set -u

BRAIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- Kill switch ---
if [ "${PROJECT_BRAIN_DISABLE:-0}" = "1" ]; then
  exit 0
fi

# --- Not initialized yet? Exit silently. ---
if [ ! -f "$BRAIN/.last-ingest" ]; then
  exit 0
fi

# --- Read prompt from stdin (Claude Code UserPromptSubmit JSON) ---
STDIN_JSON=$(cat)

# Extract prompt field. Order: jq (fast, native), node, bun, bash grep (last resort).
if command -v jq >/dev/null 2>&1; then
  PROMPT=$(echo "$STDIN_JSON" | jq -r '.prompt // .user_prompt // empty' 2>/dev/null)
elif command -v node >/dev/null 2>&1; then
  PROMPT=$(echo "$STDIN_JSON" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>{try{const o=JSON.parse(s);process.stdout.write(o.prompt||o.user_prompt||"")}catch{}})' 2>/dev/null)
elif command -v bun >/dev/null 2>&1; then
  PROMPT=$(echo "$STDIN_JSON" | bun -e 'const s=await Bun.stdin.text();try{const o=JSON.parse(s);process.stdout.write(o.prompt||o.user_prompt||"")}catch{}' 2>/dev/null)
else
  # POSIX sed last resort (BSD grep has no -P; GNU grep -P breaks on non-UTF-8 locales).
  # Handles simple unescaped prompts only — jq/node/bun above cover the real cases.
  PROMPT=$(printf '%s' "$STDIN_JSON" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi

# Skip on empty/whitespace prompt
if [ -z "${PROMPT// }" ]; then
  exit 0
fi

# Skip on very short prompts (<10 chars) — noise filter for "ok", "yes", etc.
if [ "${#PROMPT}" -lt 10 ]; then
  exit 0
fi

# Truncate to first 500 chars — search operates on query terms, not novel-length prompts
QUERY="${PROMPT:0:500}"

# Strip punctuation that breaks BM25 tokenization (preserve hyphens/underscores for identifiers).
QUERY=$(echo "$QUERY" | tr '.?!,;:()[]{}<>"'"'"'\`~@#$%^&*+=|\\/' ' ' | tr -s ' ')

# --- Debug log ---
if [ "${PROJECT_BRAIN_DEBUG:-0}" = "1" ]; then
  {
    echo "=== $(date -Iseconds) ==="
    echo "Query: $QUERY"
  } >> "$BRAIN/hooks/debug.log"
fi

# --- Run BM25 search with a hard wallclock timeout (2s) ---
QMD_BIN="$HOME/.bun/install/global/node_modules/@tobilu/qmd/bin/qmd"
if [ ! -f "$QMD_BIN" ]; then
  exit 0  # silent fail — don't block the prompt if qmd is missing
fi

if command -v timeout >/dev/null 2>&1; then
  RESULTS=$(timeout 2 bash "$QMD_BIN" search "$QUERY" 2>/dev/null | head -60)
else
  RESULTS=$(bash "$QMD_BIN" search "$QUERY" 2>/dev/null | head -60)
fi

if [ -z "$RESULTS" ]; then
  exit 0
fi

# Extract top 3 hits. qmd output is "qmd://<collection>/path.md:LINE  #hash\nTitle: ...\n
# Score: NN%\n\n@@ -..." per hit. Top 3 keeps injection under ~2KB.
HITS_BLOCK=$(echo "$RESULTS" | awk '
  BEGIN { hits = 0; max_hits = 3; in_hit = 0; buf = "" }
  /^qmd:\/\// {
    if (in_hit && hits < max_hits) { print buf; hits++ }
    if (hits >= max_hits) exit
    buf = $0; in_hit = 1; next
  }
  in_hit { buf = buf "\n" $0 }
  END { if (in_hit && hits < max_hits) print buf }
')

if [ -z "$HITS_BLOCK" ]; then
  exit 0
fi

# --- Emit the context block ---
cat <<EOF
<project-brain-context>
Auto-injected from local BM25 search over the project corpus. Use
\`bash $BRAIN/bin/qmd vsearch "<query>"\` for semantic search, or
\`bash $BRAIN/bin/qmd get <qmd://...>\` for full docs.

$HITS_BLOCK
</project-brain-context>
EOF

if [ "${PROJECT_BRAIN_DEBUG:-0}" = "1" ]; then
  {
    echo "Hits injected:"
    echo "$HITS_BLOCK"
    echo ""
  } >> "$BRAIN/hooks/debug.log"
fi

exit 0
