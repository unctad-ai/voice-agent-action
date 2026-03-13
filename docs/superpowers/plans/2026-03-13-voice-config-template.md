# Voice Config Template Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make voice-config files scaffolded templates so the app always boots, even if Claude Code fails.

**Architecture:** Add `.tmpl` template files for both `server/voice-config.ts` and `src/voice-config.ts` with a placeholder service. `scaffold.sh` substitutes config values using node. `verify.sh` validates critical files before pushing. Claude Code prompts updated from "generate" to "enhance."

**Tech Stack:** Bash, Node.js (for safe string substitution), GitHub Actions composite action

**Spec:** `docs/superpowers/specs/2026-03-13-voice-config-template-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `templates/server/voice-config.ts.tmpl` | Create | Server voice-config template with placeholder service |
| `templates/src/voice-config.ts.tmpl` | Create | Client voice-config template with placeholder service |
| `scripts/scaffold.sh` | Modify (after line 22) | Add node-based template substitution for both configs |
| `scripts/verify.sh` | Modify (before line 7) | Add critical file + import resolution checks |
| `action.yml` | Modify (lines 47, 93-95, 116-134) | Parse new config fields, pass env vars, revert file-existence checks |
| `prompts/initial-integration.md` | Modify (sections 2-3) | "Generate" → "Enhance the scaffolded" |
| `prompts/incremental-update.md` | Modify (top) | Add placeholder detection note |

---

## Chunk 1: Templates

### Task 1: Create server voice-config template

**Files:**
- Create: `templates/server/voice-config.ts.tmpl`

- [ ] **Step 1: Create the template file**

```typescript
import type { SiteConfig } from '@unctad-ai/voice-agent-core';

const services = [
  { id: 'general-help', title: 'General assistance', category: 'General' },
];

const categories = [
  { title: 'General', services },
];

const categoryMap: Record<string, string> = {};
for (const s of services) {
  categoryMap[s.id] = s.category;
}

const synonyms: Record<string, string[]> = {};

const routeMap: Record<string, string> = {
  home: '/',
};

function getServiceFormRoute(_serviceId: string): string | null {
  return null;
}

export const siteConfig: SiteConfig = {
  copilotName: '__COPILOT_NAME__',
  siteTitle: '__SITE_TITLE__',
  farewellMessage: '__FAREWELL_MESSAGE__',
  systemPromptIntro: '__SYSTEM_PROMPT_INTRO__',
  colors: {
    primary: '__COPILOT_COLOR__',
    processing: '__COPILOT_COLOR__',
    speaking: '__COPILOT_COLOR__',
    glow: '__COPILOT_COLOR__66',
  },
  services,
  categories,
  synonyms,
  categoryMap,
  routeMap,
  getServiceFormRoute,
};
```

- [ ] **Step 2: Verify placeholders are unique strings**

Run: `grep -c '__' templates/server/voice-config.ts.tmpl`
Expected: 9 matches (5 unique placeholders, some repeated in colors)

### Task 2: Create client voice-config template

**Files:**
- Create: `templates/src/voice-config.ts.tmpl`

- [ ] **Step 1: Create the template file**

Same structure as server but with client-only placeholders (`__GREETING_MESSAGE__`, `__AVATAR_URL__`) and a minimal `systemPromptIntro` default (required by SiteConfig type but not used client-side):

```typescript
import type { SiteConfig } from '@unctad-ai/voice-agent-core';

const services = [
  { id: 'general-help', title: 'General assistance', category: 'General' },
];

const categories = [
  { title: 'General', services },
];

const categoryMap: Record<string, string> = {};
for (const s of services) {
  categoryMap[s.id] = s.category;
}

const synonyms: Record<string, string[]> = {};

const routeMap: Record<string, string> = {
  home: '/',
};

function getServiceFormRoute(_serviceId: string): string | null {
  return null;
}

export const siteConfig: SiteConfig = {
  copilotName: '__COPILOT_NAME__',
  siteTitle: '__SITE_TITLE__',
  farewellMessage: '__FAREWELL_MESSAGE__',
  systemPromptIntro: 'You are __COPILOT_NAME__.',
  colors: {
    primary: '__COPILOT_COLOR__',
    processing: '__COPILOT_COLOR__',
    speaking: '__COPILOT_COLOR__',
    glow: '__COPILOT_COLOR__66',
  },
  // Client-only: __GREETING_MESSAGE__ and __AVATAR_URL__ are substituted by scaffold
  // but consumed at runtime by the UI components, not embedded in this config object.
  // They are passed via VoiceAgentProvider props in App.tsx.
  services,
  categories,
  synonyms,
  categoryMap,
  routeMap,
  getServiceFormRoute,
};
```

Note: `__GREETING_MESSAGE__` and `__AVATAR_URL__` are substituted in the file by scaffold but are not SiteConfig fields — they're used by Claude Code when wiring `App.tsx` (passed as props to `VoiceAgentProvider` or `GlassCopilotPanel`). The scaffold writes them as comments at the top of the file so Claude Code knows the values:

```typescript
// Voice Agent Settings (from .voice-agent.yml)
// greeting: __GREETING_MESSAGE__
// avatar: __AVATAR_URL__
```

`systemPromptIntro` is required by the SiteConfig type even on the client, so we set a minimal default. The server template uses `__SYSTEM_PROMPT_INTRO__` for the real LLM prompt.

- [ ] **Step 2: Commit templates**

```bash
git add templates/server/voice-config.ts.tmpl templates/src/voice-config.ts.tmpl
git commit -m "feat: add voice-config template files with placeholder service"
```

---

## Chunk 2: Scaffold & Verify

### Task 3: Update scaffold.sh to produce voice-config files

**Files:**
- Modify: `scripts/scaffold.sh:20-22` (after `COPILOT` variable and sed lines)

- [ ] **Step 1: Add voice-config templating after line 22**

Insert after the existing `sed "s|__COPILOT_NAME__|${COPILOT}|g" "$TEMPLATES/server/.env.example" > server/.env.example` line:

```bash
# Voice config files (node substitution — safe for all characters in user values)
echo "=== Scaffold: generating voice-config files ==="

SITE_TITLE="${SITE_TITLE:-$DESCRIPTION}"
FAREWELL="${FAREWELL_MESSAGE:-Thank you for using ${COPILOT}. Have a great day!}"
SYSTEM_INTRO="${SYSTEM_PROMPT_INTRO:-You are ${COPILOT}, the virtual assistant for ${DESCRIPTION:-this portal}.}"
GREETING="${GREETING_MESSAGE:-Hi, I'm ${COPILOT}. How can I help you today?}"
AVATAR="${AVATAR_URL:-}"

node -e "
  const fs = require('fs');
  const T = process.env.TEMPLATES;
  const sub = (tpl, subs) => {
    let t = fs.readFileSync(tpl, 'utf8');
    for (const [k, v] of Object.entries(subs)) t = t.split(k).join(v);
    return t;
  };

  const baseSubs = {
    '__COPILOT_NAME__': process.env.COPILOT_NAME || 'Assistant',
    '__COPILOT_COLOR__': process.env.COPILOT_COLOR || '#1B5E20',
    '__SITE_TITLE__': process.env.SITE_TITLE || '',
    '__FAREWELL_MESSAGE__': process.env.FAREWELL_MESSAGE || '',
  };

  // Server config
  const serverSubs = { ...baseSubs, '__SYSTEM_PROMPT_INTRO__': process.env.SYSTEM_PROMPT_INTRO || '' };
  fs.writeFileSync('server/voice-config.ts', sub(T + '/server/voice-config.ts.tmpl', serverSubs));
  console.log('  Created server/voice-config.ts');

  // Client config
  const clientSubs = { ...baseSubs, '__GREETING_MESSAGE__': process.env.GREETING_MESSAGE || '', '__AVATAR_URL__': process.env.AVATAR_URL || '' };
  fs.mkdirSync('src', { recursive: true });
  fs.writeFileSync('src/voice-config.ts', sub(T + '/src/voice-config.ts.tmpl', clientSubs));
  console.log('  Created src/voice-config.ts');
"
```

The node script reads env vars set by scaffold.sh defaults, so it works even if action.yml doesn't pass them (standalone scaffold usage).

Environment variables used: `TEMPLATES` (already set at line 6), `COPILOT_NAME` (already set), `COPILOT_COLOR`, `SITE_TITLE`, `FAREWELL_MESSAGE`, `SYSTEM_PROMPT_INTRO`, `GREETING_MESSAGE`, `AVATAR_URL`, `DESCRIPTION`.

Note: `LANGUAGE` is parsed by action.yml and passed to scaffold but not consumed by any template yet — reserved for future TTS locale integration.

- [ ] **Step 2: Export the new variables for the node subshell**

The bash defaults (`SITE_TITLE`, `FAREWELL`, etc.) need to be exported so the node `-e` script can read them via `process.env`. Add these exports before the node call:

```bash
export TEMPLATES COPILOT_NAME="${COPILOT}" COPILOT_COLOR="${COPILOT_COLOR:-#1B5E20}"
export SITE_TITLE FAREWELL_MESSAGE="${FAREWELL}" SYSTEM_PROMPT_INTRO="${SYSTEM_INTRO}"
export GREETING_MESSAGE="${GREETING}" AVATAR_URL="${AVATAR}" DESCRIPTION="${DESCRIPTION:-}"
```

Note: `TEMPLATES` is already set at scaffold.sh line 6 but not exported. The export makes it visible to the node subprocess.

- [ ] **Step 3: Test scaffold locally**

Run from the voice-agent-action repo root with a test project directory:

```bash
mkdir -p /tmp/scaffold-test && cd /tmp/scaffold-test
mkdir -p src
echo '{"dependencies":{}}' > package.json
cat > .voice-agent.yml << 'EOF'
copilot_name: "TestBot"
copilot_color: "#FF0000"
domain: "test.example.com"
description: "Test portal with pipes | and ampersands &"
EOF
cat > vite.config.ts << 'EOF'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'
export default defineConfig({
  plugins: [react()],
})
EOF
COPILOT_NAME=TestBot VOICE_AGENT_VERSION=latest /Users/moulaymehdi/PROJECTS/figma/voice-agent-action/scripts/scaffold.sh
```

Expected: `server/voice-config.ts` and `src/voice-config.ts` exist with `TestBot` substituted, no `__PLACEHOLDER__` tokens remain, special characters `|` and `&` preserved correctly.

```bash
grep -c '__' /tmp/scaffold-test/server/voice-config.ts /tmp/scaffold-test/src/voice-config.ts
```

Expected: 0 matches in both files.

```bash
grep 'TestBot' /tmp/scaffold-test/server/voice-config.ts
```

Expected: `copilotName: 'TestBot'` present.

- [ ] **Step 4: Commit**

```bash
git add scripts/scaffold.sh
git commit -m "feat: scaffold voice-config files from templates with node substitution"
```

### Task 4: Add critical file checks to verify.sh

**Files:**
- Modify: `scripts/verify.sh:4` (insert after `FAILED=0`, before Docker check)

- [ ] **Step 1: Add file existence and import resolution checks**

Insert after line 4 (`FAILED=0`), before line 6 (`# Check Docker availability`):

```bash
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
```

Note: The early exit (`exit 1`) on critical file failure intentionally skips Docker builds — no point running expensive builds if core files are missing.

- [ ] **Step 2: Test verify locally against scaffold output**

```bash
cd /tmp/scaffold-test
/Users/moulaymehdi/PROJECTS/figma/voice-agent-action/scripts/verify.sh
```

Expected: "Critical files" check passes (all 3 files exist, imports resolve). Docker check will warn (no Docker context) but critical files pass.

- [ ] **Step 3: Test verify catches missing files**

```bash
cd /tmp/scaffold-test
rm server/voice-config.ts
/Users/moulaymehdi/PROJECTS/figma/voice-agent-action/scripts/verify.sh
```

Expected: Fails with `::error::Missing critical file: server/voice-config.ts`

- [ ] **Step 4: Commit**

```bash
git add scripts/verify.sh
git commit -m "feat: add critical file and import resolution checks to verify.sh"
```

---

## Chunk 3: Action & Prompts

### Task 5: Update action.yml config parsing and env vars

**Files:**
- Modify: `action.yml:47` (keys array in Read config step)
- Modify: `action.yml:93-95` (env block in Scaffold step)
- Modify: `action.yml:116-134` (revert file-existence checks in content hash step)

- [ ] **Step 1: Expand keys array in "Read config" step**

At `action.yml:47`, replace:

```javascript
const keys = ['copilot_name','copilot_color','domain','description','voice_agent_version','auto_merge_incremental'];
```

With:

```javascript
const keys = ['copilot_name','copilot_color','domain','description','voice_agent_version','auto_merge_incremental','site_title','farewell_message','system_prompt_intro','greeting_message','avatar_url','language'];
```

- [ ] **Step 2: Add env vars to "Scaffold from templates" step**

At `action.yml:93-95`, replace:

```yaml
      env:
        COPILOT_NAME: ${{ steps.config.outputs.copilot_name }}
        VOICE_AGENT_VERSION: ${{ steps.config.outputs.voice_agent_version }}
```

With:

```yaml
      env:
        COPILOT_NAME: ${{ steps.config.outputs.copilot_name }}
        COPILOT_COLOR: ${{ steps.config.outputs.copilot_color }}
        VOICE_AGENT_VERSION: ${{ steps.config.outputs.voice_agent_version }}
        DESCRIPTION: ${{ steps.config.outputs.description }}
        SITE_TITLE: ${{ steps.config.outputs.site_title }}
        FAREWELL_MESSAGE: ${{ steps.config.outputs.farewell_message }}
        SYSTEM_PROMPT_INTRO: ${{ steps.config.outputs.system_prompt_intro }}
        GREETING_MESSAGE: ${{ steps.config.outputs.greeting_message }}
        AVATAR_URL: ${{ steps.config.outputs.avatar_url }}
        LANGUAGE: ${{ steps.config.outputs.language }}
```

- [ ] **Step 3: Revert file-existence checks in content hash step**

At `action.yml:117-134`, replace the entire block from `mkdir -p .voice-agent` to the closing `fi`:

```yaml
        mkdir -p .voice-agent
        echo "$HASH" > .voice-agent/content-hash

        # Safety: never skip if critical voice-config files are missing from the branch
        BRANCH="origin/${{ inputs.voice_agent_branch }}"
        CONFIGS_OK=true
        for f in server/voice-config.ts src/voice-config.ts; do
          if ! git show "${BRANCH}:${f}" &>/dev/null; then
            echo "  Missing ${f} on ${BRANCH} — will force Claude Code"
            CONFIGS_OK=false
          fi
        done

        if [[ "$HASH" == "$OLD_HASH" && "${{ steps.mode.outputs.mode }}" == "incremental" && "$CONFIGS_OK" == "true" ]]; then
          echo "skip=true" >> "$GITHUB_OUTPUT"
          echo "Content unchanged — skipping Claude Code"
        else
          echo "skip=false" >> "$GITHUB_OUTPUT"
        fi
```

Replace with the original simpler version (templates make the safety check unnecessary):

```yaml
        mkdir -p .voice-agent
        echo "$HASH" > .voice-agent/content-hash
        if [[ "$HASH" == "$OLD_HASH" && "${{ steps.mode.outputs.mode }}" == "incremental" ]]; then
          echo "skip=true" >> "$GITHUB_OUTPUT"
          echo "Content unchanged — skipping Claude Code"
        else
          echo "skip=false" >> "$GITHUB_OUTPUT"
        fi
```

- [ ] **Step 4: Commit**

```bash
git add action.yml
git commit -m "feat: parse new voice-agent settings and pass to scaffold"
```

### Task 6: Update Claude Code prompts

**Files:**
- Modify: `prompts/initial-integration.md:113,152` (section headers)
- Modify: `prompts/incremental-update.md:1-10` (add context note)

- [ ] **Step 1: Update initial-integration.md section 2 header and intro**

At line 113, replace:

```markdown
## 2. Generate `src/voice-config.ts`
```

With:

```markdown
## 2. Enhance the scaffolded `src/voice-config.ts`

> The scaffold has already created this file with a placeholder service and defaults from `.voice-agent.yml`. Replace the placeholder service array with real services extracted from the codebase. Keep the existing config fields (copilotName, colors, farewellMessage, etc.) — only update services, categories, categoryMap, synonyms, routeMap, and getServiceFormRoute.
```

- [ ] **Step 2: Update initial-integration.md section 3 header and intro**

At line 152, replace:

```markdown
## 3. Generate `server/voice-config.ts`
```

With:

```markdown
## 3. Enhance the scaffolded `server/voice-config.ts`

> Same as above — the scaffold created a bootable default. Replace the placeholder service with real services. Additionally add extraServerTools and coreIds based on the project's domain.
```

- [ ] **Step 3: Add placeholder detection to incremental-update.md**

After the existing "## Context" section (line 3), add:

```markdown
## Placeholder Detection

If `server/voice-config.ts` or `src/voice-config.ts` only contain the scaffold placeholder (a single `general-help` service), treat this as an initial integration for those files — extract real services from the codebase using the process described in `initial-integration.md` sections 2 and 3.
```

- [ ] **Step 4: Commit**

```bash
git add prompts/initial-integration.md prompts/incremental-update.md
git commit -m "docs: update prompts to enhance scaffolded configs instead of generating"
```

### Task 7: Final validation

- [ ] **Step 1: Run full scaffold + verify test**

```bash
cd /tmp && rm -rf scaffold-test && mkdir scaffold-test && cd scaffold-test
mkdir -p src server
echo '{"dependencies":{}}' > package.json
cat > .voice-agent.yml << 'EOF'
copilot_name: "Pesa"
copilot_color: "#DB2129"
domain: "kenya.singlewindow.dev"
description: "Kenya Trade Single Window — business registration, permits & investment services"
site_title: "Kenya Trade Single Window"
farewell_message: "Kwaheri! Thank you for using Pesa."
EOF
cat > vite.config.ts << 'EOF'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'
export default defineConfig({
  plugins: [react()],
})
EOF
COPILOT_NAME=Pesa COPILOT_COLOR="#DB2129" DESCRIPTION="Kenya Trade Single Window — business registration, permits & investment services" SITE_TITLE="Kenya Trade Single Window" FAREWELL_MESSAGE="Kwaheri! Thank you for using Pesa." VOICE_AGENT_VERSION=latest /Users/moulaymehdi/PROJECTS/figma/voice-agent-action/scripts/scaffold.sh
```

Verify:
- `cat server/voice-config.ts` — contains `copilotName: 'Pesa'`, `primary: '#DB2129'`, `Kwaheri!` in farewell
- `cat src/voice-config.ts` — contains `copilotName: 'Pesa'`
- No `__` placeholders remain: `grep -c '__' server/voice-config.ts src/voice-config.ts` → 0
- `&` in description preserved correctly

```bash
/Users/moulaymehdi/PROJECTS/figma/voice-agent-action/scripts/verify.sh
```

Expected: Critical files check passes.

- [ ] **Step 2: Verify action.yml parses correctly**

Manually inspect `action.yml` for:
- Keys array has 12 entries
- Scaffold env block has 10 vars
- Content hash step has NO `CONFIGS_OK` variable
- Mode detection still checks both `src/voice-config.ts` AND `server/voice-config.ts`

- [ ] **Step 3: Verify prompts**

```bash
grep -c "Enhance the scaffolded" prompts/initial-integration.md
```

Expected: 2 (one for section 2, one for section 3)

```bash
grep -c "general-help" prompts/incremental-update.md
```

Expected: 1 (placeholder detection note)

- [ ] **Step 4: Final commit with all docs**

```bash
git add docs/
git commit -m "docs: add spec and implementation plan for voice-config templates"
```
