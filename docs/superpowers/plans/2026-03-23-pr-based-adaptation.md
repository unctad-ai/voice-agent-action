# PR-Based Adaptation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the destructive merge-based voice-agent-action with a PR-triggered adaptation workflow that preserves voice-agent code while integrating UI changes.

**Architecture:** Split the single composite action into two modes (init/adapt) controlled by a `mode` input. The adapt path checks out a PR branch, diffs against voice-agent, runs Claude Code only on changed files, and pushes back to the PR. The init path remains the current bootstrap flow.

**Tech Stack:** GitHub Actions composite action, bash scripts, Claude Code CLI, Node.js

**Spec:** `docs/superpowers/specs/2026-03-23-pr-based-adaptation-design.md`

---

### Task 1: Update action.yml inputs and metadata

**Files:**
- Modify: `action.yml:1-15`

- [ ] **Step 1: Update action metadata and inputs**

Replace the current inputs block with:

```yaml
name: 'Voice Agent Action'
description: 'Voice agent integration — init (bootstrap) or adapt (PR-based hook integration)'
inputs:
  claude_code_oauth_token:
    description: 'Claude Code OAuth token for subscription-based usage'
    required: true
  voice_agent_branch:
    description: 'Target branch name'
    required: false
    default: 'voice-agent'
  github_token:
    description: 'GitHub token with contents:write, pull-requests:write permissions'
    required: false
    default: ${{ github.token }}
  mode:
    description: 'init (bootstrap new project) or adapt (PR voice hook integration)'
    required: false
    default: 'adapt'
  pr_number:
    description: 'PR number (required for workflow_dispatch adapt mode)'
    required: false
    default: ''
```

- [ ] **Step 2: Verify YAML is valid**

Run: `python3 -c "import yaml; yaml.safe_load(open('action.yml'))" && echo OK`
Expected: OK

- [ ] **Step 3: Commit**

```bash
git add action.yml
git commit -m "refactor: update action inputs for init/adapt modes"
```

---

### Task 2: Add bot guard step

**Files:**
- Modify: `action.yml` (add step after git identity config, before read config)

- [ ] **Step 1: Add bot guard step**

Insert after the "Configure git identity" step:

```yaml
    - name: Bot guard (prevent infinite loops)
      if: ${{ inputs.mode == 'adapt' }}
      id: guard
      shell: bash
      run: |
        LAST_AUTHOR=$(git log -1 --format='%an')
        if [[ "$LAST_AUTHOR" == "github-actions[bot]" ]]; then
          echo "Skipping — last commit was from the action"
          echo "skip=true" >> "$GITHUB_OUTPUT"
        else
          echo "skip=false" >> "$GITHUB_OUTPUT"
        fi
```

- [ ] **Step 2: Add guard condition to all subsequent adapt steps**

Every step that runs in adapt mode needs: `if: ${{ inputs.mode == 'adapt' && steps.guard.outputs.skip != 'true' }}` or for shared steps, make sure the guard is respected. **CRITICAL:** All `if:` conditions in composite actions must use `${{ }}` expression syntax.

- [ ] **Step 3: Commit**

```bash
git add action.yml
git commit -m "feat: add bot guard to prevent infinite PR adaptation loops"
```

---

### Task 3: Update config read for adapt mode

**Files:**
- Modify: `action.yml` (Read config step)

- [ ] **Step 1: Update config read to work from PR branch**

In adapt mode, `.voice-agent.yml` may not exist on the PR branch (it lives on voice-agent). Read from `origin/voice-agent` instead:

```yaml
    - name: Read config
      id: config
      shell: bash
      run: |
        MODE="${{ inputs.mode }}"
        BRANCH="${{ inputs.voice_agent_branch }}"

        if [[ "$MODE" == "adapt" ]]; then
          # In adapt mode, read config from the base branch (voice-agent)
          CONFIG=$(git show "origin/${BRANCH}:.voice-agent.yml" 2>/dev/null || echo "")
          if [[ -z "$CONFIG" ]]; then
            echo "::error::Missing .voice-agent.yml on ${BRANCH} branch"
            exit 1
          fi
          echo "$CONFIG" > /tmp/.voice-agent.yml
          CONFIG_FILE="/tmp/.voice-agent.yml"
        else
          if [ ! -f .voice-agent.yml ]; then
            echo "::error::Missing .voice-agent.yml in repository root"
            exit 1
          fi
          CONFIG_FILE=".voice-agent.yml"
        fi

        node -e "
          const fs = require('fs');
          const yaml = fs.readFileSync('$CONFIG_FILE', 'utf8');
          const config = {};
          yaml.split('\n').forEach(line => {
            const m = line.match(/^(\w+):\s*(.+)/);
            if (m) config[m[1]] = m[2].replace(/^[\"']|[\"']$/g, '').trim();
          });
          const keys = ['copilot_name','copilot_color','domain','description','voice_agent_version','site_title','farewell_message','system_prompt_intro','greeting_message','avatar_url','language'];
          const out = [];
          keys.forEach(k => out.push(k + '=' + (config[k] || '')));
          if (!config.voice_agent_version) out.push('voice_agent_version=latest');
          fs.appendFileSync(process.env.GITHUB_OUTPUT, out.join('\n') + '\n');
        "
```

- [ ] **Step 2: Commit**

```bash
git add action.yml
git commit -m "feat: read .voice-agent.yml from base branch in adapt mode"
```

---

### Task 4: Add PR checkout step for adapt mode

**Files:**
- Modify: `action.yml` (add step after bot guard)

- [ ] **Step 1: Add PR checkout step**

Insert after bot guard:

```yaml
    - name: Checkout PR branch (adapt mode, workflow_dispatch)
      if: ${{ inputs.mode == 'adapt' }} && inputs.pr_number != '' && steps.guard.outputs.skip != 'true'
      shell: bash
      run: |
        gh pr checkout ${{ inputs.pr_number }}
      env:
        GH_TOKEN: ${{ inputs.github_token }}
```

Note: For PR-trigger events, the consuming workflow's `actions/checkout` already checks out the PR branch with `ref: ${{ github.head_ref }}`. This step only runs for `workflow_dispatch` where we need to resolve the PR number to a branch.

- [ ] **Step 2: Commit**

```bash
git add action.yml
git commit -m "feat: add PR checkout for workflow_dispatch adapt mode"
```

---

### Task 4: Add pre-flight build check

**Files:**
- Modify: `action.yml` (add step after PR checkout)

- [ ] **Step 1: Add pre-flight build step**

```yaml
    - name: Pre-flight build check
      if: ${{ inputs.mode == 'adapt' }} && steps.guard.outputs.skip != 'true'
      id: preflight
      shell: bash
      run: |
        npm install
        if npm run build 2>/dev/null; then
          echo "status=pass" >> "$GITHUB_OUTPUT"
        else
          echo "::warning::PR build already failing before adaptation"
          echo "status=fail" >> "$GITHUB_OUTPUT"
        fi
        rm -rf build dist
```

- [ ] **Step 2: Commit**

```bash
git add action.yml
git commit -m "feat: add pre-flight build check for adapt mode"
```

---

### Task 5: Replace merge step with PR diff detection

**Files:**
- Modify: `action.yml` (replace "Merge main" and "Content hash check" steps)
- Modify: `scripts/detect-changes.sh`

- [ ] **Step 1: Update detect-changes.sh for PR diff**

Replace the current script with:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Classify what changed in the PR compared to the voice-agent base branch
# Output: space-separated list of change types

BRANCH="${1:-voice-agent}"
CHANGES=""

CHANGED_FILES=$(git diff --name-only "origin/${BRANCH}...HEAD" 2>/dev/null || git diff --name-only HEAD~1..HEAD)

while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  case "$file" in
    src/data/services*|src/data/serviceCategories*)
      CHANGES="$CHANGES services"
      ;;
    src/App.tsx|src/routes*)
      CHANGES="$CHANGES navigation"
      ;;
    src/components/*Application*|src/components/*Form*)
      CHANGES="$CHANGES forms"
      ;;
    src/components/*|src/pages/*)
      CHANGES="$CHANGES components"
      ;;
    *.css|*.scss|*.png|*.jpg|*.svg|src/assets/*)
      CHANGES="$CHANGES cosmetic"
      ;;
    *)
      CHANGES="$CHANGES other"
      ;;
  esac
done <<< "$CHANGED_FILES"

# Deduplicate
CHANGES=$(echo "$CHANGES" | tr ' ' '\n' | sort -u | tr '\n' ' ')

if [[ -z "$CHANGES" || "$CHANGES" =~ ^[[:space:]]*cosmetic[[:space:]]*$ ]]; then
  echo "cosmetic-only"
else
  echo "$CHANGES"
fi
```

- [ ] **Step 2: Replace merge + hash steps in action.yml with PR diff detection**

Remove these steps:
- "Content hash check"
- "Merge main into voice-agent branch"
- "Write content hash"

Replace with:

```yaml
    - name: Detect PR changes
      if: ${{ inputs.mode == 'adapt' }} && steps.guard.outputs.skip != 'true'
      id: changes
      shell: bash
      run: |
        BRANCH="${{ inputs.voice_agent_branch }}"
        CHANGE_TYPES=$(${{ github.action_path }}/scripts/detect-changes.sh "$BRANCH")
        echo "types=${CHANGE_TYPES}" >> "$GITHUB_OUTPUT"
        echo "Detected changes: ${CHANGE_TYPES}"

        # Save changed files and diff to files (avoid GITHUB_OUTPUT size/quoting issues)
        git diff --name-only "origin/${BRANCH}...HEAD" 2>/dev/null > /tmp/pr-changed-files.txt || echo "" > /tmp/pr-changed-files.txt
        git diff "origin/${BRANCH}...HEAD" -- src/ server/ 2>/dev/null > /tmp/pr-diff.patch || echo "" > /tmp/pr-diff.patch

        # Truncate diff if too large for Claude Code context (500KB limit)
        DIFF_SIZE=$(wc -c < /tmp/pr-diff.patch)
        if [[ "$DIFF_SIZE" -gt 500000 ]]; then
          echo "::warning::PR diff is ${DIFF_SIZE} bytes — truncating to 500KB for Claude Code"
          head -c 500000 /tmp/pr-diff.patch > /tmp/pr-diff-truncated.patch
          mv /tmp/pr-diff-truncated.patch /tmp/pr-diff.patch
          echo "" >> /tmp/pr-diff.patch
          echo "... (diff truncated — full diff too large)" >> /tmp/pr-diff.patch
        fi
```

- [ ] **Step 3: Add cosmetic-only skip with PR comment**

```yaml
    - name: Skip cosmetic-only changes
      if: ${{ inputs.mode == 'adapt' }} && steps.guard.outputs.skip != 'true' && steps.changes.outputs.types == 'cosmetic-only'
      shell: bash
      run: |
        PR="${{ inputs.pr_number }}"
        if [[ -n "$PR" ]]; then
          gh pr comment "$PR" --body "✅ No voice adaptation needed — only cosmetic changes detected."
        fi
        echo "Cosmetic only — skipping Claude Code"
      env:
        GH_TOKEN: ${{ inputs.github_token }}
```

- [ ] **Step 4: Commit**

```bash
git add action.yml scripts/detect-changes.sh
git commit -m "feat: replace merge with PR diff detection for adapt mode"
```

---

### Task 6: Create pr-adaptation.md prompt

**Files:**
- Create: `prompts/pr-adaptation.md`

- [ ] **Step 1: Write the PR adaptation prompt**

Create `prompts/pr-adaptation.md` that combines context from `context.md` with PR-specific instructions. The prompt should:
- Receive the PR diff and changed file list
- Reference the golden-reference patterns
- Instruct Claude Code to only touch changed/new form components
- Follow the same integration rules from `initial-integration.md` section 4 (form fields)
- Check if routes or services changed and update voice-config accordingly
- Never modify files that already have correct voice hooks unless the component structure changed

```markdown
# PR Voice Agent Adaptation

A pull request has introduced UI changes to the voice-agent branch. Your job is to integrate voice agent hooks into new or modified components.

## What changed

The PR diff and changed file list are provided below. Focus ONLY on these files.

## Rules

1. **Only modify files that need voice hooks** — don't touch unrelated files
2. **Study the golden reference first** — read `golden-reference/after.tsx` for correct patterns
3. **For new form components** — apply the full integration from initial-integration.md section 4
4. **For modified form components** — check if existing hooks still apply. If the component structure changed (fields added/removed/renamed), update the hooks. If only styling changed, skip.
5. **For route changes** — update `src/voice-config.ts` routeMap and getServiceFormRoute
6. **For service data changes** — update both voice-config files
7. **Never modify the designer's original code** — only add voice hooks
8. **Verify after changes** — confirm no type errors

## Output

List all files modified and why:
```
MODIFIED: src/components/NewForm.tsx (added voice hooks)
UNCHANGED: src/components/Homepage.tsx (no form — skip)
MODIFIED: src/voice-config.ts (new route added)
```
```

- [ ] **Step 2: Commit**

```bash
git add prompts/pr-adaptation.md
git commit -m "feat: add PR adaptation prompt for Claude Code"
```

---

### Task 7: Update Claude Code step for adapt mode

**Files:**
- Modify: `action.yml` (Claude Code integration step)

- [ ] **Step 1: Update the Claude Code step for adapt mode**

The step should:
- In adapt mode: use `pr-adaptation.md` prompt, pass PR diff and changed files
- In init mode: keep using `initial-integration.md` (existing behavior)
- Skip if cosmetic-only or guard triggered

```yaml
    - name: Claude Code integration
      if: ${{ inputs.mode == 'init' || (inputs.mode == 'adapt' && steps.guard.outputs.skip != 'true' && steps.changes.outputs.types != 'cosmetic-only') }}
      shell: bash
      run: |
        MODE="${{ inputs.mode }}"
        ACTION_PATH="${{ github.action_path }}"
        CONTEXT_FILE="$ACTION_PATH/prompts/context.md"

        if [[ "$MODE" == "init" ]]; then
          PROMPT_FILE="$ACTION_PATH/prompts/initial-integration.md"
          {
            cat "$CONTEXT_FILE"
            echo ""
            cat "$PROMPT_FILE"
            echo ""
            echo "The project config is:"
            echo "- Copilot name: ${{ steps.config.outputs.copilot_name }}"
            echo "- Copilot color: ${{ steps.config.outputs.copilot_color }}"
            echo "- Domain: ${{ steps.config.outputs.domain }}"
            echo "- Description: ${{ steps.config.outputs.description }}"
          } | npx -y @anthropic-ai/claude-code@latest \
            --model claude-opus-4-6 \
            --print \
            --allowedTools "Edit,Read,Write,Bash,Glob,Grep"
        else
          PROMPT_FILE="$ACTION_PATH/prompts/pr-adaptation.md"
          {
            cat "$CONTEXT_FILE"
            echo ""
            cat "$PROMPT_FILE"
            echo ""
            echo "## Project config"
            echo "- Copilot name: ${{ steps.config.outputs.copilot_name }}"
            echo "- Copilot color: ${{ steps.config.outputs.copilot_color }}"
            echo "- Change categories: ${{ steps.changes.outputs.types }}"
            echo ""
            echo "## Changed files"
            cat /tmp/pr-changed-files.txt
            echo ""
            echo "## Diff"
            cat /tmp/pr-diff.patch
          } | npx -y @anthropic-ai/claude-code@latest \
            --model claude-opus-4-6 \
            --print \
            --allowedTools "Edit,Read,Write,Bash,Glob,Grep"
        fi
      env:
        CLAUDE_CODE_OAUTH_TOKEN: ${{ inputs.claude_code_oauth_token }}
```

- [ ] **Step 2: Commit**

```bash
git add action.yml
git commit -m "feat: update Claude Code step for adapt mode with PR diff context"
```

---

### Task 8: Update verify and commit/push for adapt mode

**Files:**
- Modify: `action.yml` (verify, clean, push steps)

- [ ] **Step 1: Update build verification step**

Replace the current verify step with mode-aware logic:

```yaml
    - name: Verify build
      if: ${{ inputs.mode == 'init' || (inputs.mode == 'adapt' && steps.guard.outputs.skip != 'true' && steps.changes.outputs.types != 'cosmetic-only') }}
      id: verify
      shell: bash
      run: |
        npm install
        if npm run build; then
          echo "status=pass" >> "$GITHUB_OUTPUT"
        else
          if [[ "${{ steps.preflight.outputs.status }}" == "fail" ]]; then
            echo "::warning::Build was already failing before adaptation"
            echo "status=pre-existing" >> "$GITHUB_OUTPUT"
          else
            echo "::error::Voice adaptation broke the build"
            echo "status=broken" >> "$GITHUB_OUTPUT"
          fi
          exit 1
        fi
```

- [ ] **Step 2: Update commit and push step for adapt mode**

Replace the current push step:

```yaml
    - name: Clean build artifacts
      if: ${{ inputs.mode == 'init' || (inputs.mode == 'adapt' && steps.guard.outputs.skip != 'true' && steps.changes.outputs.types != 'cosmetic-only') }}
      shell: bash
      run: rm -rf node_modules build dist server/node_modules

    - name: Commit and push
      id: push
      if: ${{ inputs.mode == 'init' || (inputs.mode == 'adapt' && steps.guard.outputs.skip != 'true' && steps.changes.outputs.types != 'cosmetic-only') }}
      shell: bash
      run: |
        MODE="${{ inputs.mode }}"
        BRANCH="${{ inputs.voice_agent_branch }}"
        PR="${{ inputs.pr_number }}"

        if [[ "$MODE" == "init" ]]; then
          git checkout -B "$BRANCH"
          git add -A
          if git diff --cached --quiet; then
            echo "No changes — skipping push"
            echo "skipped=true" >> "$GITHUB_OUTPUT"
            exit 0
          fi
          MAIN_SHORT=$(git rev-parse --short origin/main)
          git commit -m "chore: initialize voice-agent from main ${MAIN_SHORT}"
          git push --force origin "$BRANCH"
        else
          # Adapt mode: stage only voice-agent related files
          git add src/ server/ .voice-agent* 2>/dev/null || true
          if git diff --cached --quiet; then
            echo "No changes — skipping push"
            echo "skipped=true" >> "$GITHUB_OUTPUT"
            if [[ -n "$PR" ]]; then
              gh pr comment "$PR" --body "✅ No voice adaptation needed — PR is already compatible."
            fi
            exit 0
          fi
          git commit -m "chore: adapt voice-agent hooks for PR #${PR}"
          git push
        fi

        echo "skipped=false" >> "$GITHUB_OUTPUT"
      env:
        GH_TOKEN: ${{ inputs.github_token }}
```

- [ ] **Step 3: Add PR comment on success/failure**

```yaml
    - name: PR comment (success)
      if: ${{ inputs.mode == 'adapt' }} && steps.push.outputs.skipped == 'false'
      shell: bash
      run: |
        PR="${{ inputs.pr_number }}"
        [[ -n "$PR" ]] && gh pr comment "$PR" --body "✅ Voice hooks adapted. Please review the latest commit."
      env:
        GH_TOKEN: ${{ inputs.github_token }}

    - name: PR comment (build failure)
      if: ${{ inputs.mode == 'adapt' }} && failure() && steps.verify.outputs.status != ''
      shell: bash
      run: |
        PR="${{ inputs.pr_number }}"
        STATUS="${{ steps.verify.outputs.status }}"
        if [[ -n "$PR" ]]; then
          if [[ "$STATUS" == "pre-existing" ]]; then
            gh pr comment "$PR" --body "⚠️ Build was already failing before voice adaptation. Claude Code did not make it worse."
          else
            gh pr comment "$PR" --body "❌ Voice adaptation broke the build. Manual fix needed. Check the [workflow run](${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}) for details."
          fi
        fi
      env:
        GH_TOKEN: ${{ inputs.github_token }}
```

- [ ] **Step 4: Commit**

```bash
git add action.yml
git commit -m "feat: mode-aware verify, commit, push, and PR comments"
```

---

### Task 9: Clean up obsolete code

**Files:**
- Modify: `action.yml` (remove remaining dead steps not yet removed by earlier tasks)
- Delete: `scripts/save-ignored.sh`
- Delete: `scripts/restore-ignored.sh`

- [ ] **Step 1: Remove remaining obsolete steps from action.yml**

By this point, Tasks 1-8 have already replaced the merge/hash steps. Remove any remaining dead steps:
- "Detect mode (initial vs incremental)" — replaced by `mode` input
- "Save ignored files" — no longer needed
- "Restore ignored files" — no longer needed
- "Write content hash" — no longer needed

Also add a note: fork-based PRs are not supported (push to PR branch will fail for cross-fork PRs).

- [ ] **Step 2: Guard scaffold step with init mode**

The scaffold step should only run in init mode:

```yaml
    - name: Scaffold from templates
      if: ${{ inputs.mode == 'init' }}
      shell: bash
      run: ${{ github.action_path }}/scripts/scaffold.sh
```

- [ ] **Step 3: Delete unused scripts**

```bash
rm scripts/save-ignored.sh scripts/restore-ignored.sh
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: remove merge-based sync, keep only init and adapt paths"
```

---

### Task 10: Create workflow templates for consuming repos

**Files:**
- Modify: `templates/voice-agent-adapt.yml` (may exist or create)
- Modify: `templates/voice-agent-init.yml` (may exist or create)

- [ ] **Step 1: Create voice-agent-adapt.yml template**

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
    env:
      FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: "true"
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

- [ ] **Step 2: Create voice-agent-init.yml template**

```yaml
name: Voice Agent Init
on:
  workflow_dispatch:
jobs:
  init:
    runs-on: self-hosted
    permissions:
      contents: write
    env:
      FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: "true"
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

- [ ] **Step 3: Commit**

```bash
git add templates/
git commit -m "feat: add workflow templates for voice-agent-adapt and voice-agent-init"
```

---

### Task 11: Deploy to Swkenya

**Files:**
- Modify: `Swkenya/.github/workflows/voice-agent-sync.yml` → rename to `voice-agent-adapt.yml`

- [ ] **Step 1: Replace Swkenya workflow**

Delete `Swkenya/.github/workflows/voice-agent-sync.yml` and create `voice-agent-adapt.yml` from the template (Task 10 Step 1).

- [ ] **Step 2: Create voice-agent-init.yml in Swkenya**

Copy from template (Task 10 Step 2).

- [ ] **Step 3: Commit and push Swkenya**

```bash
cd Swkenya
git rm .github/workflows/voice-agent-sync.yml
git add .github/workflows/voice-agent-adapt.yml .github/workflows/voice-agent-init.yml
git commit -m "feat: switch to PR-based voice agent adaptation"
git push origin voice-agent
```

- [ ] **Step 4: Push voice-agent-action**

```bash
cd voice-agent-action
git push origin main
```

---

### Task 12: End-to-end test

- [ ] **Step 1: Create a test PR on Swkenya**

From voice-agent, create a test branch, make a small component change, open a PR targeting voice-agent.

```bash
cd Swkenya
git checkout -b test/adapt-workflow voice-agent
# Make a small change to a component
git push origin test/adapt-workflow
gh pr create --base voice-agent --title "test: verify adapt workflow" --body "Testing PR-based adaptation"
```

- [ ] **Step 2: Verify the action runs**

Check GitHub Actions — the "Voice Agent Adapt" workflow should trigger on the PR.

- [ ] **Step 3: Verify bot guard prevents loop**

After the action pushes an adaptation commit, confirm the second trigger is skipped by the bot guard.

- [ ] **Step 4: Review and close test PR**

Review the adaptation commit. If correct, close/delete the test PR and branch.

- [ ] **Step 5: Commit test results**

If any fixes were needed during testing, commit them.
