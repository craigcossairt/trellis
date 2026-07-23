#!/bin/bash
# Brain configuration — sourced by scripts/ingest.sh.
# Edit this file to control what goes into the corpus. Everything else is generic.
# shellcheck disable=SC2034  # every variable here is consumed by the sourcing scripts

# Collection name used with QMD (also appears in qmd:// result URIs).
BRAIN_COLLECTION="project"

# Directories/files to copy into raw/, relative to the repo root.
# Format: "<source-path>:<raw-subdir>"
INGEST_SOURCES=(
  "docs:docs"
  "AGENTS.md:agents-md"
  "README.md:agents-md"
)

# Set to 1 to also generate a markdown git commit log into raw/git-commits/.
INGEST_GIT_LOG=1

# Optional: absolute path to your agent-harness memory directory to include in the corpus.
# Leave empty to skip. Example (Claude Code):
#   INGEST_MEMORY_DIR="$HOME/.claude/projects/<project-slug>/memory"
INGEST_MEMORY_DIR=""
