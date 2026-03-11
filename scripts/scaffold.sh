#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATES="$ACTION_ROOT/templates"

VERSION="${VOICE_AGENT_VERSION:-latest}"

echo "=== Scaffold: copying templates ==="

# Server directory
mkdir -p server
cp "$TEMPLATES/server/Dockerfile" server/Dockerfile
cp "$TEMPLATES/server/index.ts" server/index.ts

# Server package.json with version substitution
sed "s|__VOICE_AGENT_VERSION__|${VERSION}|g" "$TEMPLATES/server/package.json.tmpl" > server/package.json

# Docker / deploy files
cp "$TEMPLATES/Dockerfile.frontend" Dockerfile.frontend
cp "$TEMPLATES/docker-compose.yml.tmpl" docker-compose.yml
cp "$TEMPLATES/nginx.conf" nginx.conf
cp "$TEMPLATES/.dockerignore" .dockerignore

# Substitute copilot name in docker-compose (portable sed -i)
COPILOT="${COPILOT_NAME:-Assistant}"
sed "s|__COPILOT_NAME__|${COPILOT}|g" docker-compose.yml > docker-compose.yml.tmp && mv docker-compose.yml.tmp docker-compose.yml

echo "=== Scaffold: adding voice-agent packages to package.json ==="

# Add voice-agent packages to frontend package.json if not present
add_dep() {
  local pkg="$1" ver="$2"
  if ! grep -q "\"$pkg\"" package.json; then
    node -e "
      const pkg = JSON.parse(require('fs').readFileSync('package.json','utf8'));
      pkg.dependencies = pkg.dependencies || {};
      pkg.dependencies['$pkg'] = '$ver';
      require('fs').writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
    "
    echo "  Added $pkg@$ver"
  else
    echo "  $pkg already present"
  fi
}

add_dep "@unctad-ai/voice-agent-core" "$VERSION"
add_dep "@unctad-ai/voice-agent-ui" "$VERSION"
add_dep "@unctad-ai/voice-agent-registries" "$VERSION"
add_dep "@ai-sdk/react" "^1.0.0"

echo "=== Scaffold: patching vite.config.ts ==="

# Add build.outDir: 'build' if not present
if ! grep -q "outDir.*['\"]build['\"]" vite.config.ts 2>/dev/null; then
  # Use node for reliable AST-level patching
  node -e "
    let config = require('fs').readFileSync('vite.config.ts', 'utf8');
    if (!config.includes('outDir')) {
      config = config.replace(
        /export default defineConfig\(\{/,
        'export default defineConfig({\n  build: { outDir: \"build\" },'
      );
      require('fs').writeFileSync('vite.config.ts', config);
      console.log('  Added build.outDir: build');
    }
  "
else
  echo "  outDir already set"
fi

# Add ten-vad-glue alias if not present
if ! grep -q "ten-vad-glue" vite.config.ts 2>/dev/null; then
  node -e "
    let config = require('fs').readFileSync('vite.config.ts', 'utf8');
    if (config.includes('alias')) {
      // Add to existing alias object
      config = config.replace(
        /alias:\s*\{/,
        'alias: {\n      \"ten-vad-glue\": \"./node_modules/@gooney-001/ten-vad-lib/ten_vad.js\",'
      );
    } else {
      // Add resolve.alias section
      config = config.replace(
        /export default defineConfig\(\{/,
        'export default defineConfig({\n  resolve: { alias: { \"ten-vad-glue\": \"./node_modules/@gooney-001/ten-vad-lib/ten_vad.js\" } },'
      );
    }
    require('fs').writeFileSync('vite.config.ts', config);
    console.log('  Added ten-vad-glue alias');
  "
else
  echo "  ten-vad-glue alias already present"
fi

echo "=== Scaffold complete ==="
