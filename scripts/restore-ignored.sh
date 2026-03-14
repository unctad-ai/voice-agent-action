#!/usr/bin/env bash
set -euo pipefail

# Restore files saved by save-ignored.sh back into the working tree.

SAVE_DIR="/tmp/voice-agent-ignored"

if [ ! -d "$SAVE_DIR" ] || [ -z "$(ls -A "$SAVE_DIR" 2>/dev/null)" ]; then
  echo "  No ignored files to restore"
  exit 0
fi

echo "=== Restoring ignored files ==="
RESTORED=0
ORIG="$(pwd)"

while IFS= read -r f; do
  REL="${f#./}"
  DEST="$ORIG/$REL"
  mkdir -p "$(dirname "$DEST")"
  cp "$SAVE_DIR/$REL" "$DEST"
  echo "  Restored: $REL"
  RESTORED=$((RESTORED + 1))
done < <(cd "$SAVE_DIR" && find . -type f)

echo "  Total restored: $RESTORED files"
