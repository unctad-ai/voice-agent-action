# Initial Voice Agent Integration

You are integrating voice agent support into a Figma Make-generated React project. Follow each section in order.

## 1. Wrap App.tsx

Read `src/App.tsx` and detect which router pattern the project uses:

**Pattern A — `<BrowserRouter>` with `<Routes>` (classic):**
```tsx
import { useState, useCallback, useEffect, lazy, Suspense } from 'react';
import { VoiceAgentProvider, VoiceOnboarding, VoiceA11yAnnouncer } from '@unctad-ai/voice-agent-ui';
import type { OrbState } from '@unctad-ai/voice-agent-core';
import { siteConfig } from './voice-config';

const GlassCopilotPanel = lazy(() =>
  import('@unctad-ai/voice-agent-ui').then(m => ({ default: m.GlassCopilotPanel }))
);

export default function App() {
  const [isVoiceOpen, setIsVoiceOpen] = useState(false);
  const [orbState, setOrbState] = useState<OrbState>('idle');

  // Ctrl+Shift+V keyboard shortcut
  const toggleVoice = useCallback(() => setIsVoiceOpen(prev => !prev), []);
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.ctrlKey && e.shiftKey && e.key === 'V') { e.preventDefault(); toggleVoice(); }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [toggleVoice]);

  return (
    <Router>
      <VoiceAgentProvider config={siteConfig}>
        {/* existing Routes */}
        {!isVoiceOpen && <VoiceOnboarding onTryNow={() => setIsVoiceOpen(true)} />}
        <Suspense fallback={null}>
          <GlassCopilotPanel
            isOpen={isVoiceOpen}
            onOpen={() => setIsVoiceOpen(true)}
            onClose={() => setIsVoiceOpen(false)}
            onStateChange={setOrbState}
          />
        </Suspense>
        <VoiceA11yAnnouncer isOpen={isVoiceOpen} orbState={orbState} />
      </VoiceAgentProvider>
    </Router>
  );
}
```

**Pattern B — `createBrowserRouter` + `<RouterProvider>` (data router):**
You CANNOT wrap children inside `<RouterProvider>`. Instead, find the root layout component (usually referenced in the router config as `element` or `Component` on the top-level route) and wrap its content:
```tsx
// In the root layout component (e.g. RootLayout.tsx or the component used by the "/" route):
import { useState, useCallback, useEffect, lazy, Suspense } from 'react';
import { VoiceAgentProvider, VoiceOnboarding, VoiceA11yAnnouncer } from '@unctad-ai/voice-agent-ui';
import type { OrbState } from '@unctad-ai/voice-agent-core';
import { siteConfig } from './voice-config';

const GlassCopilotPanel = lazy(() =>
  import('@unctad-ai/voice-agent-ui').then(m => ({ default: m.GlassCopilotPanel }))
);

function VoiceLayer() {
  const [isVoiceOpen, setIsVoiceOpen] = useState(false);
  const [orbState, setOrbState] = useState<OrbState>('idle');

  const toggleVoice = useCallback(() => setIsVoiceOpen(prev => !prev), []);
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.ctrlKey && e.shiftKey && e.key === 'V') { e.preventDefault(); toggleVoice(); }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [toggleVoice]);

  return (
    <>
      {!isVoiceOpen && <VoiceOnboarding onTryNow={() => setIsVoiceOpen(true)} />}
      <Suspense fallback={null}>
        <GlassCopilotPanel
          isOpen={isVoiceOpen}
          onOpen={() => setIsVoiceOpen(true)}
          onClose={() => setIsVoiceOpen(false)}
          onStateChange={setOrbState}
        />
      </Suspense>
      <VoiceA11yAnnouncer isOpen={isVoiceOpen} orbState={orbState} />
    </>
  );
}

// Wrap the Outlet:
<VoiceAgentProvider config={siteConfig}>
  <Outlet />
  <VoiceLayer />
</VoiceAgentProvider>
```

If the project uses a single root `<App>` component with `RouterProvider` inside it, wrap the `RouterProvider`:
```tsx
<VoiceAgentProvider config={siteConfig}>
  <RouterProvider router={router} />
  <VoiceLayer />
</VoiceAgentProvider>
```

Do NOT restructure existing routes or layout — only wrap them.

**CRITICAL — Router context:** `GlassCopilotPanel` uses `useNavigate()` internally, which requires Router context. With `RouterProvider`, `VoiceLayer` must be INSIDE the router tree (either as a child of the root layout route, or wrapped around `RouterProvider`). If placed as a sibling outside the router, it crashes. Verify after wrapping: trace from `GlassCopilotPanel` up to the nearest Router/RouterProvider — there must be one in the ancestor chain.

## 2. Enhance the scaffolded `src/voice-config.ts`

> The scaffold has already created this file with a placeholder service and defaults from `.voice-agent.yml`. Replace the placeholder service array with real services extracted from the codebase. Keep the existing config fields (copilotName, colors, farewellMessage, etc.) — only update services, categories, categoryMap, synonyms, routeMap, and getServiceFormRoute.

### 2.1 Find services

Try these sources in order:
1. `src/data/services.ts` or `src/data/services.tsx` — dedicated services file with typed objects
2. `src/data/serviceCategories.ts` — categorized services
3. If neither exists: grep for service arrays in page components (e.g. `Homepage.tsx`, `Dashboard.tsx`). Look for arrays with `title`/`name`/`description`/`link` fields.
4. If no structured services found: create minimal service entries from the routes that look like service pages.

For each service, extract or synthesize: `id` (kebab-case slug), `name`, `description`, `category`.

### 2.2 Find routes

Read `src/App.tsx` and extract all routes:
- Static routes: `/dashboard`, `/about`, etc.
- **Parameterized routes:** `/service/:serviceId`, `/company/:id` → include with parameter notation in routeMap
- Exclude routes listed in `.voice-agent.yml` `exclude_routes`

### 2.3 Read config

Read `.voice-agent.yml` for copilot name, color, domain, description, exclude_routes.

**If `.voice-agent.yml` doesn't exist:** Use these defaults and note in output:
- `copilot_name`: "Assistant"
- `copilot_color`: "#1B5E20"
- `exclude_routes`: []

### 2.4 Generate the file

Generate `src/voice-config.ts` with:
- `services` array matching actual service IDs
- `routeMap` mapping route paths to human-readable names
- `getServiceFormRoute(serviceId)` returning the correct path for each service's form. For services with **external URLs** (linking outside the SPA), return `null` and note in the system prompt that these require browser navigation.
- `copilotName`, `copilotColor`, `description` from config
- `synonyms` for common alternative names

Export as `siteConfig` with the `SiteConfig` type from `@unctad-ai/voice-agent-core`.

**CRITICAL — all required SiteConfig fields must be present.** Missing fields cause runtime crashes (`colors.primary`, `buildSynonymMap(undefined)`, etc.). Required fields:
```typescript
{
  copilotName: string,
  siteTitle: string,
  systemPromptIntro: string,
  services: Service[],
  categories: string[],
  categoryMap: Record<string, string>,
  routeMap: Record<string, string>,
  synonyms: Record<string, string[]>,
  colors: { primary: string, processing: string, speaking: string, glow: string },
  getServiceFormRoute: (id: string) => string | null,
}
```

**Import services from the project's canonical data source** (e.g., `data/services.tsx` or `data/services.ts`) — do NOT hand-copy a sparse subset. The LLM answers from `getServiceDetails` tool results; sparse data causes hallucination.

## 3. Enhance the scaffolded `server/voice-config.ts`

> Same as above — the scaffold created a bootable default. Replace the placeholder service with real services. Additionally add extraServerTools and coreIds based on the project's domain.

Mirror the client config structure. Additionally:
- Add `extraServerTools` if the project has domain-specific tool opportunities (e.g. `recommendServices`, `compareServices`, `searchServices`)
- Use `coreIds` to highlight frequently-accessed services
- All service IDs MUST match actual IDs from the services source identified in Step 2.1
- All required SiteConfig fields from section 2.4 apply here too

Export as `siteConfig`.

## 4. Integrate Form Fields

**Study the golden reference first:** Before touching any form component, read `golden-reference/before.tsx` and `golden-reference/after.tsx` in this action's directory. The after.tsx demonstrates every pattern correctly. Use it as your template.

**API usage:** Use `useProgressiveFields` exclusively (from `@unctad-ai/voice-agent-registries`). NEVER use individual `useRegisterFormField` calls.

### 4.1 Discover form components

Search broadly — do NOT rely only on filename patterns:

1. **Primary:** Files matching `*Application*.tsx` or `*Form*.tsx` in `src/components/`
2. **Secondary:** Grep across all `.tsx` files for:
   - `<form` or `onSubmit` or `handleSubmit`
   - Multiple `useState` with form-like names (firstName, email, phone, etc.)
   - `formData` object state pattern
3. **Exclude:** Components that are purely display/read-only (detail views, dashboards, search results)
4. **Skip non-compiling components:** If a component has broken imports (importing from files/directories that don't exist), flag it in output and skip: `SKIPPED: ComponentName.tsx (broken import: ./tabs/SomeTab does not exist)`

**Nested form components:** When a parent component (e.g. `RegisterCompanyApplication`) wraps a child form (e.g. `RegisterCompanyForm`), treat them as separate components in the algorithm below. Register **guide/wizard fields** (step selection, payment, consent) in the **parent** and **form data fields** in the **child**. Do NOT duplicate field registrations across parent and child.

### 4.2 Per-Component Algorithm

Repeat these steps for EACH form component found in 4.1.

---

#### Step 1: Read and inventory

Read the component file and catalog its state.

> **Large files (> 2000 lines):** Read state declarations first (lines 1-300 typically) to understand the FormData interface, useState vars, and helper functions. Then read JSX sections one at a time. If you cannot fully integrate, flag in output: `PARTIAL: src/components/LargeForm.tsx (3300 lines — integrated N fields, manual review needed for sections X, Y)`

**What to collect:**

- **All `useState` variables.** Categorize each as:
  - *Form data* — values the user types/selects (firstName, email, nationality)
  - *UI state* — tabs, modals, loading, animation flags
  - *File uploads* — file references, uploaded-file state
  - *Flags* — consent, agreement, processing booleans
- **Tab type and state** — e.g. `const [activeTab, setActiveTab] = useState<'form' | 'documents' | 'send'>('form')`
- **Section conditions** — variables that gate visibility (showDirectorForm, showProjectSection, hasUploadedFile)
- **Submit handler** — the function called when the user submits

**What to skip — do NOT register these as form fields:**
- UI toggle/flag state (modals, accordions, loading, animation)
- Collection/array state (expose via UI actions instead)
- Loading/error/processing indicators
- Validation error state
- Uncontrolled inputs (no React state = no bind target)

**Choose a prefix** for this component's IDs: a short kebab-case name (e.g. `pin-reg`, `evaluate-investment`, `phyto`).

**Determine the state binding pattern** used by this component:

Pattern A — Individual `useState` variables (most common):
```typescript
const [firstName, setFirstName] = useState('');
// bind:
bind: [firstName, (v) => setFirstName(v as string)]
```

Pattern B — Object state (e.g. `formData`, `currentDirector`):
```typescript
const [formData, setFormData] = useState({ firstName: '', lastName: '' });
// bind with prev => pattern (REQUIRED to avoid stale closures):
bind: [formData.firstName, (v) => setFormData(prev => ({...prev, firstName: v as string}))]

// WRONG — stale closure:
bind: [formData.firstName, (v) => setFormData({...formData, firstName: v as string})]
```

Pattern C — Object state with updater function:
```typescript
const [formData, setFormData] = useState({...});
const updateFormData = (field: string, value: string) => setFormData(prev => ({...prev, [field]: value}));
// bind:
bind: [formData.firstName, (v) => updateFormData('firstName', v as string)]
```

---

#### Step 2: Map tabs

IF the component has tabs or step/wizard navigation:

```typescript
useRegisterTabSwitchAction(
  'prefix',
  ['form', 'send'] as const,  // must match component's tab type exactly
  (tab) => setActiveTab(tab as TabType),
  'prefix'
);
```

Also works for multi-page/multi-step wizards — use page/section names as tab values.

For **nested tab hierarchies** (parent has outer tabs, child has inner sections): register each tab switch in the component that owns that tab state.

Note which tab each section of fields belongs to — you will need this for `visible:` in Step 3.

---

#### Step 3: Map sections and gates

Walk the JSX and identify each logical section (grouped by headings, `<div>` wrappers, or conditional blocks). For each section, record:

| Property | How to determine |
|---|---|
| **Section name** | From the heading text or grouping label in JSX |
| **`visible:`** | Which tab is it on? e.g. `activeTab === 'form'` |
| **`ready:`** | Is it behind a condition? e.g. `showSection`, `hasUploaded`, `directorsCount > 0` |
| **`gatedAction:`** | Does it need a UI action to reveal? e.g. `'pin-reg.addDirector'` |

**Produce a section inventory** before moving to Step 4:
```
| Section | Tab | visible | ready | gatedAction |
|---------|-----|---------|-------|-------------|
| Director Details | form | activeTab === 'form' | showDirectorForm | pin-reg.addDirector |
| Director Address | form | activeTab === 'form' | showDirectorForm | pin-reg.addDirector |
| Project Info | form | activeTab === 'form' | showProjectSection | — |
| Required Documents | documents | activeTab === 'documents' | — | — |
```
This inventory drives Steps 4–7.

**`ready:` gates — CRITICAL for progressive forms:**
When fields only appear after a user action (upload completes, save clicked, etc.), the step MUST have a `ready:` condition. Without it, `getFormSchema` exposes invisible fields, causing the LLM to skip required navigation steps.

How to identify: look for `{condition && (<div>...fields...</div>)}` in JSX. The condition variable is your `ready:` gate.

**Visibility:** Walk up the JSX tree from each field's element, collect all `{condition && (...)}` gates, AND them together. Include `!isProcessing*` guards. For section-based visibility (e.g. `currentSection === 'applicant'`), use the section condition as the step-level `visible`.

---

#### Step 4: Map fields per section

Assemble the `useProgressiveFields` call. Each step MUST be a `ProgressiveStepConfig` object — **never pass a flat field array:**
```tsx
// CORRECT — array of step objects:
useProgressiveFields('prefix', [
  { step: 'Section Name', visible: activeTab === 'form', ready: condition, fields: [...] },
  { step: 'Other Section', visible: activeTab === 'form', fields: [...] },
]);

// WRONG — flat field array (causes "p.fields is not iterable" crash):
useProgressiveFields('prefix', [
  { id: 'field1', label: '...', type: 'text', bind: [...] },
]);
```

For each field in each section, produce a field definition:

| Property | How to determine |
|---|---|
| **`id:`** | `{prefix}.{section}.{field}` — field is camelCase |
| **`label:`** | COPY from JSX heading/label verbatim. e.g. "Director first name" not "First name", "Project county" not "County" |
| **`type:`** | Check the RENDERED element (see type table below) |
| **`required:`** | Only `true` if label has `<span className="text-red-500">*</span>` or `<input>` has `required` attribute. Default: omit (false) |
| **`options:`** | Only for `select` and `radio` types. Extract from source code |
| **`bind:`** | Match the component's state pattern (A/B/C from Step 1) |

**Field type table — trust the RENDERED element, not assumptions:**

| Rendered Element | Correct `type` | Notes |
|---|---|---|
| `<select>` | `select` with `options` array | Extract options to module-scope constants |
| `<input type="tel">` | `tel` | |
| `<input type="email">` | `email` | |
| `<input type="date">` | `date` | |
| `<input type="text">` | `text` | NEVER add options |
| `<textarea>` | `text` | |
| `<input type="number">` | `text` | `number` not in FormFieldType |
| `<input type="radio">` | `radio` with `options` | |
| `<input type="checkbox">` | `checkbox` | |

**CRITICAL — Custom wrapper components:**
Projects often wrap `<select>` in custom components like `NationalitySelect`, `CountySelect`, `PhoneCodeSelect`, or use custom `Switcher`/`RadioGroup` components. Before assigning a field type:
1. Check if the JSX uses a custom component (not a raw HTML element)
2. Read the custom component's source to determine what it renders internally
3. If it renders `<select>` → type `select`. If it renders radio buttons → type `radio`. If it renders toggle buttons → type `radio`.
4. For custom select components with large option lists (70+ items like nationalities): extract the first 10-15 representative options and add a comment `// Subset — full list in NationalitySelect component`. Do NOT fabricate options not present in the source.

**CRITICAL:** NEVER assign `type: 'select'` unless the rendered element is actually a `<select>`. Many fields that seem like dropdowns are actually `<input type="text">` in Figma Make output.

**CRITICAL:** NEVER fabricate option values. Only extract options from actual `<option>` elements, custom component source arrays, or module-scope constants in the source code.

---

#### Step 5: Handle upload-gated fields

IF a section has an upload field AND text fields that appear only after the upload completes:

Split into two `useProgressiveFields` steps with the SAME step name:
```tsx
// Step A: upload only — ready when section is open
{ step: 'Director Details', visible: activeTab === 'form', ready: showDirectorForm,
  gatedAction: 'pin-reg.addDirector',
  fields: [{ id: 'director.passportUpload', label: 'Upload passport copy', type: 'upload', required: true, bind: [...] }] },
// Step B: text fields — ready only after upload completes
{ step: 'Director Details', visible: activeTab === 'form', ready: showDirectorForm && hasUploadedFile,
  fields: [{ id: 'director.firstName', ... }, ...] },
```

Same step name = fields merge into one schema section. The text fields appear only when their `ready` condition is true.

IF no upload-gated text fields exist in this section, skip this step.

---

#### Step 6: Handle save-gated sections

IF a section appears only after a Save/Add action (look for `{condition && (<div>...fields...</div>)}` where the condition is set by a save/add handler):

Add `ready: conditionVariable` to that step:
```tsx
{ step: 'Project Information', visible: activeTab === 'form', ready: showProjectSection, fields: [...] }
```

IF no save-gated sections exist in this component, skip this step.

---

#### Step 7: Register upload-only tabs

IF a tab has ONLY upload fields (e.g. Documents, Attachments tab), register them all:
```tsx
{ step: 'Required Documents', visible: activeTab === 'documents',
  fields: [
    { id: 'docs.passport', label: 'Passport photo for each shareholder', type: 'upload', required: true, bind: [file ? 'uploaded' : '', () => {}] },
    // ... every upload field on this tab
  ] }
```

Without this, `getFormSchema` returns "no fields visible" on that tab and the LLM loops.

IF no upload-only tabs exist, skip this step.

---

#### Step 8: Register UI actions

For EVERY interactive button in the component that is not a form field, add `useRegisterUIAction`. Common actions:
- Add/remove items in a list (directors, documents, line items)
- Upload/delete files
- Clear/reset form sections
- Toggle sections open/closed
- Query/search operations

**API is positional args** — NOT an object. A handler returning `void` causes a false "action not found" error:
```typescript
// CORRECT — positional args, returns string:
useRegisterUIAction(
  'prefix.actionName',                              // id
  'Human description of what this does',             // description
  useCallback(() => {                                // handler
    doSomething();
    return `Result: what happened. Current state: ${items.length} items.`;
  }, [items.length, doSomething]),  // include every variable referenced inside
  { category: 'prefix' }
);
```
**Common dep array mistake:** omitting state variables or callbacks from the array causes stale closures — the handler runs with old values.

---

#### Step 9: Register submit action

REQUIRED for every form component, even without an explicit submit handler:
```typescript
useRegisterSubmitAction('prefix', {
  description: 'Submit the [form name] application',
  guard: () => {
    if (activeTab !== 'send') return 'Switch to the Send tab first';
    if (!consentChecked) return 'Consent checkbox must be checked';
    // Check other preconditions from the component's validation logic
    return null;
  },
  onSubmit: () => { /* call existing submit handler or navigate */ },
  successMessage: 'Application submitted successfully.',
  category: 'prefix',
});
```

Guard should check real preconditions: required tabs visited, required uploads present, consent checked.

---

#### Step 10: Adversarial review — simulate the LLM

Pretend you are the voice assistant LLM at runtime. Walk through the form tab by tab and check for failure modes discovered in live testing.

**For each tab, ask:**

1. **"What does getFormSchema return right now?"** List the sections and fields that would appear based on your `visible:` and `ready:` conditions with the component in its initial state (nothing filled, no actions taken).
   - If you see fields the user CANNOT see on screen → **FIX:** add `ready:` gate referencing the condition variable from JSX (go back to Step 6)
   - If you see 0 fields on a tab with upload areas → **FIX:** register those upload fields (go back to Step 7)

2. **"After I fill these fields, what happens?"** Simulate fillFormFields → auto getFormSchema refresh.
   - If new sections from a DIFFERENT tab appear → **FIX:** add `ready:` gate tied to the save/navigate action's state variable (Step 6)
   - If 15+ fields appear at once in one section → **FIX:** split the step into smaller logical groups (Step 3/4)

3. **"After all fields are filled, what action do I take?"** Check UI_ACTIONS.
   - If no save/tab-switch action exists to advance → **FIX:** register the button as a `useRegisterUIAction` (Step 8)
   - If the only path forward requires a button click not registered as an action → **FIX:** same — register it (Step 8)

4. **"Can I submit?"** Try calling the submit action.
   - If no submit action is registered → **FIX:** add `useRegisterSubmitAction` (Step 9)
   - If guard returns an error that the LLM cannot resolve via tools → **FIX:** relax the guard or add the missing tool/action that unblocks it

5. **"If I say the field names out loud, can the user find them?"**
   - If a label differs from what the UI shows → **FIX:** replace the label with the exact text from the JSX heading (Step 4)

6. **"Do all bind setters use `prev =>` for object state?"** Check every bind that updates object state (Pattern B/C from Step 1).
   - If any bind uses `setFormData({...formData, field: v})` instead of `setFormData(prev => ({...prev, field: v}))` → **FIX:** rewrite with `prev =>` pattern (Step 1)
   - Without this, consecutive fillFormFields calls overwrite each other (stale closure)

7. **"Does every `gatedAction` ID match a registered action?"** Cross-check all `gatedAction:` strings from Steps 5-6 against `useRegisterUIAction` IDs from Step 8.
   - If an ID has no matching registration → **FIX:** register the action (Step 8), or fix the typo in the gatedAction string

8. **"Is useProgressiveFields called with step objects, not flat fields?"** Check the call passes `[{step, visible, fields}, ...]` not `[{id, label, type, bind}, ...]`.
   - If flat field arrays are passed → **FIX:** wrap in `{ step: 'Name', visible: condition, fields: [...] }` (Step 4)
   - Flat arrays cause "p.fields is not iterable" runtime crash

9. **"Do all useRegisterUIAction calls use positional args and return strings?"** Check every handler.
   - If handler returns `void`/`undefined` → **FIX:** add a `return 'Result...'` statement (Step 8)
   - If called with object syntax `({id, description, handler})` instead of positional `(id, description, handler, options)` → **FIX:** convert to positional (Step 8)

**If any check fails, fix it and re-run this step from check 1.** Do not proceed to Step 11 until all 9 checks pass. If after 3 rounds of fixes any check still fails, flag the component as `PARTIAL` and move on.

**Quick reference — failure → fix:**
| Failure | Root cause | Fix step |
|---------|-----------|----------|
| Invisible fields in schema | Missing `ready:` gate | Step 5 or 6 |
| Empty tab in schema | Upload fields not registered | Step 7 |
| No action to advance | Button not registered as UI action | Step 8 |
| Submit not found | `useRegisterSubmitAction` missing | Step 9 |
| User cannot find field | Label doesn't match UI text | Step 4 |
| LLM dumps all fields | Step too large (15+ fields) | Step 3/4 |
| LLM offers manual entry | Upload + text in same step | Step 5 |
| Consecutive fills overwrite fields | Missing `prev =>` in object state bind | Step 1 |
| Gated section cannot be unlocked | gatedAction ID doesn't match registered action | Step 8 |
| "p.fields is not iterable" crash | Flat field array instead of step objects | Step 4 |
| "Action not found" false error | Handler returns void or wrong call signature | Step 8 |
| Runtime crash on config access | Missing required SiteConfig fields | Section 2.4 |

#### Step 11: Verify

Before moving to the next component:

- [ ] Labels match UI text exactly (copy-pasted from JSX, not paraphrased)
- [ ] All field IDs reference real state variables in the component
- [ ] All `gatedAction` IDs match a registered `useRegisterUIAction`
- [ ] All `visible:` / `ready:` conditions use real variables from the component
- [ ] No fabricated option values — all extracted from source
- [ ] Adversarial review (Step 10) passed — no invisible fields, no missing actions
- [ ] Build passes: `npm run build` (or `npx vite build`)

## 5. Validation

After generating all files, verify:
1. Every service ID in voice-config exists in the services source
2. Every route target in `routeMap` matches an actual route in `App.tsx`
3. Every form field ID references a real state variable
4. No broken imports (all imported components/modules exist)
5. Build passes: `npm run build` (or `npx vite build`)

## 6. Output

List all files created or modified:
```
CREATED: src/voice-config.ts
CREATED: server/voice-config.ts
MODIFIED: src/App.tsx (or src/RootLayout.tsx for RouterProvider pattern)
MODIFIED: src/components/SomeApplication.tsx
MODIFIED: package.json (voice-agent deps added by scaffold)
SKIPPED: src/components/BrokenForm.tsx (broken import: ./tabs/SomeTab)
PARTIAL: src/components/HugeForm.tsx (3300 lines — 45 fields integrated, sections 5-7 need review)
NOTE: .voice-agent.yml not found — used defaults
```

This list will be used for manifest tracking.
