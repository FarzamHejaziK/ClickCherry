---
description: Real-session browser automation and browser-extension-adjacent V1 plan for ClickCherry.
---

# Browser Extension V1

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
