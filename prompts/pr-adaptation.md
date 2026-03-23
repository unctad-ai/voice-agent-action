# PR Adaptation — Voice Hook Integration

A PR targeting `voice-agent` has landed with designer changes from `main`. Adapt the voice agent hooks to match the new code. Work ONLY on the changed files listed below.

## 0. Study the golden reference

Read `golden-reference/after.tsx` in this action's directory. Every pattern you apply must match what that file demonstrates. Do not invent alternative patterns.

## 1. Classify each changed file

For each file in the changed-files list, assign exactly one action:

| File pattern | Action |
|---|---|
| New form component (`*Application*.tsx`, `*Form*.tsx`) not yet integrated | **INTEGRATE** — full form integration |
| Existing form component with structural changes (fields added/removed/renamed, tabs changed) | **UPDATE** — adjust existing hooks |
| Existing form component with cosmetic-only changes (CSS, text, images) | **SKIP** |
| `src/App.tsx` with route changes | **ROUTE-UPDATE** |
| `src/data/services.ts` or service data files | **SERVICE-UPDATE** |
| Non-form component, asset, or utility | **SKIP** |

## 2. INTEGRATE — new form components

For files classified as INTEGRATE, apply the full per-component algorithm from `initial-integration.md` section 4 (all 11 steps including adversarial review). Specifically:

1. Read and inventory state (Step 1)
2. Map tabs (Step 2)
3. Map sections and gates (Step 3)
4. Map fields per section with `useProgressiveFields` (Step 4)
5. Handle upload-gated fields (Step 5)
6. Handle save-gated sections (Step 6)
7. Register upload-only tabs (Step 7)
8. Register UI actions (Step 8)
9. Register submit action (Step 9)
10. Adversarial review — simulate the LLM (Step 10, all 10 checks)
11. Verify (Step 11)

Import hooks from `@unctad-ai/voice-agent-registries`. Use `useProgressiveFields` exclusively — never individual `useRegisterFormField` calls. Add `useCallback` to the React import if not already present.

## 3. UPDATE — modified form components

For files classified as UPDATE:

1. Read the PR diff for this file to understand what changed
2. Read the current file on the `voice-agent` branch
3. Check each existing hook registration:
   - **Field removed from JSX** — remove from `useProgressiveFields`
   - **Field added to JSX** — add to the correct step in `useProgressiveFields` with proper `id`, `label`, `type`, `bind`
   - **Field renamed** — update `id` and `label` to match new name
   - **Tab added/removed** — update `useRegisterTabSwitchAction` tab list
   - **Section visibility changed** — update `visible:`/`ready:` conditions
   - **State variable renamed** — update all `bind` references
   - **Select options changed** — update the options constant
4. Run adversarial review checks 1-9 from `initial-integration.md` section 4, Step 10
5. If the structural changes are so extensive that patching is error-prone, re-integrate from scratch (treat as INTEGRATE)

## 4. ROUTE-UPDATE — route changes

If `src/App.tsx` routes changed:

1. Read the new routes from `src/App.tsx`
2. Update `src/voice-config.ts`:
   - Add new routes to `routeMap` with human-readable names
   - Remove deleted routes from `routeMap`
   - Update `getServiceFormRoute` if service form paths changed
3. Update `server/voice-config.ts` with the same route changes

## 5. SERVICE-UPDATE — service data changes

If service data files changed:

1. Read the updated service data source
2. Update `src/voice-config.ts`:
   - Ensure `services` import still resolves
   - Update `synonyms` for new/renamed services
   - Update `getServiceFormRoute` for new service IDs
3. Update `server/voice-config.ts`:
   - Update `coreIds` if frequently-accessed services changed
   - Update `extraServerTools` references if service IDs changed

## 6. Rules

1. **Never modify the designer's original code** — only add voice hooks (imports, hook calls, option constants)
2. **Trust the JSX** — field types come from rendered HTML elements, not assumptions
3. **Never fabricate options** — extract only from actual source code
4. **Labels must match UI text exactly** — copy from JSX headings verbatim
5. **All `bind` setters for object state must use `prev =>` pattern** — prevents stale closures
6. **All `useRegisterUIAction` handlers must return strings** — void returns cause false errors
7. **`useProgressiveFields` requires step objects** — never pass flat field arrays

## 7. Verify

After all changes:

```bash
npm run build
```

The build must pass with no type errors. If it fails, fix the issues before proceeding.

## 8. Output

List every file from the changed-files list with its outcome:

```
INTEGRATED: src/components/NewApplication.tsx (15 fields, 3 tabs, 4 actions)
UPDATED: src/components/ExistingForm.tsx (2 fields added, 1 removed)
MODIFIED: src/voice-config.ts (route added: /dashboard/new-form)
MODIFIED: server/voice-config.ts (new service synced)
UNCHANGED: src/components/ServiceCard.tsx (non-form component)
UNCHANGED: src/components/ExistingForm.tsx (cosmetic changes only)
SKIPPED: src/components/BrokenForm.tsx (broken import: ./tabs/MissingTab)
```
