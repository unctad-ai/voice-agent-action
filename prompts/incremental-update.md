# Incremental Voice Agent Update

The designer updated the React project on `main`. Analyze what changed and update voice agent integration files accordingly.

## Context

The action provides these inputs:
- **Change categories** (from `detect-changes.sh`): `services`, `navigation`, `forms`, `components`, `cosmetic`, `other`
- **Previous voice-agent branch** was backed up and manual additions preserved

## What to update based on change categories

### If `services` changed

Re-read `src/data/services.ts` and update:
- `src/voice-config.ts` — services array, synonyms
- `server/voice-config.ts` — services array, coreIds, extraServerTools references

Verify all service IDs still exist. Remove references to deleted services, add new ones.

### If `navigation` changed

Re-read `src/App.tsx` routes and update:
- `src/voice-config.ts` — routeMap, getServiceFormRoute
- `server/voice-config.ts` — routeMap, getServiceFormRoute

Check `.voice-agent.yml` `exclude_routes` — new routes may need exclusion.

### If `forms` changed

For each changed form component (`*Application*.tsx`, `*Form*.tsx`):
1. Read the golden reference at `golden-reference/after.tsx` for correct patterns
2. Read the new version of the component from `main`
3. Re-apply voice agent hooks using the same rules as initial integration:
   - `useProgressiveFields` with correct types, IDs, labels, visibility
   - `useRegisterUIAction` for button actions
   - `useRegisterTabSwitchAction` for tabs
   - `useRegisterSubmitAction` for submission
4. Compare with the preserved version to minimize unnecessary changes
5. Flag in output if significant differences found

### If `cosmetic` only

Do nothing. The action skips Claude Code entirely for cosmetic-only changes (CSS, images, assets). This prompt is never called in that case.

### If `components` changed (non-form)

Check if the changed components are referenced in voice-config navigation targets. If a component was renamed or removed, update routeMap accordingly. No form hook changes needed.

## Rules

1. **Only modify voice-agent files** — voice-config.ts files and form component hook additions
2. **Never modify the designer's original code** — no restructuring, no style changes
3. **Trust the JSX** — field types come from actual HTML elements, not assumptions
4. **Never fabricate options** — only extract from actual `<option>` elements
5. **Preserve existing patterns** — if the previous integration had correct hook calls that still apply, keep them
6. **Verify after changes** — run `npm run build` to confirm no type errors

## Output

List all files modified and why:
```
MODIFIED: src/voice-config.ts (new service added: export-permit)
MODIFIED: server/voice-config.ts (new service added, coreIds updated)
UNCHANGED: src/components/ApplicationForm.tsx (main didn't change this form)
RE-INTEGRATED: src/components/NewForm.tsx (designer changed form structure)
```
