# Voice Config Template & Settings Externalization

**Date:** 2026-03-13
**Status:** Approved
**Scope:** `voice-agent-action` repo only

## Problem

`server/voice-config.ts` and `src/voice-config.ts` are generated entirely by Claude Code during the GitHub Action workflow. If Claude Code fails, times out, or the files get lost (as happened when Figma Make reverted the voice-agent integration on Swkenya), the deployed app crash-loops with `ERR_MODULE_NOT_FOUND` or `TypeError: Cannot convert undefined or null to object`.

There is no fallback — the app cannot boot without these files.

## Solution

Make both voice-config files **scaffolded templates** with sensible defaults, so the app always boots. Claude Code enhances them with real services extracted from the codebase. Additionally, externalize user-facing settings to `.voice-agent.yml` so a future settings UI can edit them without touching code.

### Safety Model (three layers, any can fail)

1. **Scaffold** — always produces bootable files with a placeholder service
2. **Restore** — copies enhanced files from previous branch (incremental mode)
3. **Claude Code** — extracts real services and enhances configs

If Claude Code runs but partially breaks a config, `verify.sh` catches TypeScript/build errors before the branch is pushed — the workflow fails instead of deploying a broken branch.

## New `.voice-agent.yml` Fields

These are settings a non-developer admin would customize through a settings UI.

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `site_title` | string | `"{description}"` | Portal title shown in UI |
| `farewell_message` | string | `"Thank you for using {copilot_name}. Have a great day!"` | Copilot goodbye message |
| `system_prompt_intro` | string | `"You are {copilot_name}, the virtual assistant for {description}."` | Opening line of LLM system prompt |
| `greeting_message` | string | `"Hi, I'm {copilot_name}. How can I help you today?"` | First message when panel opens |
| `avatar_url` | string | _(empty)_ | Custom copilot avatar URL |
| `language` | string | `"en"` | Reserved for future TTS locale integration |

Existing fields unchanged: `copilot_name`, `copilot_color`, `domain`, `description`, `voice_agent_version`, `auto_merge_incremental`, `exclude_routes`.

**Not externalized** (codebase-derived, Claude Code generates): services, synonyms, categories, categoryMap, routeMap, getServiceFormRoute, extraServerTools.

## Changes

### 1. New template: `templates/server/voice-config.ts.tmpl`

Server-side voice config with:
- Single placeholder service `{ id: 'general-help', title: 'General assistance', category: 'General' }` — prevents `z.enum([])` crash
- `categories` and `categoryMap` derived from services array
- Empty `synonyms: {}` (safe — `Object.keys({})` returns `[]`)
- Minimal `routeMap` with home route
- No-op `getServiceFormRoute` returning `null`
- All identity/branding fields use `__PLACEHOLDER__` style tokens for node substitution

Fields used: `__COPILOT_NAME__`, `__COPILOT_COLOR__`, `__SITE_TITLE__`, `__FAREWELL_MESSAGE__`, `__SYSTEM_PROMPT_INTRO__`.

Colors derive `processing`/`speaking` from primary, `glow` appends `66` (40% opacity).

### 2. New template: `templates/src/voice-config.ts.tmpl`

Client-side voice config with same structure as server, plus:
- `__GREETING_MESSAGE__` placeholder (client-only)
- `__AVATAR_URL__` placeholder (client-only)
- No `systemPromptIntro` (server-only)

### 3. Edit: `scripts/scaffold.sh`

After existing server file copies, add voice-config templating. **Use node (not sed) for substitution** to avoid metacharacter issues with user-provided strings (descriptions containing `|`, `&`, quotes, etc.):

```bash
# Defaults for new fields
SITE_TITLE="${SITE_TITLE:-$DESCRIPTION}"
FAREWELL="${FAREWELL_MESSAGE:-Thank you for using ${COPILOT}. Have a great day!}"
SYSTEM_INTRO="${SYSTEM_PROMPT_INTRO:-You are ${COPILOT}, the virtual assistant for ${DESCRIPTION}.}"
GREETING="${GREETING_MESSAGE:-Hi, I'm ${COPILOT}. How can I help you today?}"
AVATAR="${AVATAR_URL:-}"

# Server voice-config (node substitution — safe for all characters in values)
node -e "
  const fs = require('fs');
  let t = fs.readFileSync('$TEMPLATES/server/voice-config.ts.tmpl', 'utf8');
  const subs = {
    '__COPILOT_NAME__': process.env.COPILOT_NAME || 'Assistant',
    '__COPILOT_COLOR__': process.env.COPILOT_COLOR || '#1B5E20',
    '__SITE_TITLE__': process.env.SITE_TITLE || '',
    '__FAREWELL_MESSAGE__': process.env.FAREWELL_MESSAGE || '',
    '__SYSTEM_PROMPT_INTRO__': process.env.SYSTEM_PROMPT_INTRO || '',
  };
  for (const [k, v] of Object.entries(subs)) t = t.split(k).join(v);
  fs.writeFileSync('server/voice-config.ts', t);
"

# Client voice-config (same pattern, plus client-only fields)
node -e "
  const fs = require('fs');
  let t = fs.readFileSync('$TEMPLATES/src/voice-config.ts.tmpl', 'utf8');
  const subs = {
    '__COPILOT_NAME__': process.env.COPILOT_NAME || 'Assistant',
    '__COPILOT_COLOR__': process.env.COPILOT_COLOR || '#1B5E20',
    '__SITE_TITLE__': process.env.SITE_TITLE || '',
    '__FAREWELL_MESSAGE__': process.env.FAREWELL_MESSAGE || '',
    '__GREETING_MESSAGE__': process.env.GREETING_MESSAGE || '',
    '__AVATAR_URL__': process.env.AVATAR_URL || '',
  };
  for (const [k, v] of Object.entries(subs)) t = t.split(k).join(v);
  fs.writeFileSync('src/voice-config.ts', t);
"
```

The `split(k).join(v)` pattern is safe for all characters — no regex metacharacter issues.

### 4. Edit: `scripts/verify.sh`

Add critical file and import resolution checks **before** the Docker build step. Use node instead of `grep -oP` for portability:

```bash
echo "=== Verify: Critical files ==="
MISSING=0
for f in server/voice-config.ts src/voice-config.ts server/index.ts; do
  if [ ! -f "$f" ]; then
    echo "::error::Missing critical file: $f"
    MISSING=1
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
" || MISSING=1

if [ "$MISSING" -ne 0 ]; then
  echo "=== Verify: FAILED (missing files) ==="
  exit 1
fi
```

### 5. Edit: `action.yml`

**"Read config" step** — add new keys to the node YAML parser:

```javascript
// Add to the keys array:
const keys = [
  'copilot_name','copilot_color','domain','description',
  'voice_agent_version','auto_merge_incremental',
  'site_title','farewell_message','system_prompt_intro',
  'greeting_message','avatar_url','language'
];
```

**"Scaffold from templates" step** — pass new env vars:

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

**Mode detection** — keep existing check for `src/voice-config.ts` on the branch. This still works correctly: mode detection runs *before* scaffold, so it checks the *branch*, not the working directory. If `src/voice-config.ts` is missing from the branch, it means Claude Code never enhanced the scaffold, so initial mode is correct.

**Revert content hash file-existence checks** added during the Kenya debugging session. With templates, even if restore fails, scaffold default is in place. The content hash skip is safe again.

**"Restore Claude-modified files" step** — unchanged. Still useful for copying enhanced configs from previous branch. If restore finds nothing, scaffold default is already in place.

### 6. Edit: `prompts/initial-integration.md`

Sections 2 and 3:
- "Generate `src/voice-config.ts`" → "Enhance the scaffolded `src/voice-config.ts`"
- "Generate `server/voice-config.ts`" → "Enhance the scaffolded `server/voice-config.ts`"
- Add note: "The scaffold has already created these files with a placeholder service and defaults from `.voice-agent.yml`. Replace the placeholder service array with real services extracted from the codebase. Keep the existing config fields (copilotName, colors, farewellMessage, etc.) — only update services, categories, categoryMap, synonyms, routeMap, and getServiceFormRoute."

### 7. Edit: `prompts/incremental-update.md`

Add note: "If `server/voice-config.ts` or `src/voice-config.ts` only contain the scaffold placeholder (single `general-help` service), treat this as an initial integration for those files — extract real services from the codebase."

## Out of Scope

- Changes to `@unctad-ai/voice-agent-*` packages
- Changes to consuming repos (Kenya, Bhutan, etc.)
- Building the settings UI itself
- Migration of existing deployments (they already have enhanced voice-configs)
