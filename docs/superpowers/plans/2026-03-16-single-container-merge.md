# Single-Container Merge Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge the nginx frontend container and Express backend container into a single Express container per country deployment.

**Architecture:** Multi-stage Dockerfile — stage 1 builds Vite frontend, stage 2 runs Express serving both static files and API/WebSocket on port 80. All template files, scaffold script, and verify script updated to match.

**Tech Stack:** Docker multi-stage builds, Express 5, Vite, Node 22

**Spec:** `docs/superpowers/specs/2026-03-16-single-container-merge-design.md`

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `templates/Dockerfile` | Unified multi-stage build (Vite + Express) |
| Modify | `templates/server/index.ts` | Add compression, static serving, SPA fallback, port 80 default |
| Modify | `templates/server/package.json.tmpl` | Add `compression` dependency |
| Modify | `templates/docker-compose.yml.tmpl` | Single `app` service replacing `frontend` + `backend` |
| Modify | `templates/.dockerignore` | Remove `server` exclusion, allow both `src/` and `server/` |
| Modify | `scripts/scaffold.sh` | Copy unified Dockerfile, remove nginx/frontend copies |
| Modify | `scripts/verify.sh` | Single Docker build instead of two |
| Delete | `templates/Dockerfile.frontend` | Replaced by unified `templates/Dockerfile` |
| Delete | `templates/nginx.conf` | No longer needed — Express serves static |
| Delete | `templates/server/Dockerfile` | Replaced by unified `templates/Dockerfile` |
| Delete | `templates/server/.dockerignore` | No separate server build context |

**Note:** This project has no test framework — verification is done via `scripts/verify.sh` (Docker build check) and manual deployment. Steps are structured for incremental commits rather than TDD.

---

## Chunk 1: Template Files

### Task 1: Create unified Dockerfile

**Files:**
- Create: `templates/Dockerfile`

- [ ] **Step 1: Create `templates/Dockerfile`**

```dockerfile
# check=skip=SecretsUsedInArgOrEnv
FROM node:22-slim AS frontend
WORKDIR /app
COPY package.json package-lock.json* ./
ARG NPM_CACHE_BUST=0
RUN npm install --legacy-peer-deps
COPY . .
ARG VITE_BACKEND_URL
ARG VITE_API_KEY
ARG VITE_COPILOT_NAME
RUN printf 'VITE_BACKEND_URL=%s\nVITE_API_KEY=%s\nVITE_COPILOT_NAME=%s\n' \
    "${VITE_BACKEND_URL}" "${VITE_API_KEY}" "${VITE_COPILOT_NAME}" > .env.production \
    && npx vite build

FROM node:22-slim
WORKDIR /app
COPY server/package.json server/package-lock.json* ./
ARG NPM_CACHE_BUST=0
RUN npm install --legacy-peer-deps
COPY server/ .
COPY --from=frontend /app/build ./build
EXPOSE 80
CMD ["npx", "tsx", "index.ts"]
```

- [ ] **Step 2: Commit**

```bash
git add templates/Dockerfile
git commit -m "feat: add unified multi-stage Dockerfile for single container"
```

---

### Task 2: Update Express server template

**Files:**
- Modify: `templates/server/index.ts`
- Modify: `templates/server/package.json.tmpl`

- [ ] **Step 1: Add `compression` to `templates/server/package.json.tmpl`**

Add to the `dependencies` object:

```json
"compression": "^1.8.0"
```

- [ ] **Step 2: Update `templates/server/index.ts`**

Add imports at top of file (after existing `import fs from 'node:fs'`):

```ts
import path from 'node:path';
import compression from 'compression';
```

Add compression middleware after `app.use(express.json())`:

```ts
app.use(compression());
```

Change default port from `3001` to `80`:

```ts
const port = parseInt(process.env.PORT || '80');
```

Add static file serving after `attachVoicePipeline(...)` call, before `server.listen(...)`:

```ts
// Serve Vite build output
app.use(express.static(path.join(import.meta.dirname, 'build')));
app.get('*', (_req, res) => {
  res.sendFile(path.join(import.meta.dirname, 'build', 'index.html'));
});
```

- [ ] **Step 3: Commit**

```bash
git add templates/server/index.ts templates/server/package.json.tmpl
git commit -m "feat: add static file serving and compression to Express server"
```

---

### Task 3: Update docker-compose template

**Files:**
- Modify: `templates/docker-compose.yml.tmpl`

- [ ] **Step 1: Replace entire file contents**

```yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        - VITE_BACKEND_URL=
        - VITE_API_KEY=${CLIENT_API_KEY:-}
        - VITE_COPILOT_NAME=${COPILOT_NAME:-__COPILOT_NAME__}
        - NPM_CACHE_BUST=${NPM_CACHE_BUST:-0}
    expose:
      - "80"
    environment:
      - PORT=80
      - GROQ_API_KEY=${GROQ_API_KEY:-}
      - CLIENT_API_KEY=${CLIENT_API_KEY:-}
      - QWEN3_TTS_URL=${QWEN3_TTS_URL:-}
      - KYUTAI_STT_URL=${KYUTAI_STT_URL:-}
      - POCKET_TTS_URL=${POCKET_TTS_URL:-}
    volumes:
      - persona-data:/app/data/persona

volumes:
  persona-data:
```

- [ ] **Step 2: Commit**

```bash
git add templates/docker-compose.yml.tmpl
git commit -m "feat: single-service docker-compose replacing frontend+backend"
```

---

### Task 4: Update .dockerignore and delete obsolete templates

**Files:**
- Modify: `templates/.dockerignore`
- Delete: `templates/Dockerfile.frontend`
- Delete: `templates/nginx.conf`
- Delete: `templates/server/Dockerfile`
- Delete: `templates/server/.dockerignore`

- [ ] **Step 1: Update `templates/.dockerignore`**

Replace entire contents with:

```
node_modules
server/node_modules
.env
server/.env
build
dist
.git
.voice-agent
*.log
```

Key change: removed `server` line (was excluding server directory from frontend build context — now we need it).

- [ ] **Step 2: Delete obsolete files**

```bash
git rm templates/Dockerfile.frontend templates/nginx.conf templates/server/Dockerfile templates/server/.dockerignore
```

- [ ] **Step 3: Commit**

```bash
git add templates/.dockerignore
git commit -m "refactor: remove nginx/frontend templates, update .dockerignore"
```

---

## Chunk 2: Scripts

### Task 5: Update scaffold script

**Files:**
- Modify: `scripts/scaffold.sh`

- [ ] **Step 1: Update the Docker/deploy file copy section**

Find this block (around lines 80-84):

```bash
# Docker / deploy files
cp "$TEMPLATES/Dockerfile.frontend" Dockerfile.frontend
cp "$TEMPLATES/docker-compose.yml.tmpl" docker-compose.yml
cp "$TEMPLATES/nginx.conf" nginx.conf
cp "$TEMPLATES/.dockerignore" .dockerignore
cp "$TEMPLATES/.gitignore" .gitignore
```

Replace with:

```bash
# Docker / deploy files
cp "$TEMPLATES/Dockerfile" Dockerfile
cp "$TEMPLATES/docker-compose.yml.tmpl" docker-compose.yml
cp "$TEMPLATES/.dockerignore" .dockerignore
cp "$TEMPLATES/.gitignore" .gitignore
```

- [ ] **Step 2: Remove server Dockerfile copy**

Find this line (around line 20):

```bash
cp "$TEMPLATES/server/Dockerfile" server/Dockerfile
```

Remove it.

- [ ] **Step 3: Remove server .dockerignore copy**

Find this line (around line 23):

```bash
cp "$TEMPLATES/server/.dockerignore" server/.dockerignore
```

Remove it.

- [ ] **Step 4: Commit**

```bash
git add scripts/scaffold.sh
git commit -m "refactor: scaffold copies unified Dockerfile, drops nginx/frontend"
```

---

### Task 6: Update verify script

**Files:**
- Modify: `scripts/verify.sh`

- [ ] **Step 1: Replace the Docker build section**

Find the block that builds frontend and backend separately (around lines 43-65):

```bash
  # Build frontend
  echo "Building frontend..."
  if docker build -f Dockerfile.frontend -t voice-agent-frontend-test . 2>&1 | tee /tmp/docker-frontend.log; then
    echo "  Frontend: OK"
  else
    echo "::error::Frontend Docker build failed"
    echo "::group::Full frontend build log"
    cat /tmp/docker-frontend.log
    echo "::endgroup::"
    FAILED=1
  fi

  # Build backend (context is server/ to match Dockerfile expectations)
  echo "Building backend..."
  if docker build -f server/Dockerfile -t voice-agent-backend-test server/ 2>&1 | tee /tmp/docker-backend.log; then
    echo "  Backend: OK"
  else
    echo "::error::Backend Docker build failed"
    echo "::group::Full backend build log"
    cat /tmp/docker-backend.log
    echo "::endgroup::"
    FAILED=1
  fi
```

Replace with:

```bash
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
```

- [ ] **Step 2: Commit**

```bash
git add scripts/verify.sh
git commit -m "refactor: verify script builds single unified container"
```

---

## Chunk 3: Verification

### Task 7: Local sanity check

- [ ] **Step 1: Review all changes**

```bash
git log --oneline main..HEAD
git diff main..HEAD --stat
```

Verify:
- 6 commits (one per task)
- Files created: `templates/Dockerfile`
- Files modified: `templates/server/index.ts`, `templates/server/package.json.tmpl`, `templates/docker-compose.yml.tmpl`, `templates/.dockerignore`, `scripts/scaffold.sh`, `scripts/verify.sh`
- Files deleted: `templates/Dockerfile.frontend`, `templates/nginx.conf`, `templates/server/Dockerfile`, `templates/server/.dockerignore`

- [ ] **Step 2: Verify no references to deleted files remain**

```bash
grep -r "Dockerfile.frontend\|nginx.conf\|server/Dockerfile\|server/\.dockerignore" templates/ scripts/ --include="*.sh" --include="*.tmpl" --include="*.yml"
```

Expected: no output (no stale references).

- [ ] **Step 3: Verify docker-compose has single service**

```bash
grep -c "build:" templates/docker-compose.yml.tmpl
```

Expected: `1` (single service).

### Task 8: Deploy to Swkenya for end-to-end verification

- [ ] **Step 1: Push changes and trigger the GitHub Action on Swkenya**

- [ ] **Step 2: Verify deployment**

Check:
- `docker ps` on the server shows 1 container (was 2)
- `kenya.singlewindow.dev` serves the UI
- `kenya.singlewindow.dev/api/health` returns health JSON
- Voice pipeline WebSocket connects and works end-to-end
- Deep links (e.g. `kenya.singlewindow.dev/some-path`) return index.html (SPA routing)
