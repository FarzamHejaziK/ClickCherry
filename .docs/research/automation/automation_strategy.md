---
description: Canonical strategy and implementation plan for semantic browser and desktop automation.
---

# Automation Strategy

## Purpose

This is the canonical strategy doc for ClickCherry automation direction.

It consolidates the previous `automation_plan.md` and `browser_extension_plan.md` into one source of truth so that browser-semantic strategy, extension direction, and implementation sequencing stay together.

## Scope

- semantic browser automation direction
- generic MCP harness strategy
- real-session browser path decisions
- phased implementation plan

## Consolidated Strategy Baseline
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

## Browser Extension And Real-Session Appendix
## Goal

Build a real-user-session browser automation path for ClickCherry that works inside the user's everyday Chrome profile without relying on default-profile CDP relaunch.

This plan complements desktop and future accessibility automation. The current preferred path is to use Playwright MCP Bridge through a generic app-owned MCP harness before deciding whether ClickCherry needs its own custom extension.

## Why This Exists

The managed Chrome + Playwright/CDP path is valid for custom automation profiles, but it is not the right foundation for the user's default Chrome profile. Chrome's current default-profile restrictions make external CDP takeover the wrong long-term path for logged-in browser workflows.

The extension path solves a different problem:

- real LinkedIn / Gmail / Google Docs sessions
- real cookies, tabs, and logged-in state
- webpage DOM access from inside the user's actual profile

## Current Decision

ClickCherry should first integrate an off-the-shelf extension path:

- Playwright MCP server
- Playwright MCP Bridge Chrome extension
- generic MCP harness in the app

This means the first implementation target is not a bespoke ClickCherry browser wrapper. The app should become a generic MCP host that can run approved servers and expose their tools to the LLM with prompt-level usage policy.

If the Playwright MCP Bridge path later shows a proven workflow gap, then reassess whether ClickCherry needs its own custom extension.

## V1 Product Shape

The first real-session extension release should be deliberately narrow and should prefer an already-available extension bridge before any custom extension work.

### V1 responsibilities

- connect the app to the user's real Chrome session through Playwright MCP Bridge
- expose approved browser MCP tools to the LLM for webpage DOM work
- preserve browser state in the user's real session
- keep browser chrome / OS dialogs / non-DOM surfaces outside the browser MCP path

### V1 non-goals

- broad autonomous control of all browser tabs without user awareness
- browser chrome automation through the extension
- OS dialog control through the extension
- cross-origin network interception as a default feature
- silent sending, posting, purchasing, or messaging on behalf of the user
- full `chrome.debugger`-powered CDP control in the first store-facing version

## Architecture

The real-user-session path should use four cooperating pieces:

1. generic MCP runtime inside ClickCherry
2. approved Playwright MCP server process
3. Playwright MCP Bridge extension in Chrome
4. the user's real Chrome session

High-level flow:

- ClickCherry app starts or connects to the approved Playwright MCP server.
- The MCP server connects to Chrome through the installed Playwright MCP Bridge extension.
- The LLM uses approved browser MCP tools directly for webpage DOM work.
- The app handles server lifecycle, allowlist policy, and transport health.
- Results return to the LLM through the app's generic MCP runtime.

## App-Side MCP Responsibilities

The app should own generic MCP infrastructure, not a Playwright-specific browser wrapper.

Responsibilities:

- approved MCP server registry
- server startup / shutdown
- process health and reconnection
- tool discovery
- tool allowlisting
- tool invocation routing
- clear startup and bridge error handling

## First Browser Server

The first approved real-session browser server should be:

- `@playwright/mcp`
- launched in extension mode
- connected to the installed Playwright MCP Bridge extension

This lets the app use a real-session browser path now without immediately taking on custom extension distribution and review scope.

## Native App Responsibilities

The ClickCherry app should still own:

- task planning
- model orchestration
- approved MCP runtime
- desktop fallback
- browser launch/focus when needed
- browser chrome automation
- OS dialogs and permission prompts
- future macOS accessibility routing

The extension bridge should not replace the app. It should add a new browser-semantic backend for webpage content in the user's real browser session.

## Initial Action Surface

V1 should expose only the approved subset of Playwright MCP browser tools needed for webpage work.

Likely initial surface:

- `get_url`
- `get_title`
- `snapshot`
- `click`
- `type`
- `press`
- `scroll`
- `wait_for`
- `read_text`

These should be mapped to approved Playwright MCP tools, not to a custom ClickCherry browser wrapper contract.

This keeps the first release useful without pushing into the highest-risk permission and review surfaces.

## Locator Strategy

V1 should lean on the Playwright MCP tool model and snapshots rather than inventing a parallel locator language.

If later needed, app policy can limit which browser MCP tools the LLM sees without redefining their semantics.

## Planner Routing

For webpage tasks, the planner should choose among browser backends like this:

1. real logged-in Chrome session required:
   - use Playwright MCP Bridge through the generic MCP harness
2. managed/custom browser mode explicitly requested or later enabled:
   - use managed Playwright MCP mode
3. browser chrome / OS / non-DOM:
   - use accessibility, deterministic actions, or desktop fallback

Examples:

- "Open Chrome and go to linkedin.com" -> deterministic app/URL action
- "Click Jobs on LinkedIn in my real logged-in browser" -> Playwright MCP Bridge path
- "Click the extensions icon in Chrome" -> accessibility or desktop fallback
- "Interact with a canvas-heavy editor" -> desktop fallback

## Permission and Store-Risk Strategy

Because the first target is the Playwright MCP Bridge path, ClickCherry should avoid taking on custom-extension review risk before a real capability gap is proven.

### Lower-risk V1 principles

- single clear purpose
- explicit user-facing browser connection flow
- approved MCP allowlist rather than arbitrary server execution
- explicit consent for sensitive actions
- clear privacy explanation
- no hidden background behavior from the app

### Sensitive actions that should require confirmation

- sending messages
- posting social content
- submitting purchases
- accepting invitations or connection requests
- emailing or DMing on behalf of the user

### V1 recommendation

Do not start with a custom extension or `chrome.debugger`.

Start with:

- generic MCP harness in the app
- Playwright MCP Bridge as the real-session browser extension path
- prompt-level tool policy for when browser MCP tools should be used

Then revisit a custom extension only if this path proves insufficient for key user workflows.

## Custom Extension Follow-Up Path

If the Playwright MCP Bridge path proves too limited, a later version can revisit a custom ClickCherry extension for:

- tighter product-specific UX
- a narrower custom tool surface
- richer product telemetry
- possibly deeper browser capabilities if store risk remains acceptable

But this should be treated as a follow-up capability slice, not the baseline assumption for the first real-session browser release.

## User Experience Plan

The first real-session browser experience should feel explicit and trustworthy.

Suggested UX traits:

- explicit connection state between app and approved browser MCP server
- clear indication that the real browser session is connected through Playwright MCP Bridge
- clear indication of which tab/site is being controlled
- confirmation before sensitive outbound actions
- graceful fallback to desktop mode when the extension cannot act

## Testing Plan

Each extension step should include both automated and manual verification.

### Automated

- unit tests for MCP server registration, startup, and tool allowlisting
- integration tests for MCP tool discovery and invocation
- app-side tests for browser-tool routing and error handling

### Manual

- install Playwright MCP Bridge in a local Chrome profile
- verify MCP connection from the app to the real Chrome session
- verify active-tab click/type/read flows on simple webpages
- verify real logged-in workflows on sites such as LinkedIn or Google Docs
- verify fallback behavior when browser MCP tools cannot act on browser chrome or non-DOM surfaces

## Implementation Phases

### Phase E1: Generic MCP Foundation

- implement approved MCP server registry
- implement MCP server startup and tool discovery
- implement Playwright MCP extension-mode connection from the app

### Phase E2: Real-Session Browser V1

- expose the first approved Playwright MCP tool subset to the LLM
- add prompt routing for webpage DOM work
- validate real-session browser flows end-to-end

### Phase E3: Reassess Custom Extension Need

- identify concrete workflow gaps, if any
- decide whether a custom ClickCherry extension is still necessary

### Phase E4: Real-session workflows

- test logged-in LinkedIn / Docs style tasks
- add safer confirmation behavior for sensitive actions
- improve locator robustness

### Phase E5: Optional power features

- evaluate whether `chrome.debugger` is needed
- add it only for demonstrated workflow gaps

## Relationship To Managed Playwright

Managed Playwright remains useful and should stay in the product for:

- deterministic regression coverage
- clean automation sessions
- isolated browser testing
- workflows that do not require the user's live browser state

The extension path is not a replacement for that mode. It is the correct complement for real-session browser use.
