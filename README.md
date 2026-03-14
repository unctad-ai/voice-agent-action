# Voice Agent Action

Reusable GitHub Action that rebuilds a `voice-agent` branch from a Figma Make project's `main` branch with full voice agent integration. Coolify auto-deploys from that branch.

## What it does

On every push to `main`, this action:

1. **Scaffolds** server code, Docker configs, nginx, and frontend dependencies from deterministic templates
2. **Runs Claude Code** (claude-opus-4-6) to generate `voice-config.ts`, wrap `App.tsx`, and integrate form fields
3. **Verifies** both frontend and backend Docker builds pass
4. **Force-pushes** to the `voice-agent` branch — Coolify picks it up automatically

No PRs are created. Figma Make owns `main`; merging voice-agent changes back into `main` is architecturally wrong since Figma Make regenerates `main` on every design change. The `voice-agent` branch is a derived artifact rebuilt from scratch each time.

## Usage

### 1. Add `.voice-agent.yml` to your repo root (on `main`)

```yaml
copilot_name: "Kenya Assistant"
copilot_color: "#1B5E20"
domain: "kenya.singlewindow.dev"
description: "Kenya Trade Single Window services portal"
voice_agent_version: "^1.0.0"
auto_merge_incremental: true
exclude_routes: ["/2", "/3", "/design-system"]
```

### 2. Add the workflow (`.github/workflows/voice-agent-sync.yml`)

```yaml
name: Voice Agent Sync
on:
  push:
    branches: [main]
  workflow_dispatch:
concurrency:
  group: voice-agent-sync
  cancel-in-progress: true
env:
  FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true
jobs:
  sync:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0
      - uses: unctad-ai/voice-agent-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

### 3. Add the `CLAUDE_CODE_OAUTH_TOKEN` secret to your repo

### 4. (Optional) Add `.voice-agent-ignore` to the `voice-agent` branch

If you need files on the `voice-agent` branch that should survive rebuilds (e.g. persona data, custom configs), create a `.voice-agent-ignore` file directly on the `voice-agent` branch:

```
# Custom persona data uploaded via API
server/data/persona/

# Custom environment overrides
server/.env.local
```

One path per line. Directories end with `/`. Lines starting with `#` are comments. These files are saved before the rebuild and restored after, so they're never lost during force-pushes.

## Key design decisions

### No PRs — direct branch deployment

The action force-pushes to `voice-agent` instead of opening PRs. Figma Make regenerates `main` on every design change, so merging voice-agent patches back into `main` would be overwritten immediately. The voice-agent branch is a disposable overlay rebuilt from the latest `main` each run.

### Mode detection: initial vs incremental

The action checks whether `src/voice-config.ts` exists on the `voice-agent` branch. If it does, the run is incremental; otherwise it's initial. This matters for prompt selection and file preservation.

### Content hash check

On incremental runs, the action hashes the Claude Code input files (`src/App.tsx`, `src/data/services.ts`, form components). If the hash matches the previous run, Claude Code is skipped entirely and its output files are restored from the existing branch. This avoids the expensive LLM step when only cosmetic changes happened on `main`.

### Backup tags

Before each incremental rebuild, the action creates a timestamped backup tag (`voice-agent-backup-YYYYMMDD-HHMMSS`) so the previous state is always recoverable.

### Tree hash check

After building, the action compares the new git tree hash to the existing `voice-agent` branch. If identical, the push is skipped (no-op detection).

### Peer deps resolved dynamically

`scaffold.sh` reads `peerDependencies` from the npm registry at build time, so the action never needs manual updates when the voice-agent-kit's dependencies change.

### Protecting critical files on `main`

Figma Make occasionally does full-tree syncs that can delete non-Figma files. To protect `.voice-agent.yml` and `.github/workflows/voice-agent-sync.yml` on `main`, add a GitHub branch protection rule with a CODEOWNERS file:

```
# .github/CODEOWNERS
/.voice-agent.yml @your-team
/.github/workflows/voice-agent-sync.yml @your-team
```

This requires review approval before these files can be modified or deleted.

### Docker cache busting

Both Dockerfiles accept an `NPM_CACHE_BUST` build arg. When deploying a new voice-agent-kit version, set `NPM_CACHE_BUST=$(date +%s)` to force Docker to re-run `npm install` instead of using cached layers with stale `latest` versions.

### Self-hosted runner

The workflow uses `self-hosted` runners (not `ubuntu-latest`) because Claude Code and Docker builds require more resources. The action avoids `gh` CLI and `yq` — it uses `curl` + `node` one-liners for portability across runner environments.

## Structure

```
├── action.yml              # Composite action definition
├── templates/              # Deterministic scaffolding
│   ├── server/             # Express server (Dockerfile, index.ts, package.json)
│   ├── Dockerfile.frontend # Multi-stage Vite + nginx build
│   ├── docker-compose.yml  # Frontend + backend services
│   ├── nginx.conf          # Reverse proxy config
│   └── CLAUDE.md.tmpl      # Claude Code context for the target repo
├── scripts/
│   ├── scaffold.sh         # Template copying, dep injection, vite patching
│   ├── verify.sh           # Docker build verification (frontend + backend)
│   ├── save-ignored.sh     # Saves .voice-agent-ignore files before rebuild
│   ├── restore-ignored.sh  # Restores ignored files after rebuild
│   └── detect-changes.sh   # Classifies main branch changes (services, forms, cosmetic, etc.)
├── prompts/
│   ├── initial-integration.md   # Claude Code prompt for first-time integration
│   └── incremental-update.md    # Claude Code prompt for subsequent rebuilds
└── golden-reference/       # Reviewed before/after App.tsx example
    ├── before.tsx
    └── after.tsx
```

## Pipeline flow

```
main push → read .voice-agent.yml → detect mode → backup tag (incremental)
  → save ignored files (incremental) → content hash check → restore Claude files (incremental)
  → scaffold templates → [Claude Code or skip] → restore ignored files
  → Docker build verification → commit → force-push voice-agent branch
```
