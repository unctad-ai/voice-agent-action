# Voice Agent Action

Reusable GitHub Action that automates voice agent integration for Figma Make-generated React projects.

## What it does

On every push to `main`, this action:

1. **Scaffolds** server code, Docker configs, and nginx from templates
2. **Runs Claude Code** to wrap App.tsx, generate voice-config, and integrate form fields
3. **Verifies** the Docker build passes
4. **Pushes** to the `voice-agent` branch (Coolify auto-deploys from there)

## Usage

### 1. Add `.voice-agent.yml` to your repo root (on `main`):

```yaml
copilot_name: "Kenya Assistant"
copilot_color: "#1B5E20"
domain: "kenya.singlewindow.dev"
description: "Kenya Trade Single Window services portal"
voice_agent_version: "^1.0.0"
auto_merge_incremental: true
exclude_routes: ["/2", "/3", "/design-system"]
```

### 2. Add the workflow (`.github/workflows/voice-agent-sync.yml`):

```yaml
name: Voice Agent Sync
on:
  push:
    branches: [main]
  workflow_dispatch:
concurrency:
  group: voice-agent-sync
  cancel-in-progress: true
jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: unctad-ai/voice-agent-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

### 3. Add the `CLAUDE_CODE_OAUTH_TOKEN` secret to your repo.

## How it works

- **Initial run**: Creates `voice-agent` branch from scratch, opens PR for review
- **Incremental runs**: Rebuilds from current `main`, preserves manual additions, auto-pushes if verify passes
- **Content hash check**: Skips Claude Code if input files haven't changed
- **Tree hash check**: Skips push if output is identical to existing branch

## Structure

```
├── action.yml              # Composite action definition
├── templates/              # Deterministic scaffolding
│   ├── server/             # Express server (Dockerfile, index.ts, package.json)
│   ├── Dockerfile.frontend # Multi-stage Vite + nginx build
│   ├── docker-compose.yml  # Frontend + backend services
│   └── nginx.conf          # Reverse proxy
├── scripts/                # Automation scripts
│   ├── scaffold.sh         # Template copying + patching
│   ├── verify.sh           # Docker build verification
│   ├── preserve-manual.sh  # Incremental file preservation
│   └── detect-changes.sh   # Change classification
├── prompts/                # Claude Code instructions
│   ├── initial-integration.md
│   └── incremental-update.md
└── golden-reference/       # Reviewed before/after example
    ├── before.tsx
    └── after.tsx
```
