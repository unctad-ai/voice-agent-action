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
