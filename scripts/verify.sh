#!/usr/bin/env bash
set -euo pipefail

echo "=== Verify: Docker build ==="

# Build frontend
echo "Building frontend..."
docker build -f Dockerfile.frontend -t voice-agent-frontend-test . 2>&1 | tail -5
echo "  Frontend: OK"

# Build backend
echo "Building backend..."
docker build -f server/Dockerfile -t voice-agent-backend-test server/ 2>&1 | tail -5
echo "  Backend: OK"

# Run tests if they exist
if grep -q '"test"' package.json 2>/dev/null; then
  echo "=== Verify: Running tests ==="
  npm test || { echo "Tests failed"; exit 1; }
fi

echo "=== Verify: All checks passed ==="
