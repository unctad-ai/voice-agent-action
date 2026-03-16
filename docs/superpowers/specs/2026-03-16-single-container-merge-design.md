# Single-Container Merge: Frontend + Backend

**Date:** 2026-03-16
**Status:** Approved
**Goal:** Merge nginx (frontend) and Express (backend) into a single container per country project. Eliminates nginx proxy timeouts, halves container count, simplifies debugging.

## Current Architecture

Two services per country deployment:

- **frontend** — `Dockerfile.frontend`: multi-stage build (Vite → nginx:alpine). nginx serves static files and proxies `/api/*` to backend:3001 with WebSocket upgrade headers.
- **backend** — `server/Dockerfile`: node:22-slim running Express on port 3001. Handles `/api/health`, WebSocket voice pipeline.

Problems: nginx proxy timeouts on long WebSocket connections (required a 300s timeout workaround), two containers to manage, CORS configuration needed between services.

## Target Architecture

Single service per deployment:

- **app** — Multi-stage Dockerfile at project root. Stage 1 builds the Vite frontend. Stage 2 runs Express serving both static files and API/WebSocket on port 80.

## Files Changed

### 1. NEW: `templates/Dockerfile`

Replaces both `templates/Dockerfile.frontend` and `templates/server/Dockerfile`.

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

**Container layout:**
```
/app/
  index.ts
  voice-config.ts
  package.json
  node_modules/
  build/
    index.html
    assets/
```

### 2. MODIFY: `templates/server/index.ts`

Add `path` import alongside existing `fs` import at top of file. Add `compression` middleware for gzip (replaces nginx's default gzip). Add static file serving after `attachVoicePipeline`, before `server.listen`. Update default port from 3001 to 80.

```ts
import path from 'node:path';
import compression from 'compression';
```

After `app.use(express.json())`:

```ts
app.use(compression());
```

Default port change:

```ts
const port = parseInt(process.env.PORT || '80');
```

After `attachVoicePipeline(...)` call, before `server.listen`:

```ts
// Serve Vite build output
app.use(express.static(path.join(import.meta.dirname, 'build')));
app.get('*', (_req, res) => {
  res.sendFile(path.join(import.meta.dirname, 'build', 'index.html'));
});
```

- Uses `import.meta.dirname` (Node 21+, safe on node:22-slim)
- `./build` path: index.ts is at `/app/index.ts`, build is at `/app/build/`
- SPA catch-all `*` placed after all `/api/*` routes so API routes take precedence
- `compression()` replaces nginx's default gzip — without it, static assets would be served uncompressed

Note: Keep `cors` middleware — it's still useful for local development (frontend on different port) and external API consumers. `CORS_ORIGIN` defaults to `*` in code, no env var needed in docker-compose.

### 2b. MODIFY: `templates/server/package.json.tmpl`

Add `compression` dependency:

```json
"compression": "^1.8.0"
```

### 3. MODIFY: `templates/docker-compose.yml.tmpl`

Remove `frontend` service. Rename `backend` → `app`. Single service:

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

Key changes:
- Removed `frontend` service and `depends_on`
- Added VITE build args to single service
- Port 80 (was 3001)
- Dropped `CORS_ORIGIN` (same-origin, no cross-service requests)
- Kept `persona-data` volume on the single service

### 4. DELETE: `templates/Dockerfile.frontend`

No longer needed — frontend build is stage 1 of the unified Dockerfile.

### 5. DELETE: `templates/nginx.conf`

No longer needed — Express serves static files directly.

### 5b. DELETE: `templates/server/Dockerfile`

No longer needed — replaced by unified `templates/Dockerfile` at root.

### 5c. DELETE: `templates/server/.dockerignore`

No longer needed — server is no longer a separate build context. The root `.dockerignore` covers everything.

### 6. MODIFY: `scripts/scaffold.sh`

Changes to the Docker/deploy file copy section:

- Replace `cp "$TEMPLATES/Dockerfile.frontend" Dockerfile.frontend` with `cp "$TEMPLATES/Dockerfile" Dockerfile`
- Remove `cp "$TEMPLATES/nginx.conf" nginx.conf`
- Remove `cp "$TEMPLATES/server/Dockerfile" server/Dockerfile`
- Remove `cp "$TEMPLATES/server/.dockerignore" server/.dockerignore`

### 7. MODIFY: `scripts/verify.sh`

Replace the two separate Docker builds with a single build:

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

### 8. MODIFY: `templates/.dockerignore`

The current `.dockerignore` excludes `server` and `server/node_modules` — this was correct when the frontend Dockerfile didn't need server files. The unified Dockerfile needs both `src/` and `server/` in the build context. Updated to remove the `server` exclusion:

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

## Trade-offs

**Cache efficiency:** The current setup has separate build contexts, so frontend rebuilds don't invalidate backend layers. The unified Dockerfile's `COPY . .` in stage 1 means any server file change invalidates the frontend build cache. This is acceptable given: (a) the current `Dockerfile.frontend` already uses `COPY . .` at root context, (b) rebuilds are fast (~30s), (c) the simplification benefit outweighs the marginal cache hit.

**No gzip by default:** nginx provided gzip automatically. Express does not. Fixed by adding `compression` middleware (see section 2).

**VITE_BACKEND_URL:** Set to empty string in docker-compose build args. The frontend already handles this by defaulting to relative paths (same-origin). This is unchanged from the current behavior.

## Route Precedence

Express routes are matched in registration order:

1. `/api/health` — health check endpoint
2. `/api/voice` — WebSocket voice pipeline (registered by `attachVoicePipeline`)
3. `express.static('./build')` — static files (JS, CSS, images)
4. `GET *` — SPA fallback (serves `index.html` for client-side routing)

WebSocket upgrade requests to `/api/voice` are handled at the HTTP server level by `attachVoicePipeline`, bypassing Express routing entirely — no proxy needed.

## Future Improvements (non-blocking)

- **`@types/compression`**: Add to server `package.json.tmpl` if type-checking is enabled. Not needed for `tsx` runtime.
- **Docker HEALTHCHECK**: Consider adding `HEALTHCHECK CMD node -e "fetch('http://localhost:80/api/health').then(r => {if(!r.ok) process.exit(1)})"` to the Dockerfile for Coolify/Docker orchestration.
- **SPA catch-all**: The `GET *` fallback serves `index.html` for missing static assets too. This is standard SPA behavior and rarely causes issues since Vite hashes asset URLs.

## Verification Plan

1. Run the GitHub Action on Swkenya
2. Confirm `kenya.singlewindow.dev` serves both UI and WebSocket from one container
3. `docker ps` shows 1 container instead of 2
4. Voice pipeline works end-to-end (no proxy timeout issues)
5. SPA routing works (deep links return index.html)
6. `/api/health` returns expected JSON
