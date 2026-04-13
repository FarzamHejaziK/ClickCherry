---
description: Implementation sequencing and validation plan for ClickCherry automation strategy.
---

# Automation Strategy Implementation Plan

## Phase Plan

### Phase 1: Reliability Hardening In Current Runner

Focus:

- update the execution prompt to prefer semantic actions and deterministic app actions
- change visual click semantics from "done" to "unverified until evidence confirms outcome"
- require post-action evidence before the model may return `SUCCESS`
- force crop/zoom/grid when the target is tiny, adjacent, icon-only, or ambiguous

Deliverables:

- prompt update for semantic-first routing
- click result payload update
- tests covering verification-gated click handling

Why first:

- lowest-risk change
- immediate improvement without introducing new external runtime dependencies

### Phase 2: Browser Semantic Control Through A First-Party Extension

Focus:

- build a first-party Chrome extension for real-session browser control
- connect the app to the extension through native messaging
- expose a narrow DOM-focused browser action surface for webpage work

Proposed capabilities:

- pairing and reconnect:
  - connect Chrome
  - trust a specific browser profile
  - reconnect automatically after first approval
- first expected browser tool surface:
  - page snapshot / DOM reads
  - click
  - type / fill
  - key press
  - scroll
  - wait-for element/text
  - URL/title reads

Implementation note:

- the app should own the bridge lifecycle directly for v1
- browser v1 should not depend on Playwright MCP Bridge startup or token pairing
- screenshots should remain app-owned in this phase
- browser v1 should not depend on `chrome.debugger`

Profile/session note:

- the first real-session path should use the user's existing Chrome session through the ClickCherry extension
- do not treat the default Chrome data directory as a supported CDP takeover path
- managed/custom profile Playwright can remain a later supplemental mode if needed

Real-user-session note:

- when the task depends on the user's real logged-in Chrome profile, the recommended direction is the first-party extension bridge
- browser chrome, OS dialogs, and non-DOM surfaces should remain with desktop and future accessibility layers
- if the initial direct bridge later needs broader tool-host reuse, reassess whether an MCP adapter is valuable after the first-party extension is stable

### Phase 3: Native Accessibility Control

Focus:

- add a macOS semantic surface for native app interaction

This phase depends on the browser-semantic architecture stabilizing first.

## Testing Strategy

Each incremental step should include both automated and manual verification.

### Automated

- unit tests for routing and tool output semantics
- runner tests that assert unverified click responses and required follow-up evidence
- future extension bridge contract tests for browser actions
- future AX tests for native semantic actions where feasible

### Manual

- verify app-launch/focus flows no longer rely on Dock pixel clicks
- verify website flows use semantic browser control where available
- verify failed or mislanded clicks no longer immediately report success
- verify ambiguous targets trigger extra inspection instead of overconfident action

## Immediate Next Steps

1. Preserve the reusable generic MCP pieces already explored in the app, but take Playwright MCP Bridge off the critical path for browser v1.
2. Define the first-party extension/app bridge protocol and pairing flow.
3. Implement the MV3 extension skeleton and native messaging host.
4. Update the execution prompt so browser extension tools are preferred for webpage DOM work.
5. Keep desktop/native fallback for browser chrome, OS dialogs, and non-DOM surfaces.
6. Revisit managed/custom-profile Playwright mode only after the real-session extension path is working.
7. Implement `accessibility_action` after the browser-semantic architecture is stable.

## Open Questions

- What exact browser action schema should the app expose to the run agent for the first DOM-focused slice?
- How should connected Chrome profiles be represented in product UX after pairing?
- What concrete workflow gap would justify adding `chrome.debugger` after the DOM-only release?
