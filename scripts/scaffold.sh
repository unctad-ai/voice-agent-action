#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATES="$ACTION_ROOT/templates"

VERSION="${VOICE_AGENT_VERSION:-latest}"
# Keep "latest" as-is — Coolify force_rebuild ensures fresh npm resolution.
# Only pin when .voice-agent.yml specifies an explicit version.
if [[ "$VERSION" == "latest" ]]; then
  echo "  Using version: latest"
fi

echo "=== Scaffold: copying templates ==="

# Server directory
mkdir -p server
cp "$TEMPLATES/server/index.ts" server/index.ts
cp "$TEMPLATES/server/tsconfig.json" server/tsconfig.json

# Server package.json and .env.example with substitutions
COPILOT="${COPILOT_NAME:-Assistant}"
sed "s|__VOICE_AGENT_VERSION__|${VERSION}|g" "$TEMPLATES/server/package.json.tmpl" > server/package.json
sed "s|__COPILOT_NAME__|${COPILOT}|g" "$TEMPLATES/server/.env.example" > server/.env.example

# Voice config files — only generate if they don't exist yet.
# In incremental mode, voice-config files are maintained by Claude Code
# (or manual edits). Overwriting them with the scaffold placeholder would
# destroy real service data whenever Claude Code is skipped by the content
# hash check.
echo "=== Scaffold: voice-config files ==="

SITE_TITLE="${SITE_TITLE:-$DESCRIPTION}"
_DEFAULT_FAREWELL="Thank you for using ${COPILOT}. Have a great day!"
FAREWELL="${FAREWELL_MESSAGE:-$_DEFAULT_FAREWELL}"
_DEFAULT_DESC="${DESCRIPTION:-this portal}"
_DEFAULT_SYSTEM="You are ${COPILOT}, the virtual assistant for ${_DEFAULT_DESC}."
SYSTEM_INTRO="${SYSTEM_PROMPT_INTRO:-$_DEFAULT_SYSTEM}"
_DEFAULT_GREETING="Hi, I am ${COPILOT}. How can I help you today?"
GREETING="${GREETING_MESSAGE:-$_DEFAULT_GREETING}"
AVATAR="${AVATAR_URL:-}"

export TEMPLATES COPILOT_NAME="${COPILOT}" COPILOT_COLOR="${COPILOT_COLOR:-#1B5E20}"
export SITE_TITLE FAREWELL_MESSAGE="${FAREWELL}" SYSTEM_PROMPT_INTRO="${SYSTEM_INTRO}"
export GREETING_MESSAGE="${GREETING}" AVATAR_URL="${AVATAR}" DESCRIPTION="${DESCRIPTION:-}"
export LANGUAGE="${LANGUAGE:-en}"

if [[ -f server/voice-config.ts && -f src/voice-config.ts ]]; then
  echo "  voice-config files exist — preserving (Claude Code manages these)"
else
  echo "  Generating initial voice-config files"
  node <<'SCAFFOLD_EOF'
    const fs = require('fs');
    const path = require('path');
    const T = process.env.TEMPLATES;
    const sub = (tpl, subs) => {
      let t = fs.readFileSync(tpl, 'utf8');
      for (const [k, v] of Object.entries(subs)) {
        const escaped = v.replace(/'/g, "\\'");
        t = t.split(k).join(escaped);
      }
      return t;
    };

    // Detect canonical service data file
    const serviceDataFile = ['src/data/services.tsx', 'src/data/services.ts']
      .find(f => fs.existsSync(f));

    const baseSubs = {
      '__COPILOT_NAME__': process.env.COPILOT_NAME || 'Assistant',
      '__COPILOT_COLOR__': process.env.COPILOT_COLOR || '#1B5E20',
      '__SITE_TITLE__': process.env.SITE_TITLE || '',
      '__FAREWELL_MESSAGE__': process.env.FAREWELL_MESSAGE || '',
    };

    // Server config
    const serverSubs = { ...baseSubs, '__SYSTEM_PROMPT_INTRO__': process.env.SYSTEM_PROMPT_INTRO || '', '__LANGUAGE__': process.env.LANGUAGE || 'en' };
    if (!fs.existsSync('server/voice-config.ts')) {
      fs.writeFileSync('server/voice-config.ts', sub(T + '/server/voice-config.ts.tmpl', serverSubs));
      console.log('  Created server/voice-config.ts');
    }

    // Client config — use import from data file if available
    const clientSubs = { ...baseSubs, '__GREETING_MESSAGE__': process.env.GREETING_MESSAGE || '', '__AVATAR_URL__': process.env.AVATAR_URL || '', '__LANGUAGE__': process.env.LANGUAGE || 'en' };
    fs.mkdirSync('src', { recursive: true });
    if (!fs.existsSync('src/voice-config.ts')) {
      if (serviceDataFile) {
        // Read the data file to detect exported names
        const dataContent = fs.readFileSync(serviceDataFile, 'utf8');
        const hasAllServices = /export\s+(const|function)\s+allServices/.test(dataContent);
        const hasServiceCategories = /export\s+(const|function)\s+serviceCategories/.test(dataContent);
        const importPath = './' + path.relative('src', serviceDataFile).replace(/\.tsx?$/, '');

        if (hasAllServices && hasServiceCategories) {
          // Generate voice-config that imports from canonical data source
          let config = sub(T + '/src/voice-config.ts.tmpl', clientSubs);
          // Replace placeholder service list + categories with imports
          config = config.replace(
            /import type \{ SiteConfig \} from '@unctad-ai\/voice-agent-core';/,
            `import type { SiteConfig } from '@unctad-ai/voice-agent-core';\nimport { allServices, serviceCategories } from '${importPath}';`
          );
          config = config.replace(
            /\/\/ __SERVICE_DATA_START__[\s\S]*?\/\/ __SERVICE_DATA_END__/,
            'const services = allServices;\nconst categories = serviceCategories;'
          );
          fs.writeFileSync('src/voice-config.ts', config);
          console.log('  Created src/voice-config.ts (importing from ' + serviceDataFile + ')');
        } else {
          // Data file exists but doesn't export expected names — use template
          fs.writeFileSync('src/voice-config.ts', sub(T + '/src/voice-config.ts.tmpl', clientSubs));
          console.log('  Created src/voice-config.ts (data file found but missing allServices/serviceCategories exports)');
        }
      } else {
        fs.writeFileSync('src/voice-config.ts', sub(T + '/src/voice-config.ts.tmpl', clientSubs));
        console.log('  Created src/voice-config.ts');
      }
    }
SCAFFOLD_EOF
fi

# Docker / deploy files
cp "$TEMPLATES/Dockerfile" Dockerfile
cp "$TEMPLATES/docker-compose.yml.tmpl" docker-compose.yml
cp "$TEMPLATES/.dockerignore" .dockerignore
cp "$TEMPLATES/.gitignore" .gitignore

# Remove legacy two-container artifacts (nginx frontend was merged into Express)
rm -f Dockerfile.frontend nginx.conf server/Dockerfile server/.dockerignore

# CLAUDE.md with copilot name substitution
sed "s|__COPILOT_NAME__|${COPILOT}|g" "$TEMPLATES/CLAUDE.md.tmpl" > CLAUDE.md

# Substitute copilot name in docker-compose (portable sed -i)
sed "s|__COPILOT_NAME__|${COPILOT}|g" docker-compose.yml > docker-compose.yml.tmp && mv docker-compose.yml.tmp docker-compose.yml

echo "=== Scaffold: adding voice-agent packages to package.json ==="

# Add or update voice-agent packages in frontend package.json
add_dep() {
  local pkg="$1" ver="$2"
  node -e "
    const pkg = JSON.parse(require('fs').readFileSync('package.json','utf8'));
    pkg.dependencies = pkg.dependencies || {};
    const old = pkg.dependencies['$pkg'];
    pkg.dependencies['$pkg'] = '$ver';
    require('fs').writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
    if (!old) console.log('  Added $pkg@$ver');
    else if (old !== '$ver') console.log('  Updated $pkg: ' + old + ' → $ver');
    else console.log('  $pkg@$ver (unchanged)');
  "
}

add_dev_dep() {
  local pkg="$1" ver="$2"
  node -e "
    const pkg = JSON.parse(require('fs').readFileSync('package.json','utf8'));
    pkg.devDependencies = pkg.devDependencies || {};
    const old = pkg.devDependencies['$pkg'];
    pkg.devDependencies['$pkg'] = '$ver';
    require('fs').writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
    if (!old) console.log('  Added $pkg@$ver (dev)');
    else if (old !== '$ver') console.log('  Updated $pkg (dev): ' + old + ' → $ver');
    else console.log('  $pkg@$ver (dev, unchanged)');
  "
}

add_dep "@unctad-ai/voice-agent-core" "$VERSION"
add_dep "@unctad-ai/voice-agent-ui" "$VERSION"
add_dep "@unctad-ai/voice-agent-registries" "$VERSION"
add_dev_dep "vite-plugin-static-copy" "^2.3.0"

# Auto-resolve peer dependencies from published packages (zero maintenance).
# Reads peerDependencies from the npm registry so scaffold.sh never needs
# manual version updates when the kit's deps change.
echo "  Resolving peer dependencies from npm registry..."
node -e "
  const { execSync } = require('child_process');
  const kit = [
    '@unctad-ai/voice-agent-core',
    '@unctad-ai/voice-agent-ui',
    '@unctad-ai/voice-agent-registries'
  ];
  const skip = new Set(['react', 'react-dom', ...kit]);
  const peers = {};
  for (const pkg of kit) {
    try {
      const raw = execSync('npm info ' + pkg + ' peerDependencies --json 2>/dev/null',
        { encoding: 'utf8' });
      Object.assign(peers, JSON.parse(raw));
    } catch {}
  }
  for (const k of skip) delete peers[k];
  for (const [name, ver] of Object.entries(peers))
    console.log(name + ' ' + ver);
" | while IFS=' ' read -r pkg ver; do
  [[ -z "$pkg" ]] && continue
  add_dep "$pkg" "$ver"
done

echo "=== Scaffold: patching vite.config.ts ==="

# Fix Figma Make quirk: some projects have JSX in .ts files (should be .tsx)
find src -name '*.ts' ! -name '*.d.ts' -type f 2>/dev/null | while read -r f; do
  if grep -qE '<[A-Z/]|<>' "$f" 2>/dev/null; then
    NEW="${f%.ts}.tsx"
    mv "$f" "$NEW"
    echo "  Renamed $f → $NEW (contains JSX)"
  fi
done

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

# Add vite-plugin-static-copy for ten_vad.wasm (unhashed copy to build output)
if ! grep -q "vite-plugin-static-copy" vite.config.ts 2>/dev/null; then
  node -e "
    let config = require('fs').readFileSync('vite.config.ts', 'utf8');
    // Add import
    if (!config.includes('viteStaticCopy')) {
      config = config.replace(
        /import react from/,
        \"import { viteStaticCopy } from 'vite-plugin-static-copy';\nimport react from\"
      );
    }
    // Add plugin after react()
    if (config.includes('plugins')) {
      config = config.replace(
        /react\(\)/,
        'react(),\n      viteStaticCopy({\n        targets: [\n          {\n            src: \"node_modules/@gooney-001/ten-vad-lib/ten_vad.wasm\",\n            dest: \"./\",\n          },\n        ],\n      })'
      );
    } else {
      config = config.replace(
        /export default defineConfig\(\{/,
        \"export default defineConfig({\n  plugins: [\n    react(),\n    viteStaticCopy({\n      targets: [{ src: 'node_modules/@gooney-001/ten-vad-lib/ten_vad.wasm', dest: './' }],\n    }),\n  ],\"
      );
    }
    require('fs').writeFileSync('vite.config.ts', config);
    console.log('  Added viteStaticCopy plugin for ten_vad.wasm');
  "
else
  echo "  vite-plugin-static-copy already configured"
fi

echo "=== Scaffold complete ==="
