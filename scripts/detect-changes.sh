#!/usr/bin/env bash
set -euo pipefail

# Classify what changed on main to determine if Claude Code is needed
# Output: space-separated list of change types

CHANGES=""

# Get changed files between previous and current main
CHANGED_FILES=$(git diff --name-only HEAD~1..HEAD 2>/dev/null || git ls-files)

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
