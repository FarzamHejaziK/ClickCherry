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

### Phase 2: Browser Semantic Control Through MCP

Focus:

- add a generic MCP runtime to the app
- expose approved browser MCP tools to the LLM mostly as-is
- connect the first real-session browser backend through Playwright MCP Bridge extension mode

Proposed capabilities:

- MCP server lifecycle:
  - start approved server
  - reconnect / recover
  - discover tools
  - route tool calls
- first approved browser server:
  - Playwright MCP with extension bridge
- first expected browser tool surface:
  - page snapshot
  - click
  - type / fill
  - key press
  - screenshot
  - page evaluation / read helpers as needed

Implementation note:

- the app should host a general MCP client/runtime in Swift
- Playwright MCP should run as an approved external server process
- ClickCherry should not depend on a Playwright-specific browser wrapper contract for LLM usage

Profile/session note:

- the first real-session path should use the user's existing Chrome session through the Playwright MCP Bridge extension
- do not treat the default Chrome data directory as a supported CDP takeover path
- managed/custom profile Playwright can remain a later supplemental mode through the same MCP harness if needed

Real-user-session note:

- when the task depends on the user's real logged-in Chrome profile, the recommended direction is Playwright MCP Bridge through the generic MCP harness
- browser chrome, OS dialogs, and non-DOM surfaces should remain with desktop and future accessibility layers
- if Playwright MCP Bridge proves insufficient, reassess whether a custom extension is needed after the generic MCP harness exists

### Phase 3: Native Accessibility Control

Focus:

- add a macOS semantic surface for native app interaction

This phase depends on the browser-semantic architecture stabilizing first.

## Testing Strategy

Each incremental step should include both automated and manual verification.

### Automated

- unit tests for routing and tool output semantics
- runner tests that assert unverified click responses and required follow-up evidence
- future sidecar contract tests for browser actions
- future AX tests for native semantic actions where feasible

### Manual

- verify app-launch/focus flows no longer rely on Dock pixel clicks
- verify website flows use semantic browser control where available
- verify failed or mislanded clicks no longer immediately report success
- verify ambiguous targets trigger extra inspection instead of overconfident action

## Immediate Next Steps

1. Implement the generic MCP harness in the app:
   - approved server registry
   - lifecycle/process management
   - tool discovery
   - tool invocation routing
2. Integrate Playwright MCP Bridge as the first real-session browser path.
3. Update the execution prompt so browser MCP tools are preferred for webpage DOM work.
4. Keep desktop/native fallback for browser chrome, OS dialogs, and non-DOM surfaces.
5. Revisit managed/custom-profile Playwright mode only after the real-session MCP path is working.
6. Implement `accessibility_action` after the browser-semantic architecture is stable.

## Open Questions

- How should the app present approved MCP server availability and health in product UX?
- Which browser MCP tools should be exposed directly versus filtered out from the allowlist?
- What concrete capability gap would justify a custom extension after Playwright MCP Bridge integration?
