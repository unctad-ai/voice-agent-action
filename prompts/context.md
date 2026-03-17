# System Prompt Contract

The voice-agent-kit system prompt governs how the LLM assistant behaves at runtime. Every hook you wire exists to support a specific runtime rule. Understanding these rules prevents you from wiring hooks that fight the system prompt.

## Runtime Rules → Hook Mapping

| System Prompt Rule | Runtime behavior | What you must wire |
|---|---|---|
| **FORMS 1**: Always call getFormSchema before filling | LLM reads field metadata before acting | `useProgressiveFields` with correct field IDs, types, labels, and `bind` — these become the schema the LLM reads |
| **FORMS 2**: Ask for a few fields at a time | LLM reveals fields progressively, not all at once | Group fields into logical `steps` with `visible`/`ready` gates — never dump all fields in one flat array |
| **FORMS 3**: After every fill, call getFormSchema again | LLM checks updated state after each action | `bind` must use `prev =>` pattern for object state to avoid stale closures — the re-read must see current values |
| **FORMS 4**: Gated sections need performUIAction | LLM calls an action to reveal hidden fields | Set `gatedAction: 'prefix.actionName'` on steps, and register matching `useRegisterUIAction` that reveals them |
| **FORMS 5**: Tab switches need tab param | LLM navigates tabs by calling performUIAction | `useRegisterTabSwitchAction` with exact tab names matching the component's tab type |
| **FORMS 6**: Handle uploads before text fields | Upload may auto-fill text fields (OCR, parsing) | Split into two steps with same name: upload-only step (ready when section is visible), text fields step with `ready: sectionVisible && hasUploadedFile`. Do NOT put both in one step — text fields must not appear in schema until upload completes |
| **FORMS 7**: Never say form is complete without verifying | LLM calls getFormSchema to confirm all required fields filled | Mark truly required fields with `required: true` — the LLM uses this to judge completeness |
| **PAGE TYPES** (separate rule, not part of FORMS) | /service/:id = info, /dashboard/* = forms | Only wire form hooks on /dashboard/* components. Service pages are read-only |

## Key Constraints

- **Progressive disclosure is mandatory.** The LLM asks for "a few fields at a time" — if you put 30 fields in one step with no gating, the LLM will try to ask all 30 at once, violating its 2-sentence/40-word response limit.
- **Upload-before-text ordering matters.** If a passport upload auto-fills name/nationality, putting text fields first means the LLM asks for data that will be overwritten. Split into two steps with the same step name: upload-only step (always ready) and text fields step with `ready: hasUploadedFile`.
- **Use `ready:` gates for post-action sections.** If a section only appears after a Save/Add action (e.g., project fields appear after saving a director), use `ready: stateVariable` on that step. Without it, `getFormSchema` returns fields the user cannot see yet, causing the LLM to skip navigation steps.
- **Register ALL upload fields, even upload-only tabs.** If a tab has only upload fields and none are registered, `getFormSchema` returns "No form fields visible" and the LLM loops trying other actions.
- **Field labels must match UI text exactly.** The LLM speaks labels to the user. "Signed statement of nominal capital" ≠ "Upload signed Capital Statement" — copy from JSX headings verbatim.
- **UI action handlers must return strings.** The LLM reads the return value to know what happened. A handler returning `undefined` leaves the LLM blind.
- **gatedAction must match a registered action ID exactly.** If the IDs don't match, the LLM sees "gated: true" with no way to unlock.
- **Tab names in useRegisterTabSwitchAction must match the component's type.** The LLM passes these as params — a mismatch means tab switch silently fails.

## What the LLM Sees at Runtime

```
You are {copilotName}, a friendly voice assistant for {siteTitle}. {systemPromptIntro}

RULES: [6 numbered rules — brevity, no lists, no narration, no internal leaks, no fabrication, expand currencies]
TONE: [warm human, varied openers]
SPEECH RECOGNITION: [phonetic charity for STT errors]
FORMS: [7 numbered rules — the ones mapped above]
SILENT / GOODBYE: [edge behaviors]

Current page: /dashboard/pin-registration
Active form tab: form
UI_ACTIONS available on this page: [{id, description, category, params}]
Form: 12 fields in 3 sections. Call getFormSchema before fillFormFields.
```

The dynamic context is built from `clientState`. The fields, actions, and tabs you wire are what populate `UI_ACTIONS` and `Form` at runtime.
