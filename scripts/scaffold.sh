#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATES="$ACTION_ROOT/templates"

VERSION="${VOICE_AGENT_VERSION:-latest}"
if [[ "$VERSION" == "latest" ]]; then
  VERSION="*"
fi

echo "=== Scaffold: copying templates ==="

# Server directory
mkdir -p server
cp "$TEMPLATES/server/Dockerfile" server/Dockerfile
cp "$TEMPLATES/server/index.ts.tmpl" server/index.ts
sed -i "s|__VOICE_AGENT_VERSION__|${VERSION}|g" server/index.ts 2>/dev/null || true

# Server package.json with version substitution
sed "s|__VOICE_AGENT_VERSION__|${VERSION}|g" "$TEMPLATES/server/package.json.tmpl" > server/package.json

# Docker / deploy files
cp "$TEMPLATES/Dockerfile.frontend" Dockerfile.frontend
cp "$TEMPLATES/docker-compose.yml.tmpl" docker-compose.yml
cp "$TEMPLATES/nginx.conf" nginx.conf
cp "$TEMPLATES/.dockerignore" .dockerignore

# Substitute copilot name in docker-compose
COPILOT="${COPILOT_NAME:-Assistant}"
sed -i "s|__COPILOT_NAME__|${COPILOT}|g" docker-compose.yml

echo "=== Scaffold: adding voice-agent packages to package.json ==="

# Add voice-agent packages to frontend package.json if not present
for pkg in "@unctad-ai/voice-agent-core" "@unctad-ai/voice-agent-ui" "@unctad-ai/voice-agent-registries" "@ai-sdk/react"; do
  if ! grep -q "\"$pkg\"" package.json; then
    # Use node to add to dependencies (jq alternative)
    node -e "
      const pkg = JSON.parse(require('fs').readFileSync('package.json','utf8'));
      pkg.dependencies = pkg.dependencies || {};
      pkg.dependencies['$pkg'] = '${VERSION}';
      require('fs').writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
    "
    echo "  Added $pkg"
  else
    echo "  $pkg already present"
  fi
done

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
