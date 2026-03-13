# Design: Fix scaffold/restore ordering in Voice Agent Sync

**Date:** 2026-03-13
**Repo:** `unctad-ai/voice-agent-action`

## Problem

When the content hash is unchanged (no source changes on main), the action skips Claude Code and restores files from the existing `voice-agent` branch. This restore step overwrites scaffold-generated files (`voice-config.ts`) with stale versions, preventing template updates from propagating to consuming projects.

Additionally, `.voice-agent.yml` config changes (color, greeting, language) don't bust the content hash because the hash only watches source files (`src/data/services.ts`, `src/App.tsx`, form components).

### Current step order

```
1. Preserve manual additions
2. Scaffold from templates          ← writes fresh voice-config.ts
3. Content hash check               ← unchanged → skip=true
4. Restore Claude-modified files    ← OVERWRITES scaffold output
5. Claude Code (skipped)
6. Restore preserved files
7. Verify build
8. Commit + push
```

### Impact

- Template field additions (e.g. `greetingMessage`, `avatarUrl`, `language`) never reach deployed projects
- `.voice-agent.yml` changes (copilot color, greeting, language) are silently ignored
- Only a content change on main (new services, components) triggers a full re-integration

## Solution

Two changes:

### 1. Move scaffold AFTER the restore step

```
1. Preserve manual additions
2. Content hash check
3. Restore Claude-modified files    ← restores Claude's App.tsx, components, etc.
4. Scaffold from templates          ← stamps fresh voice-config.ts ON TOP of restore
5. Claude Code (if not skipped)
6. Restore preserved files
7. Verify build
8. Commit + push
```

Scaffold always runs and always wins for its files. Restore always wins for Claude Code's files. Neither needs to know about the other's file list.

When Claude Code runs (skip=false), it reads the fresh scaffold output and patches source files. When skipped, restored files + fresh scaffold = correct state.

### 2. Add `.voice-agent.yml` to content hash

Include the config file in the hash so config-only changes (color, greeting, language) trigger a Claude Code re-run:

```bash
CLAUDE_INPUTS=".voice-agent.yml src/data/services.ts src/App.tsx"
CLAUDE_INPUTS="$CLAUDE_INPUTS $(find src/components -type f \( -name '*Application*' -o -name '*Form*' \) 2>/dev/null || true)"
```

This ensures that changing `copilot_color` or `language` in `.voice-agent.yml` busts the cache.

## Changes

### `action.yml`

1. **Move "Scaffold from templates" step** (currently step after "Preserve manual additions") to after "Restore Claude-modified files (when skipping Claude Code)"
2. **Update content hash inputs** to include `.voice-agent.yml`

### No other files change

`scaffold.sh`, `preserve-manual.sh`, `verify.sh`, templates — all unchanged.

## Edge cases

| Scenario | Before | After |
|----------|--------|-------|
| Template adds new SiteConfig field | Field never appears (restore overwrites) | Field appears on next sync |
| `.voice-agent.yml` color change | Ignored (hash unchanged) | Triggers Claude Code re-run |
| Content change on main | Full re-integration (correct) | Same — full re-integration |
| No changes at all | Tree hash check skips push (correct) | Same — tree hash check skips push |
| Initial mode (no voice-agent branch) | Scaffold → Claude Code (correct) | Same — restore step is skipped (mode != incremental) |

## Risk

Low. The reorder only affects the incremental+skip path. Initial mode and incremental+Claude Code paths are unaffected because:
- Initial mode: restore step doesn't run (condition `steps.mode.outputs.mode == 'incremental'` is false)
- Incremental + Claude Code: restore step doesn't run (condition `steps.content_hash.outputs.skip == 'true'` is false), and scaffold already ran before Claude Code in the old order too

The scaffold running after restore in the skip path is the only behavioral change, and it's the correct behavior.
