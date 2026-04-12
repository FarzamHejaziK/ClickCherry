---
description: High-level overview of ClickCherry's automation strategy direction.
---

# Automation Strategy Overview

## Purpose

This doc captures the high-level automation strategy for ClickCherry.

It is the starting point for understanding:

- the product direction for semantic automation
- the core browser/native/Desktop layering model
- the locked strategic decisions behind the current implementation plan

## Scope

- semantic browser automation direction
- generic MCP harness strategy
- real-session browser path decisions
- phased implementation direction

## Goal

Improve execution reliability by routing tasks to the most semantic control surface available instead of defaulting to mouse-based visual clicking.

## Locked Decisions

- Phase 2 should be implemented as a generic MCP harness in the app rather than a Playwright-specific wrapper layer.
- The app should maintain an allowlist of approved MCP servers and tools.
- Tool-usage policy should live primarily in the execution prompt, not in a bespoke browser abstraction.
- Phase 2 will not treat the default Chrome profile as a supported CDP relaunch target.
- The first real-session browser integration should use Playwright MCP Bridge extension mode through the generic MCP harness.
- Managed/custom-profile Playwright remains an optional later browser mode, not the main real-session path.
- Phase 3 starts with standard controls first:
  - buttons
  - text fields
  - checkboxes and radio buttons
  - dialogs and sheets
  - menu items
  - window focus
- Phase 3 must remain extensible so later iterations can add:
  - deeper/custom AX trees in more complex apps
  - browser chrome surfaces such as tab strip, toolbar, and omnibox

## Related Docs

- Architecture details: `./architecture.md`
- Implementation sequencing: `./implementation_plan.md`
- Browser-extension-specific V1 plan: `./browser_extension_v1.md`
