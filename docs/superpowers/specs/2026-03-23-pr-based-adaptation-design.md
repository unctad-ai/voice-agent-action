# Voice Agent Action: PR-Based Adaptation

## Problem

The current action merges `main` into `voice-agent`, which is destructive:
- Figma Make deletes `.github/workflows/` and `.voice-agent.yml` on every push to main
- Full merges overwrite voice-agent hooks in form components
- The action triggers on push to the trigger branch, causing loops when it pushes back
- No review gate — changes land directly on voice-agent

## Design

Replace the single "sync" workflow with two focused workflows.

### Expected PR workflow

Celia (or any contributor) works on a branch created **from voice-agent** (not from main). She opens a PR targeting `voice-agent`. The action adapts her changes with voice hooks.

For propagating Figma Make changes from main: the maintainer cherry-picks specific commits from main into a branch off voice-agent, then opens a PR targeting voice-agent. The action adapts those too.

**Important:** PRs must always be branched from `voice-agent`. PRs from `main` directly would include every voice-agent divergence in the diff and produce incorrect results.

### Workflow 1: Voice Agent Init

**File:** `.github/workflows/voice-agent-init.yml`
**Trigger:** `workflow_dispatch` only (manual, one-time per project)
**Purpose:** Bootstrap a new project's voice-agent branch from main.

Steps:
1. Checkout main
2. Read `.voice-agent.yml` config
3. Run `scaffold.sh` to generate voice configs, server setup, App.tsx wrapper
4. Run Claude Code with `initial-integration.md` prompt for full voice hook integration
5. Verify build (`npm install && npm run build`)
6. Create `voice-agent` branch, commit, force-push

This is essentially the current action's "initial" mode, extracted into its own workflow. Runs once per new country project.

### Workflow 2: Voice Agent Adapt

**File:** `.github/workflows/voice-agent-adapt.yml`
**Trigger:** `pull_request` (opened, synchronize) targeting `voice-agent` + `workflow_dispatch` with PR number input
**Purpose:** Adapt incoming UI changes with voice hooks on PRs.

#### Concurrency

```yaml
concurrency:
  group: voice-agent-adapt-${{ github.event.pull_request.number || github.event.inputs.pr_number }}
  cancel-in-progress: true
```

One run per PR at a time. If Celia pushes again while adaptation is running, the in-progress run is cancelled and a new one starts.

#### Step-by-step flow:

**1. Bot guard**
Check if the last commit author is `github-actions[bot]`. If so, exit 0 to prevent infinite loops (action pushes adaptation commit → `synchronize` event fires → action runs again).

Note: if a human pushes on top of a bot commit, the guard sees the human and runs again — this is desired behavior. Other bots (e.g., Dependabot) are not expected to open PRs against voice-agent.

**2. Checkout PR branch**
For PR events: `actions/checkout` with `fetch-depth: 0` and `ref: ${{ github.head_ref }}`.
For `workflow_dispatch`: resolve the PR branch via `gh pr checkout ${{ inputs.pr_number }}`.
Full history needed for diffing.

**3. Read config**
Parse `.voice-agent.yml` from the voice-agent branch for copilot name, color, etc.
Read from `origin/$BRANCH:.voice-agent.yml` since we're checked out on the PR branch.

**4. Pre-flight build check**
Run `npm install && npm run build` before Claude Code to establish a baseline. Record the result. This distinguishes "PR was already broken" from "Claude Code broke it" in step 6.

**5. Detect changes**
Compute `git diff --name-only origin/voice-agent...HEAD` to get files changed in the PR. Classify into categories:
- `forms` — `*Application*.tsx`, `*Form*.tsx`
- `components` — other `src/components/**`
- `navigation` — `routes.tsx`, `App.tsx`
- `services` — `src/data/services*`
- `cosmetic` — CSS, images, assets only

If only `cosmetic`, skip Claude Code. Post PR comment: "No voice adaptation needed." Exit.

**6. Claude Code adaptation**
Feed Claude Code:
- The PR diff (`git diff origin/voice-agent...HEAD -- src/`)
- The list of changed files
- The golden reference (before/after examples)
- The existing voice-config.ts for context
- A new `pr-adaptation.md` prompt instructing it to:
  - Add voice hooks to new/modified form components
  - Update routes.tsx if new routes appeared
  - Update voice-config.ts / server/voice-config.ts if new services appeared
  - Not touch files that already have correct voice hooks

**7. Build verification**
Run `npm run build` (deps already installed from pre-flight). If build fails:
- If pre-flight also failed: post PR comment "Build was already failing before adaptation. Claude Code did not make it worse."
- If pre-flight passed: post PR comment with error details: "Voice adaptation broke the build. Manual fix needed."
- Exit 1 (no push) in either case.

**8. Commit & push**
Clean build artifacts first:
```bash
rm -rf node_modules build dist server/node_modules
```

If Claude Code made changes:
- Stage only `src/`, `server/`, config files — never `git add -A`
- `git commit -m "chore: adapt voice-agent hooks for PR #${PR_NUMBER}"`
- `git push` to the PR branch
- Post PR comment: "Voice hooks adapted. Please review the latest commit."

If no changes needed:
- Post PR comment: "No voice adaptation needed — PR is already compatible."

### What gets removed

| Current | New |
|---------|-----|
| Merge main → voice-agent | Removed — user cherry-picks manually |
| `save-ignored.sh` / `restore-ignored.sh` | Removed — no rebuild cycle |
| `scaffold.sh` in adapt flow | Removed — only used in init |
| Mode detection (initial/incremental) | Removed — separate workflows |
| Content hash check | Removed — replaced by PR diff |
| Push trigger on voice-agent | Removed — PR trigger instead |

### What gets kept/reused

- `.voice-agent.yml` config reading
- Claude Code integration (new prompt)
- Build verification (`verify.sh`)
- Git identity setup
- Golden reference files

### New files needed

| File | Purpose |
|------|---------|
| `prompts/pr-adaptation.md` | Claude Code prompt for PR adaptation |
| `templates/voice-agent-adapt.yml` | Workflow template for consuming repos |
| `templates/voice-agent-init.yml` | Workflow template for consuming repos |

### Action inputs

```yaml
inputs:
  claude_code_oauth_token:
    description: 'Claude Code OAuth token'
    required: true
  voice_agent_branch:
    description: 'Target branch name'
    required: false
    default: 'voice-agent'
  github_token:
    description: 'GitHub token with contents:write, pull-requests:write'
    required: false
    default: ${{ github.token }}
  mode:
    description: 'init or adapt'
    required: false
    default: 'adapt'
  pr_number:
    description: 'PR number (for workflow_dispatch adapt mode)'
    required: false
    default: ''
```

The action.yml uses the `mode` input to switch between init and adapt paths. The two workflow files in consuming repos each pass the appropriate mode. The `pr_number` input is used by the adapt path when triggered via `workflow_dispatch` to resolve the PR branch via `gh pr checkout`.

### Loop prevention

```
PR opened/updated
  → action triggers
    → bot guard: last commit by github-actions[bot]? → exit
    → Claude Code adapts, commits, pushes
      → synchronize event fires
        → action triggers
          → bot guard: yes → exit (loop broken)
```

### Consuming repo workflow examples

**voice-agent-adapt.yml:**
```yaml
name: Voice Agent Adapt
on:
  pull_request:
    types: [opened, synchronize]
    branches: [voice-agent]
  workflow_dispatch:
    inputs:
      pr_number:
        description: 'PR number to adapt'
        required: true
concurrency:
  group: voice-agent-adapt-${{ github.event.pull_request.number || github.event.inputs.pr_number }}
  cancel-in-progress: true
jobs:
  adapt:
    runs-on: self-hosted
    permissions:
      contents: write
      pull-requests: write
    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0
          ref: ${{ github.head_ref || '' }}
      - uses: unctad-ai/voice-agent-action@main
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          github_token: ${{ github.token }}
          mode: adapt
          pr_number: ${{ github.event.pull_request.number || github.event.inputs.pr_number }}
```

**voice-agent-init.yml:**
```yaml
name: Voice Agent Init
on:
  workflow_dispatch:
jobs:
  init:
    runs-on: self-hosted
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0
      - uses: unctad-ai/voice-agent-action@main
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          github_token: ${{ github.token }}
          mode: init
```
