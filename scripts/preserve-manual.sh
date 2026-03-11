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
  ".voice-agent/content-hash"
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

while IFS= read -r file; do
  [[ -z "$file" ]] && continue

  # Skip if file exists on main (fixed-string exact match — not regex)
  if echo "$MAIN_FILES" | grep -qFx "$file"; then
    continue
  fi

  # Skip build artifacts
  case "$file" in
    node_modules/*|build/*|dist/*|server/node_modules/*|package-lock.json) continue ;;
  esac

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
done <<< "$VOICE_FILES"

echo "=== Preservation complete ==="
