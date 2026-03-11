#!/usr/bin/env bash
set -euo pipefail

# Check Docker availability
if ! command -v docker &>/dev/null; then
  echo "::warning::Docker not available — skipping Docker build verification"
else
  echo "=== Verify: Docker build ==="

  # Build frontend
  echo "Building frontend..."
  if ! docker build -f Dockerfile.frontend -t voice-agent-frontend-test . 2>&1 | tee /tmp/docker-frontend.log | tail -20; then
    echo "::group::Full frontend build log"
    cat /tmp/docker-frontend.log
    echo "::endgroup::"
    exit 1
  fi
  echo "  Frontend: OK"

  # Build backend (context is server/ to match Dockerfile expectations)
  echo "Building backend..."
  if ! docker build -f server/Dockerfile -t voice-agent-backend-test server/ 2>&1 | tee /tmp/docker-backend.log | tail -20; then
    echo "::group::Full backend build log"
    cat /tmp/docker-backend.log
    echo "::endgroup::"
    exit 1
  fi
  echo "  Backend: OK"
fi

# Run tests if a test script exists (accurate JSON check, not string grep)
if node -e "process.exit(JSON.parse(require('fs').readFileSync('package.json')).scripts?.test ? 0 : 1)" 2>/dev/null; then
  echo "=== Verify: Running tests ==="
  CI=true npm test || { echo "Tests failed"; exit 1; }
fi

echo "=== Verify: All checks passed ==="
