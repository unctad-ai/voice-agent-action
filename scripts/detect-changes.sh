#!/usr/bin/env bash
set -euo pipefail

# Classify what changed on main to determine if Claude Code is needed
# Output: space-separated list of change types

CHANGES=""

# Get files changed on main since the last merge into voice-agent
MERGE_BASE=$(git merge-base HEAD main 2>/dev/null || echo "")
if [[ -n "$MERGE_BASE" ]]; then
  CHANGED_FILES=$(git diff --name-only "$MERGE_BASE"..main 2>/dev/null || git ls-files)
else
  CHANGED_FILES=$(git diff --name-only HEAD~1..HEAD 2>/dev/null || git ls-files)
fi

while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  case "$file" in
    src/data/services*|src/data/serviceCategories*)
      CHANGES="$CHANGES services"
      ;;
    src/App.tsx|src/routes*)
      CHANGES="$CHANGES navigation"
      ;;
    src/components/*Application*|src/components/*Form*)
      CHANGES="$CHANGES forms"
      ;;
    src/components/*|src/pages/*)
      CHANGES="$CHANGES components"
      ;;
    *.css|*.scss|*.png|*.jpg|*.svg|src/assets/*)
      CHANGES="$CHANGES cosmetic"
      ;;
    *)
      CHANGES="$CHANGES other"
      ;;
  esac
done <<< "$CHANGED_FILES"

# Deduplicate
CHANGES=$(echo "$CHANGES" | tr ' ' '\n' | sort -u | tr '\n' ' ')

if [[ -z "$CHANGES" || "$CHANGES" =~ ^[[:space:]]*cosmetic[[:space:]]*$ ]]; then
  echo "cosmetic-only"
else
  echo "$CHANGES"
fi
