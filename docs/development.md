# Development Guide

## Repository Layout

- `TaskAgentMacOSApp/`: App code, tests, and Xcode project
- `docs/`: Public contributor documentation
- `.docs/`: Internal maintainer planning and implementation logs

## Prompt Files

All production prompts live under:

- `TaskAgentMacOSApp/TaskAgentMacOSApp/Prompts/`

Each prompt folder must include:

- `prompt.md`
- `config.yaml` (`version`, `llm` required)

## Test Commands

Authoritative commands are documented in `/.docs/testing.md`.

## Pull Request Checklist

- Code compiles locally.
- Unit tests pass locally.
- Behavior changes include tests.
- Relevant docs are updated.
- Commits are DCO signed.
