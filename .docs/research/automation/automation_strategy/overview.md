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

- The generic MCP runtime work remains useful infrastructure, but browser v1 does not depend on MCP.
- Phase 2 will not treat the default Chrome profile as a supported CDP relaunch target.
- The first real-session browser integration should use a first-party Chrome extension and a direct app-to-extension bridge.
- The preferred bridge transport for browser v1 is native messaging.
- Browser v1 should use content scripts and standard extension APIs only; do not include `chrome.debugger` in the first release.
- App-owned screenshots remain the default screenshot and visual verification path.
- Managed/custom-profile Playwright remains a parked fallback/research mode, not the main real-session path.
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
