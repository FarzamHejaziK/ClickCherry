# Automation Plan

## Goal

Improve execution reliability by routing tasks to the most semantic control surface available instead of defaulting to mouse-based visual clicking.

## Desired Architecture

ClickCherry should evolve toward three action layers:

1. `browser_action`
   - for webpage content in Chrome and other supported browsers
   - backed by one of two browser-semantic backends:
     - Playwright via CDP for managed/custom profiles
     - extension + native-app bridge for the user's real Chrome profile

2. `accessibility_action`
   - for native macOS UI
   - backed by macOS Accessibility APIs

3. `desktop_action`
   - for visual fallback only
   - used when semantic targeting is unavailable or untrustworthy

## Locked Decisions

- Phase 2 defaults to managed Chrome:
  - ClickCherry launches a CDP-enabled Chrome instance it controls.
  - managed/custom `user-data-dir` profiles remain the supported Playwright baseline.
- Phase 2 will not treat the default Chrome profile as a supported CDP relaunch target.
- Real default-profile browser automation moves to a separate extension + native-app bridge path.
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

## Phase 2: Browser Semantic Control

Focus:

- add a browser-side action surface for DOM-backed tasks
- use Playwright as a sidecar rather than trying to make Swift the Playwright runtime

Proposed capabilities:

- `attach_or_launch_chrome`
- `list_tabs`
- `select_tab`
- `goto`
- `click`
- `type`
- `press`
- `wait_for`
- `snapshot`
- `get_url`
- `get_title`

Implementation note:

- Playwright is not officially supported in Swift
- use a Node Playwright helper process or equivalent sidecar
- connect to Chrome via CDP remote debugging

Profile/session note:

- launching Chrome for CDP requires choosing a browser profile strategy
- support at least:
  - dedicated automation profile
  - named managed profile
- do not treat the default Chrome data directory as the future selected-user-profile follow-up path
- official Chrome behavior now requires Phase 2 to distinguish:
  - managed/custom profile automation through Playwright/CDP
  - real-user-session automation through a different browser-semantic mechanism

Real-user-session note:

- when the task depends on the user's real logged-in Chrome profile, the recommended direction is an extension + native-app bridge
- this path should own webpage DOM interaction for the active real-profile tab
- browser chrome, OS dialogs, and non-DOM surfaces should remain with desktop and future accessibility layers

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

1. browser semantic action
2. accessibility action
3. deterministic shortcut or app/URL action
4. visual desktop action

Within `browser_action`, the planner should now assume:

1. managed/custom profile requested or acceptable:
   - use Playwright/CDP
2. real user Chrome profile required:
   - use extension/native-app bridge
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

- Swift host process
- Node Playwright sidecar for managed/custom profiles
- extension + native-app bridge for the user's real Chrome profile
- local JSON or stdio contract between Swift and the browser backends

Why:

- official Playwright support exists outside Swift
- avoids betting product architecture on unofficial wrappers
- keeps browser automation semantics strong and maintainable
- avoids fighting Chrome's default-profile remote debugging restrictions when real user-session automation is required

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

1. Keep managed Playwright/CDP as the supported browser_action baseline for custom profiles.
2. Stop treating the default Chrome profile as a supported CDP takeover target.
3. Design the browser extension + native-app bridge for real-user-session webpage automation.
4. Define planner policy for choosing between managed-browser mode and real-user-session mode.
5. Implement `accessibility_action` after the browser-semantic architecture is stable.

## Open Questions

- How should the app expose the distinction between managed-browser mode and real-user-session mode in product UX?
- What is the minimal extension-backed action surface needed to replace the most common website clicks in the user's real session?
