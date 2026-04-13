---
description: Real-session browser automation and browser-extension-adjacent V1 plan for ClickCherry.
---

# Browser Extension V1

## Goal

Build a real-user-session browser automation path for ClickCherry that works inside the user's everyday Chrome profile without relying on default-profile CDP relaunch.

This plan complements desktop and future accessibility automation. The current preferred path is a first-party ClickCherry extension with a direct app bridge.

## Why This Exists

The managed Chrome + Playwright/CDP path is valid for custom automation profiles, but it is not the right foundation for the user's default Chrome profile. Chrome's current default-profile restrictions make external CDP takeover the wrong long-term path for logged-in browser workflows.

The extension path solves a different problem:

- real LinkedIn / Gmail / Google Docs sessions
- real cookies, tabs, and logged-in state
- webpage DOM access from inside the user's actual profile

## Current Decision

ClickCherry should build its own extension path for browser v1:

- ClickCherry MV3 Chrome extension
- native messaging host
- direct app-to-extension bridge
- content-script DOM automation first

This means the first implementation target is a product-controlled browser connection flow, not an off-the-shelf Playwright bridge.

The generic MCP runtime work remains reusable infrastructure, but browser v1 does not depend on it.

## V1 Product Shape

The first real-session extension release should be deliberately narrow and should prefer an already-available extension bridge before any custom extension work.

### V1 responsibilities

- connect the app to the user's real Chrome session through a ClickCherry-controlled pairing flow
- expose a narrow DOM-focused browser action surface to the LLM for webpage work
- preserve browser state in the user's real session
- keep browser chrome / OS dialogs / non-DOM surfaces outside the browser MCP path

### V1 non-goals

- broad autonomous control of all browser tabs without user awareness
- browser chrome automation through the extension
- OS dialog control through the extension
- cross-origin network interception as a default feature
- silent sending, posting, purchasing, or messaging on behalf of the user
- full `chrome.debugger`-powered CDP control in the first store-facing version
- extension-owned screenshots in the first release

## Architecture

The real-user-session path should use four cooperating pieces:

1. ClickCherry app
2. native messaging host
3. ClickCherry extension in Chrome
4. the user's real Chrome session

High-level flow:

- ClickCherry app initiates or accepts a Chrome pairing request.
- The extension connects through native messaging to the app-controlled host.
- The LLM uses the app-owned browser action surface for webpage DOM work.
- The app handles pairing, trust, routing, and transport health.
- Results return to the LLM through the same run loop that already owns desktop fallback.

## App-Side Responsibilities

The app should own the browser bridge lifecycle directly in v1.

Responsibilities:

- pairing and reconnect
- trust-state persistence
- browser action routing
- clear browser connection diagnostics
- fallback to desktop/native when the extension cannot act

## Native App Responsibilities

The ClickCherry app should still own:

- task planning
- model orchestration
- desktop fallback
- browser launch/focus when needed
- browser chrome automation
- OS dialogs and permission prompts
- future macOS accessibility routing

The extension bridge should not replace the app. It should add a new browser-semantic backend for webpage content in the user's real browser session.

## Initial Action Surface

V1 should expose only the narrow browser action set needed for webpage work.

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

This keeps the first release useful without pushing into the highest-risk permission and review surfaces.

## Locator Strategy

V1 should use a small app-owned locator contract built for DOM-backed workflows:

- visible text
- role + label where available
- CSS selector for internal/fallback use
- form label / placeholder for inputs

Start simple and explicit before growing into a broader locator language.

## Planner Routing

For webpage tasks, the planner should choose among browser backends like this:

1. real logged-in Chrome session required:
   - use the first-party extension bridge
2. managed/custom browser mode explicitly requested or later enabled:
   - use managed Playwright
3. browser chrome / OS / non-DOM:
   - use accessibility, deterministic actions, or desktop fallback

Examples:

- "Open Chrome and go to linkedin.com" -> deterministic app/URL action
- "Click Jobs on LinkedIn in my real logged-in browser" -> first-party extension bridge path
- "Click the extensions icon in Chrome" -> accessibility or desktop fallback
- "Interact with a canvas-heavy editor" -> desktop fallback

## Pairing Strategy

The first pairing flow should be product-controlled:

1. user installs the ClickCherry extension
2. app shows `Connect Chrome`
3. extension discovers the native host and requests pairing
4. user approves once
5. app stores trust state in Keychain
6. extension stores profile-local trust state in `chrome.storage.local`
7. reconnect becomes automatic for that Chrome profile

This replaces the Playwright Bridge token-copy model with an app-owned connect flow.

## Permission and Store-Risk Strategy

Because this is now a first-party extension, ClickCherry should deliberately keep the first store-facing release narrow.

### Lower-risk V1 principles

- single clear purpose
- explicit user-facing browser connection flow
- standard extension APIs first
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

Do not start with `chrome.debugger`.

Start with:

- a first-party extension
- native messaging
- content-script DOM control
- prompt-level policy for when browser tools should be used
- app-owned screenshots and visual fallback

## Follow-Up Path

If the DOM-only extension path proves too limited, a later version can revisit:

- optional `chrome.debugger`
- richer product telemetry
- a broader action surface
- an MCP adapter on top of the first-party bridge if generic tool hosting becomes valuable

## User Experience Plan

The first real-session browser experience should feel explicit and trustworthy.

Suggested UX traits:

- explicit connection state between app and Chrome
- clear indication that the real browser session is connected through ClickCherry
- clear indication of which tab/site is being controlled
- confirmation before sensitive outbound actions
- graceful fallback to desktop mode when the extension cannot act

## Testing Plan

Each extension step should include both automated and manual verification.

### Automated

- unit tests for native messaging host registration and trust persistence
- integration tests for the extension bridge protocol
- app-side tests for browser-tool routing and error handling

### Manual

- install the ClickCherry extension in a local Chrome profile
- verify connection from the app to the real Chrome session
- verify active-tab click/type/read flows on simple webpages
- verify real logged-in workflows on sites such as LinkedIn or Google Docs
- verify fallback behavior when browser MCP tools cannot act on browser chrome or non-DOM surfaces

## Implementation Phases

### Phase E1: Direct Browser Bridge Foundation

- implement native messaging host registration
- implement pairing and reconnect
- implement extension <-> app protocol

### Phase E2: Real-Session Browser V1

- expose the first DOM-focused browser action subset to the LLM
- add prompt routing for webpage DOM work
- validate real-session browser flows end-to-end

### Phase E3: Real-Session Workflow Validation

- test logged-in LinkedIn / Docs style tasks
- add safer confirmation behavior for sensitive actions
- improve locator robustness

### Phase E4: Optional Power Features

- evaluate whether `chrome.debugger` is needed
- add it only for demonstrated workflow gaps
