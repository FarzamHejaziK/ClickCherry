# Automation Plan

## Goal

Improve execution reliability by routing tasks to the most semantic control surface available instead of defaulting to mouse-based visual clicking.

## Desired Architecture

ClickCherry should evolve toward three action layers:

1. Browser-semantic MCP tools
   - for webpage content in Chrome and other supported browsers
   - exposed through a generic app-owned MCP harness
   - first approved browser server:
     - Playwright MCP in extension mode for the user's real Chrome session
   - optional later browser server:
     - Playwright MCP in managed/custom-profile mode

2. `accessibility_action`
   - for native macOS UI
   - backed by macOS Accessibility APIs

3. `desktop_action`
   - for visual fallback only
   - used when semantic targeting is unavailable or untrustworthy

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

## Phase Plan

## Phase 1: Reliability Hardening In Current Runner

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

## Phase 2: Browser Semantic Control Through MCP

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

## Phase 3: Native Accessibility Control

Focus:

- add a macOS semantic surface for native app interaction

Proposed capabilities:

- `press`
- `set_value`
- `focus_window`
- `select_menu_item`
- `read_focused_element`
- `find_element`

Implementation note:

- use AXUIElement-based APIs in native Swift
- prefer accessibility over pixel clicks for dialogs, menus, buttons, and standard controls
- explicitly keep deeper/custom AX surfaces and browser chrome support out of the first accessibility release

## Planner Routing Policy

This routing policy is cross-cutting and applies as the three phases come online:

1. approved browser MCP tools
2. accessibility action
3. deterministic shortcut or app/URL action
4. visual desktop action

Within the browser-semantic layer, the planner should now assume:

1. real user Chrome session required:
   - use Playwright MCP Bridge through the generic MCP harness
2. managed/custom browser mode explicitly requested or later enabled:
   - use managed Playwright MCP mode
3. browser chrome / OS / non-DOM:
   - use accessibility, deterministic actions, or desktop fallback

Policy examples:

- "open Chrome" -> `open_app`
- "click Login on LinkedIn" -> browser semantic action
- "choose File > Export in a native app" -> accessibility action or shortcut
- "click a node in a canvas" -> visual action

## Tooling Recommendations

## Browser Layer

Recommended approach:

- Swift-hosted generic MCP runtime
- approved MCP server registry / allowlist
- Playwright MCP as the first browser server
- Playwright MCP Bridge as the first real-session browser integration

Why:

- keeps the app extensible beyond one browser server
- reduces adaptation work when Playwright MCP evolves
- lets prompt policy guide tool use without a heavy Playwright-specific facade
- avoids fighting Chrome's default-profile remote debugging restrictions when real user-session automation is required

Extension recommendation:

- use Playwright MCP Bridge first as the off-the-shelf real-session extension path
- only consider a custom extension after the generic MCP harness is in place and a concrete capability gap is proven

## Accessibility Layer

Recommended approach:

- native Swift implementation over macOS Accessibility APIs

Why:

- best integration with current app
- no extra runtime dependency for native app semantics

## Testing Strategy

Each incremental step should include both automated and manual verification.

## Automated

- unit tests for routing and tool output semantics
- runner tests that assert unverified click responses and required follow-up evidence
- future sidecar contract tests for browser actions
- future AX tests for native semantic actions where feasible

## Manual

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
