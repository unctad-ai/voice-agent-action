#!/usr/bin/env bash
set -euo pipefail

# Classify what changed in the PR compared to the voice-agent base branch
# Output: space-separated list of change types
# Usage: detect-changes.sh [branch]
#   branch: base branch to diff against (default: voice-agent)

BRANCH="${1:-voice-agent}"
CHANGES=""

CHANGED_FILES=$(git diff --name-only "origin/${BRANCH}...HEAD" 2>/dev/null || git diff --name-only HEAD~1..HEAD)

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
