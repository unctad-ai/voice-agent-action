#!/usr/bin/env bash
set -euo pipefail

FAILED=0

# Critical file checks (fast — run before expensive Docker builds)
echo "=== Verify: Critical files ==="
for f in server/voice-config.ts src/voice-config.ts server/index.ts; do
  if [ ! -f "$f" ]; then
    echo "::error::Missing critical file: $f"
    FAILED=1
  fi
done

# Check that server/index.ts local imports resolve
node -e "
  const fs = require('fs');
  const src = fs.readFileSync('server/index.ts', 'utf8');
  const imports = [...src.matchAll(/from ['\"]\.\/([^'\"]+)['\"]/g)].map(m => m[1]);
  let fail = false;
  for (const imp of imports) {
    const base = 'server/' + imp.replace(/\.js$/, '');
    if (!fs.existsSync(base + '.ts') && !fs.existsSync(base + '.js')) {
      console.error('::error::Unresolved import in server/index.ts: ./' + imp);
      fail = true;
    }
  }
  if (fail) process.exit(1);
" || FAILED=1

if [ "$FAILED" -ne 0 ]; then
  echo "=== Verify: FAILED (critical files) ==="
  exit 1
fi

# Check Docker availability
if ! command -v docker &>/dev/null; then
  echo "::warning::Docker not available — skipping Docker build verification"
else
  echo "=== Verify: Docker build ==="

  echo "Building app..."
  if docker build -f Dockerfile -t voice-agent-test . 2>&1 | tee /tmp/docker-build.log; then
    echo "  App: OK"
  else
    echo "::error::Docker build failed"
    echo "::group::Full build log"
    cat /tmp/docker-build.log
    echo "::endgroup::"
    FAILED=1
  fi
fi

# Run tests if a test script exists (accurate JSON check, not string grep)
if node -e "process.exit(JSON.parse(require('fs').readFileSync('package.json')).scripts?.test ? 0 : 1)" 2>/dev/null; then
  echo "=== Verify: Running tests ==="
  CI=true npm test || { echo "Tests failed"; FAILED=1; }
fi

if [ "$FAILED" -ne 0 ]; then
  echo "=== Verify: FAILED ==="
  exit 1
fi

echo "=== Verify: All checks passed ==="
