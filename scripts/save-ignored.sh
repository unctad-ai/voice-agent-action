#!/usr/bin/env bash
set -euo pipefail

# Read .voice-agent-ignore from the voice-agent branch and save matching files.
# These files survive the rebuild cycle.
#
# Format: one path per line (no globs). Lines starting with # are comments.
# Example .voice-agent-ignore:
#   # Custom persona data
#   server/data/persona/avatar.png
#   server/data/persona/voices/
#   # Custom env overrides
#   server/.env.local

BRANCH="${1:-voice-agent}"
SAVE_DIR="/tmp/voice-agent-ignored"
rm -rf "$SAVE_DIR"
mkdir -p "$SAVE_DIR"

# Read ignore file from the voice-agent branch
IGNORE_CONTENT=$(git show "origin/$BRANCH:.voice-agent-ignore" 2>/dev/null || true)
if [ -z "$IGNORE_CONTENT" ]; then
  echo "  No .voice-agent-ignore found on $BRANCH — nothing to save"
  exit 0
fi

echo "=== Saving ignored files from $BRANCH ==="
SAVED=0

while IFS= read -r line; do
  # Skip empty lines and comments
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  # Trim whitespace
  line=$(echo "$line" | xargs)

  # Check if it's a directory (ends with /)
  if [[ "$line" == */ ]]; then
    # Save all files under this directory
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      mkdir -p "$SAVE_DIR/$(dirname "$f")"
      git show "origin/$BRANCH:$f" > "$SAVE_DIR/$f"
      echo "  Saved: $f"
      SAVED=$((SAVED + 1))
    done < <(git ls-tree -r --name-only "origin/$BRANCH" -- "$line" 2>/dev/null || true)
  else
    # Save single file
    if git show "origin/$BRANCH:$line" &>/dev/null; then
      mkdir -p "$SAVE_DIR/$(dirname "$line")"
      git show "origin/$BRANCH:$line" > "$SAVE_DIR/$line"
      echo "  Saved: $line"
      SAVED=$((SAVED + 1))
    fi
  fi
done <<< "$IGNORE_CONTENT"

echo "  Total saved: $SAVED files"
