# Voice Agent Action

GitHub Action that integrates voice-agent-kit into Figma Make projects via Claude Code.

## How It Works

1. Figma designer pushes to `main` in a country project (e.g. Swkenya)
2. Action detects initial vs incremental mode
3. Scaffolds server/client templates from `.voice-agent.yml` config
4. Pipes `prompts/context.md` + `prompts/{initial-integration|incremental-update}.md` to Claude Code `--print`
5. Claude Code wires voice hooks into the project
6. Result pushed to `voice-agent` branch → Coolify auto-deploys

## Prompt Architecture

- `prompts/context.md` — System prompt contract. Explains the voice-agent-kit runtime rules and why each hook pattern exists. Prepended to every CI run.
- `prompts/initial-integration.md` — First-time setup: wrap App.tsx, generate voice-config, wire form hooks.
- `prompts/incremental-update.md` — Designer updated main: detect what changed, update only affected files.
- `golden-reference/` — before/after examples of correct hook integration.

## Key Files

- `action.yml` — Composite action orchestration
- `templates/server/index.ts` — Server entrypoint template
- `scripts/` — scaffold.sh, detect-changes.sh, save-ignored.sh, restore-ignored.sh, verify.sh

## Critical Integration Patterns (learned from live testing)

These patterns are not obvious from the API alone. Each was discovered through voice testing with real users and Qwen3-32B.

### 1. `ready:` Gates on useProgressiveFields Steps

When fields only become visible after a user action (upload, save, etc.), the step MUST have a `ready:` condition. Without it, `getFormSchema` returns fields the user cannot see, causing the LLM to ask about invisible fields or offer non-existent actions.

**Upload-gated text fields:**
```tsx
// Step 1: Upload only — always ready when director form is open
{ step: 'Director Details', visible: activeTab === 'form', ready: showDirectorForm,
  gatedAction: 'pin-reg.addDirector',
  fields: [
    { id: 'director.passportUpload', label: 'Upload passport copy', type: 'upload', required: true, bind: [...] },
  ] },
// Step 2: Text fields — only ready AFTER passport is uploaded
{ step: 'Director Details', visible: activeTab === 'form', ready: showDirectorForm && hasUploadedFile,
  fields: [
    { id: 'director.firstName', label: 'Director first name', ... },
    // ... remaining auto-filled fields
  ] },
```

Same step name is intentional — fields merge into one "Director Details" section in the schema. The text fields only appear after `hasUploadedFile` becomes true.

**Save-gated sections:**
```tsx
// Project sections only appear after director is saved (handleSaveDirector sets flag)
{ step: 'Project Reference', visible: activeTab === 'form', ready: showProjectReferenceSection,
  fields: [...] },
{ step: 'Project Information', visible: activeTab === 'form', ready: showProjectReferenceSection,
  fields: [...] },
```

**How to identify:** Look for conditional rendering in JSX — `{showSection && (<div>...fields...</div>)}`. The condition variable is your `ready:` gate.

### 2. Upload-Only Tabs Must Be Registered

Tabs that contain only upload fields (e.g., a "Documents" tab with 10 upload areas) MUST have those fields registered in `useProgressiveFields`. Without registration, `getFormSchema` returns "No form fields are visible" when the LLM navigates to that tab, causing it to loop on other actions (like submit).

```tsx
{ step: 'Required Documents', visible: activeTab === 'documents',
  fields: [
    { id: 'docs.passportShareholder', label: 'Passport photo for each shareholder', type: 'upload', required: true, bind: [file ? 'uploaded' : '', () => {}] },
    // ... all other upload fields on this tab
  ] },
```

### 3. Field Labels Must Match UI Text Exactly

The LLM reads the `label` from the schema and speaks it to the user. If the label says "Signed statement of nominal capital" but the screen shows "Upload signed Capital Statement", the user cannot find the field.

**Rule:** Copy labels verbatim from the JSX heading/label text. Do not paraphrase, reorder, or simplify.

### 4. useRegisterSubmitAction Is Required

Every form component MUST have `useRegisterSubmitAction` wired — not just imported. Without it, the LLM tries to fabricate a submit action ID, gets "Action not found", and tells the user to click manually.

The guard function should check real preconditions:
```tsx
useRegisterSubmitAction('prefix', {
  description: 'Submit the [form name] application',
  guard: () => {
    if (!file1 || !file2 || !file3) return 'All signed documents must be uploaded before submitting.';
    return null;
  },
  onSubmit: () => handleSubmit(),
  successMessage: 'Application submitted successfully.',
  category: 'prefix',
});
```

### 5. Tab Switch Actions Need Correct Params

`useRegisterTabSwitchAction` registers a `performUIAction` that requires a `paramsJson` with the target tab name. The action description includes the tab sequence — the LLM reads this to know which tab to switch to.

Tab names must match the component's type/union exactly. If the type is `'guide' | 'form' | 'documents' | 'send'`, those exact strings must appear in the registration.

### 6. What NOT to Do

- **Don't register 30+ fields in a single step** — the LLM asks for "a few at a time" (2-sentence limit), so a flat 30-field step makes it dump everything
- **Don't put text fields before their gating upload** — if passport OCR auto-fills name/DOB, the upload must come first
- **Don't offer manual entry when upload is the only path** — if text fields are gated behind `ready: hasUploadedFile`, the upload is mandatory, not optional
- **Don't use labels that differ from UI text** — the LLM speaks them verbatim to the user
- **Don't leave submit action unregistered** — the LLM will fabricate an action ID and fail
