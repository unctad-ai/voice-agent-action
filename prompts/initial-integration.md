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

**Object state with `prev =>` pattern:**
```typescript
// CORRECT
bind: [currentDirector.firstName, (v) => setCurrentDirector(prev => ({...prev, firstName: v as string}))]

// WRONG — stale closure
bind: [currentDirector.firstName, (v) => setCurrentDirector({...currentDirector, firstName: v as string})]
```

**Visibility:** Walk up the JSX tree from each field's element, collect all `{condition && (...)}` gates, AND them together. Include `!isProcessing*` guards.

**Required flags:** Only set `required: true` if the label has `<span className="text-red-500">*</span>` or equivalent marker. Default to omitting (false).

**Skip — do NOT register these as form fields:**
- UI toggle/flag state (modals, accordions, loading, animation)
- Collection/array state (use UI actions instead)
- Loading/error/processing indicators
- Validation error state
- Uncontrolled inputs (no React state = no bind target)

**UI actions:** Add `useRegisterUIAction` for button actions (add/remove items, uploads). Handler MUST return a descriptive string.

**Tab switch:** Add `useRegisterTabSwitchAction` for tab navigation with typed tab array.

**Submit:** Add `useRegisterSubmitAction` with guard function checking preconditions.

**Large files:** Skip components > 2000 lines. Flag them in output for manual review.

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
