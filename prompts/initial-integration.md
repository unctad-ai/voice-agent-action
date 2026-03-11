# Initial Voice Agent Integration

You are integrating voice agent support into a Figma Make-generated React project. Follow each section in order.

## 1. Wrap App.tsx

Find the Router component in `src/App.tsx`. Wrap its children with voice agent providers:

```tsx
import { VoiceAgentProvider } from '@unctad-ai/voice-agent-core';
import { GlassCopilotPanel } from '@unctad-ai/voice-agent-ui';
import { siteConfig } from './voice-config';

// Inside the Router component, wrap existing content:
<VoiceAgentProvider config={siteConfig}>
  {/* existing routes */}
  <GlassCopilotPanel />
</VoiceAgentProvider>
```

Do NOT restructure the existing routes or layout — only wrap them.

## 2. Generate `src/voice-config.ts`

Read these files:
- `src/data/services.ts` — extract all services (id, name, description, category)
- `src/App.tsx` — extract all routes (path → component name)
- `.voice-agent.yml` — copilot name, color, domain, description, exclude_routes

Generate `src/voice-config.ts` with:
- `services` array matching actual service IDs from services.ts
- `routeMap` mapping route paths to human-readable names (exclude routes listed in `.voice-agent.yml` `exclude_routes`)
- `getServiceFormRoute(serviceId)` returning the correct path for each service's form
- `copilotName`, `copilotColor`, `description` from `.voice-agent.yml`
- `synonyms` for common alternative names

Export as `siteConfig` with the `SiteConfig` type from `@unctad-ai/voice-agent-core`.

## 3. Generate `server/voice-config.ts`

Mirror the client config structure. Additionally:
- Add `extraServerTools` if the project has domain-specific tool opportunities (e.g. `recommendServices`, `compareServices`, `searchServices`)
- Use `coreIds` to highlight frequently-accessed services
- All service IDs MUST match actual IDs from `src/data/services.ts`

Export as `siteConfig`.

## 4. Integrate Form Fields

For each form component (files matching `*Application*.tsx` or `*Form*.tsx` in `src/components/`), add voice agent hooks.

### Rules (MUST follow exactly)

**Study the golden reference first:** Read `golden-reference/before.tsx` and `golden-reference/after.tsx` in this action's directory. The after.tsx demonstrates every pattern correctly.

**API usage:**
- Use `useProgressiveFields` exclusively (from `@unctad-ai/voice-agent-registries`)
- NEVER use individual `useRegisterFormField` calls

**ID convention:** `{prefix}.{section}.{field}`
- prefix = short component name (e.g. `pin-reg`, `evaluate-investment`, `phyto`)
- section = logical grouping (e.g. `project`, `director`, `applicant`)
- field = camelCase field name

**Labels:** Domain-prefixed to avoid ambiguity:
- "Director first name" (not "First name")
- "Project county" (not "County")
- "Applicant email" (not "Email")

**Field types — trust the JSX, not assumptions:**

| JSX Element | Correct `type` | Notes |
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

**CRITICAL:** NEVER assign `type: 'select'` unless the JSX renders a `<select>` element. Many fields that look like they could be dropdowns (county, sector, nationality) are actually `<input type="text">` in Figma Make output. Trust the JSX.

**CRITICAL:** NEVER fabricate option values. Only extract options from actual `<option>` elements in the JSX.

**State binding patterns — two forms exist in Figma Make projects:**

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

Both patterns are valid. Read the component's state declarations to determine which pattern applies.

**Visibility:** Walk up the JSX tree from each field's element, collect all `{condition && (...)}` gates, AND them together. Include `!isProcessing*` guards.

**Required flags:** Only set `required: true` if the label has `<span className="text-red-500">*</span>` or equivalent marker. Default to omitting (false).

**Skip — do NOT register these as form fields:**
- UI toggle/flag state (modals, accordions, loading, animation)
- Collection/array state (use UI actions instead)
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
Also works for multi-page/multi-step wizards — use page names as tab values.

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

**Large files (> 2000 lines):** Do NOT skip entirely. Instead:
1. Read the file in chunks (first 1000 lines, then next 1000, etc.)
2. Integrate what you can (imports, useProgressiveFields, UI actions)
3. Flag in output: `PARTIAL: src/components/LargeForm.tsx (2885 lines — integrated fields from lines 1-1500, manual review needed for remainder)`

## 5. Validation

After generating all files, verify:
1. Every service ID in voice-config exists in `src/data/services.ts`
2. Every route target in `routeMap` matches an actual route in `App.tsx`
3. Every form field ID references a real `useState` variable
4. Build passes: `npm run build` (or `npx vite build`)

## 6. Output

List all files created or modified:
```
CREATED: src/voice-config.ts
CREATED: server/voice-config.ts
MODIFIED: src/App.tsx
MODIFIED: src/components/SomeApplication.tsx
MODIFIED: package.json (voice-agent deps added by scaffold)
```

This list will be used for manifest tracking.
