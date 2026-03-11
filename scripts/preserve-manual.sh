#!/usr/bin/env bash
set -euo pipefail

BRANCH="${1:-voice-agent}"
PRESERVE_DIR="/tmp/voice-agent-preserved"
rm -rf "$PRESERVE_DIR"
mkdir -p "$PRESERVE_DIR"

# Auto-generated files (will be regenerated — don't preserve)
AUTO_GENERATED=(
  "src/voice-config.ts"
  "server/voice-config.ts"
  "server/index.ts"
  "server/package.json"
  "server/Dockerfile"
  "Dockerfile.frontend"
  "docker-compose.yml"
  "nginx.conf"
  ".dockerignore"
  ".voice-agent/manifest.yml"
)

# Modified files (will be re-patched — don't preserve)
MODIFIED=(
  "src/App.tsx"
  "package.json"
  "vite.config.ts"
)

echo "=== Preserving manual additions from $BRANCH ==="

# Get list of files on voice-agent that don't exist on main
VOICE_FILES=$(git ls-tree -r --name-only "origin/$BRANCH" 2>/dev/null || true)
MAIN_FILES=$(git ls-tree -r --name-only "origin/main" 2>/dev/null || git ls-tree -r --name-only main)

for file in $VOICE_FILES; do
  # Skip if file exists on main
  if echo "$MAIN_FILES" | grep -qx "$file"; then
    continue
  fi

  # Skip auto-generated files
  SKIP=false
  for auto in "${AUTO_GENERATED[@]}"; do
    if [[ "$file" == "$auto" ]]; then SKIP=true; break; fi
  done
  if $SKIP; then continue; fi

  # Skip modified files
  for mod in "${MODIFIED[@]}"; do
    if [[ "$file" == "$mod" ]]; then SKIP=true; break; fi
  done
  if $SKIP; then continue; fi

  # Preserve this file
  mkdir -p "$PRESERVE_DIR/$(dirname "$file")"
  git show "origin/$BRANCH:$file" > "$PRESERVE_DIR/$file"
  echo "  Preserved: $file"
done

# Also preserve form component modifications (Tier 2)
# These are files that exist on BOTH main and voice-agent, but voice-agent has hook additions
MANIFEST_FILE=$(git show "origin/$BRANCH:.voice-agent/manifest.yml" 2>/dev/null || true)
if [[ -n "$MANIFEST_FILE" ]]; then
  # Read tier2 files from manifest
  TIER2_FILES=$(echo "$MANIFEST_FILE" | grep "^  - " | sed 's/^  - //' || true)
  for file in $TIER2_FILES; do
    # Check if main changed this file since last run
    MAIN_HASH=$(git rev-parse "main:$file" 2>/dev/null || echo "none")
    STORED_HASH=$(echo "$MANIFEST_FILE" | grep -A1 "$file" | grep "main_hash:" | awk '{print $2}' || echo "")

    if [[ "$MAIN_HASH" == "$STORED_HASH" ]]; then
      # Main hasn't changed — preserve the integrated version
      mkdir -p "$PRESERVE_DIR/$(dirname "$file")"
      git show "origin/$BRANCH:$file" > "$PRESERVE_DIR/$file"
      echo "  Preserved (Tier 2): $file"
    else
      echo "  CHANGED on main (needs re-integration): $file"
    fi
  done
fi

echo "=== Preservation complete ==="
