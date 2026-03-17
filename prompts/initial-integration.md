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

## 3. Enhance the scaffolded `server/voice-config.ts`

> Same as above — the scaffold created a bootable default. Replace the placeholder service with real services. Additionally add extraServerTools and coreIds based on the project's domain.

Mirror the client config structure. Additionally:
- Add `extraServerTools` if the project has domain-specific tool opportunities (e.g. `recommendServices`, `compareServices`, `searchServices`)
- Use `coreIds` to highlight frequently-accessed services
- All service IDs MUST match actual IDs from the services source identified in Step 2.1

Export as `siteConfig`.

## 4. Integrate Form Fields

### 4.1 Discover form components

Search broadly — do NOT rely only on filename patterns:

1. **Primary:** Files matching `*Application*.tsx` or `*Form*.tsx` in `src/components/`
2. **Secondary:** Grep across all `.tsx` files for:
   - `<form` or `onSubmit` or `handleSubmit`
   - Multiple `useState` with form-like names (firstName, email, phone, etc.)
   - `formData` object state pattern
3. **Exclude:** Components that are purely display/read-only (detail views, dashboards, search results)
4. **Skip non-compiling components:** If a component has broken imports (importing from files/directories that don't exist), flag it in output and skip: `SKIPPED: ComponentName.tsx (broken import: ./tabs/SomeTab does not exist)`

### 4.2 Handle nested form components

When a parent component (e.g. `RegisterCompanyApplication`) wraps a child form (e.g. `RegisterCompanyForm`):
- Register **guide/wizard fields** (step selection, payment, consent) in the **parent**
- Register **form data fields** in the **child**
- Do NOT duplicate field registrations across parent and child
- Register `useRegisterTabSwitchAction` in whichever component owns the tab state

### 4.3 Rules (MUST follow exactly)

**Study the golden reference first:** Read `golden-reference/before.tsx` and `golden-reference/after.tsx` in this action's directory. The after.tsx demonstrates every pattern correctly.

**API usage:**
- Use `useProgressiveFields` exclusively (from `@unctad-ai/voice-agent-registries`)
- NEVER use individual `useRegisterFormField` calls

**ID convention:** `{prefix}.{section}.{field}`
- prefix = short component name (e.g. `pin-reg`, `evaluate-investment`, `phyto`)
- section = logical grouping (e.g. `project`, `director`, `applicant`)
- field = camelCase field name

**Labels:** Must match the UI text the user sees exactly. Copy from JSX headings/labels verbatim:
- "Upload signed Capital Statement" (not "Signed statement of nominal capital")
- "Director first name" (not "First name")
- "Project county" (not "County")

**`ready:` gates — CRITICAL for progressive forms:**

When fields only appear after a user action (upload completes, save clicked, etc.), the step MUST have a `ready:` condition. Without it, `getFormSchema` exposes invisible fields, causing the LLM to skip required navigation steps.

Two-step split pattern for upload-gated text fields:
```tsx
// Upload field — always ready when section is open
{ step: 'Director Details', visible: activeTab === 'form', ready: showDirectorForm,
  gatedAction: 'pin-reg.addDirector',
  fields: [{ id: 'director.passportUpload', label: 'Upload passport copy', type: 'upload', required: true, bind: [...] }] },
// Text fields — only ready after upload completes
{ step: 'Director Details', visible: activeTab === 'form', ready: showDirectorForm && hasUploadedFile,
  fields: [{ id: 'director.firstName', ... }, ...] },
```

Same step name = fields merge into one schema section. Text fields appear only when `ready` is true.

For save-gated sections (e.g., project fields appear after director is saved):
```tsx
{ step: 'Project Information', visible: activeTab === 'form', ready: showProjectSection, fields: [...] }
```

How to identify: look for `{condition && (<div>...fields...</div>)}` in JSX. The condition variable is your `ready:` gate.

**Upload-only tabs must be registered.** If a tab (Documents, Attachments) has only upload fields, register them all:
```tsx
{ step: 'Required Documents', visible: activeTab === 'documents',
  fields: [
    { id: 'docs.passport', label: 'Passport photo for each shareholder', type: 'upload', required: true, bind: [file ? 'uploaded' : '', () => {}] },
    // ... every upload field on this tab
  ] }
```

Without this, `getFormSchema` returns "no fields visible" on that tab and the LLM loops.

**Field types — trust the RENDERED element, not assumptions:**

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

**State binding patterns — three forms exist in Figma Make projects:**

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

Read the component's state declarations to determine which pattern applies.

**Visibility:** Walk up the JSX tree from each field's element, collect all `{condition && (...)}` gates, AND them together. Include `!isProcessing*` guards. For section-based visibility (e.g. `currentSection === 'applicant'`), use the section condition as the step-level `visible`.

**Required flags:** Only set `required: true` if the label has `<span className="text-red-500">*</span>` or equivalent marker, or the `<input>` has a `required` attribute. Default to omitting (false).

**Skip — do NOT register these as form fields:**
- UI toggle/flag state (modals, accordions, loading, animation)
- Collection/array state (expose via UI actions instead)
- Loading/error/processing indicators
- Validation error state
- Uncontrolled inputs (no React state = no bind target)

**UI actions (REQUIRED for every form component):**
Add `useRegisterUIAction` for ALL interactive button actions — not just add/remove. Common actions:
- Add/remove items in a list (directors, documents, line items)
- Upload/delete files
- Clear/reset form sections
- Toggle sections open/closed
- Query/search operations

Handler MUST return a descriptive string:
```typescript
useRegisterUIAction(
  'prefix.actionName',
  'Human description of what this does',
  useCallback(() => {
    doSomething();
    return `Result: what happened. Current state: ${items.length} items.`;
  }, [items.length]),
  { category: 'prefix' }
);
```

**Tab/step switch (REQUIRED if component has tabs or step navigation):**
```typescript
useRegisterTabSwitchAction(
  'prefix',
  ['form', 'send'] as const,  // must match component's tab type
  (tab) => setActiveTab(tab as TabType),
  'prefix'
);
```
Also works for multi-page/multi-step wizards — use page/section names as tab values.

For **nested tab hierarchies** (parent has outer tabs, child has inner sections): register each tab switch in the component that owns that tab state.

**Submit action (REQUIRED for every form component):**
Even if the component doesn't have an explicit submit handler, add one. If the component has a "Submit" or "Send" button, hook it. If it only has navigation to next page, make the guard check required fields:
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

**Large files (> 2000 lines):**
1. Read state declarations first (lines 1-300 typically): understand FormData interface, useState vars, helper functions
2. Read JSX sections one at a time to map fields to their rendered elements
3. Integrate what you can (imports, useProgressiveFields, UI actions)
4. Flag in output: `PARTIAL: src/components/LargeForm.tsx (3300 lines — integrated N fields, manual review needed for sections X, Y)`

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
