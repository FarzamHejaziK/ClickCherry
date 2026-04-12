---
description: Canonical research and findings for ClickCherry automation reliability, browser automation, and real-profile investigation.
---

# Automation Research

## Purpose

This is the canonical research and findings doc for ClickCherry automation work.

It consolidates the previous `automation_findings.md` and `browser_real_profile_automation_findings.md` into one place so the short-form synthesis and the deeper real-profile investigation stay connected.

## Scope

- automation reliability findings
- semantic-vs-visual control findings
- real-profile browser automation research
- implementation-shaping external references

## Consolidated Findings Summary
## Summary

ClickCherry's current desktop execution loop is strong on screenshot capture, coordinate normalization, and post-action screenshots, but it still relies too heavily on visual clicking for targets that should be handled semantically. This creates two recurring failure modes:

- grounding misses: the model clicks a nearby icon or control instead of the intended one
- false success: the model reports success after a click event is injected, even when the intended target was not actually activated

These are known problems in computer-use agents and should be treated as expected failure classes, not edge cases.

## Current Observations In This Repo

- The OpenAI desktop runner already normalizes coordinates to the selected display and supports crop/grid screenshot workflows.
- The runner captures a fresh screenshot after tool execution, which gives us a good base for verification-driven behavior.
- Visual click tool outputs still resolve to a generic success payload today, which makes it easy for the model to over-credit a click as success.
- The prompt already encourages `open_app` and discourages terminal-based UI scripting, but it does not yet enforce a strong semantic-first routing policy or a "no success without evidence" rule.

## External Findings

### 1. Visual GUI agents still struggle with fine-grained grounding

Research and benchmark work on computer-use agents consistently shows that small, adjacent, icon-only, and visually similar controls are hard for current models to target reliably. This is especially true in high-resolution UIs, dense toolbars, docks, and professional app surfaces.

### 2. Verification is stronger than first-shot clicking

Recent grounding work suggests that models are often better at judging whether an action succeeded than at selecting the right pixel on the first try. This means a verification-driven loop is a high-leverage mitigation.

### 3. High-resolution and scaling issues are real

Multiple tools and public issues document errors caused by coordinate scaling, Retina/display conversion mismatches, and visually tiny targets. Even when the model conceptually finds the right target, execution can still land on the wrong nearby element.

### 4. Semantic control is more reliable than pixels

Where semantic handles exist, they should be preferred:

- browser DOM actions for website content
- macOS Accessibility actions for native UI
- deterministic app open/focus and keyboard paths for common shell-level actions

### 5. Playwright is powerful but not universal

Playwright is the right tool for DOM-backed website interaction, but it does not cover all Chrome or system interactions. It does not semantically control all browser chrome UI, OS sheets, permission prompts, or canvas-heavy content.

### 6. Managed Chrome and the default Chrome profile are no longer equivalent automation targets

Recent experiments and official Chrome guidance showed that managed Chrome and the user's default Chrome profile should not be treated as interchangeable CDP targets.

- managed or custom Chrome `user-data-dir` profiles remain viable for Playwright/CDP automation
- the default Chrome data directory should not be treated as a reliable CDP launch target
- real-user-session webpage automation should move toward an extension + native-app bridge instead of default-profile CDP takeover

### 7. Real-session Chrome automation through an extension is viable, but store risk depends heavily on scope

Recent product and policy research suggests that Chrome does allow browser automation extensions in the general category, but store risk rises quickly when the extension becomes too broad, too hidden, or too powerful by default.

Key implications:

- a narrow, explicit MV3 extension is a realistic first release shape
- a visible side panel and active-tab oriented workflow are safer than hidden background control
- `chrome.debugger` is powerful, but likely higher-risk than a DOM-only extension baseline
- sensitive outbound actions should require user confirmation

## Key Concepts

## Semantic Actions

Semantic actions target UI by identity instead of pixel location.

Examples:

- open Google Chrome by app name
- click a web button by DOM role and label
- press a native macOS button by accessibility role and title

Benefits:

- less sensitive to layout shifts
- less sensitive to coordinate mistakes
- easier to verify after execution

## Accessibility Actions

Accessibility actions use the macOS accessibility tree rather than mouse coordinates.

Examples:

- press a button by AX role/title
- set a text field value by AX identifier or label
- select a menu item through AX menu traversal
- inspect the focused window or element

These are ideal for native app controls when the app exposes good accessibility metadata.

## Playwright / CDP Attachment

For website content in Chrome, the agent should prefer a browser-semantic path:

1. launch or focus Chrome
2. connect via CDP remote debugging
3. attach Playwright to the browser session
4. operate on pages through DOM locators and assertions

Important limits:

- Chrome must be launched with remote debugging enabled for CDP attachment
- profile/session choice matters because it determines login state and cookies
- Playwright is best for webpage content, not every browser-UI surface
- the default Chrome data directory is no longer the right target for this path; managed or custom profiles should be used instead

## Real-Profile Browser Automation

When the task depends on the user's actual logged-in Chrome session, the browser-semantic path should diverge from managed Playwright:

1. keep Playwright + Node sidecar for managed/custom profiles
2. use an extension + native-app bridge for the user's real Chrome profile
3. keep desktop and future accessibility control for browser chrome, OS dialogs, and non-DOM UI

This keeps webpage DOM actions inside the user's real browser session without depending on default-profile CDP relaunch.

## Extension V1 Shape

The current recommended first release for real-session browser automation is:

- Manifest V3 extension
- service worker
- content scripts
- native messaging host
- active-tab DOM actions
- screenshots and simple page-state reads

The first version should avoid relying on `chrome.debugger` unless concrete workflow gaps prove that the DOM-only path is insufficient.

## Routing Matrix

| Target surface | Preferred action type | Notes |
|---|---|---|
| Open/focus Chrome | deterministic app action | `open_app` should be preferred over Dock clicking |
| Navigate to website | browser semantic action or deterministic URL open | avoid address-bar pixel flows when possible |
| Website links, buttons, forms | browser semantic action | use DOM/role/text/test-id targeting |
| Browser tab strip / toolbar / extension icon | accessibility or shortcut | not standard webpage DOM |
| Native app buttons, menus, dialogs | accessibility action | use AX when available |
| OS permission prompts, pickers, sheets | desktop action or accessibility | depends on what AX exposes |
| Canvas/WebGL/custom-rendered web UI | visual fallback | semantic handles may not exist |
| Image-only / ambiguous tiny targets | visual fallback with zoom and verification | force higher-confidence workflow |

## Recommended Product Direction

ClickCherry should move to a three-layer action model:

1. browser semantic actions for DOM-backed website interaction
2. accessibility actions for native macOS UI
3. desktop visual actions as fallback only

This preserves the current desktop runner, but changes its role from "primary action mechanism" to "last-resort executor" for ambiguous or non-semantic targets.

Within the browser layer, ClickCherry should now assume two execution modes:

- managed-browser mode:
  - Playwright + Node sidecar
  - custom `user-data-dir`
  - best for deterministic automation and regression coverage
- real-user-session mode:
  - extension + native-app bridge
  - best for logged-in workflows that depend on the user's existing Chrome profile
  - first release should be a narrower DOM-first extension rather than a full-power debugger-backed extension

## Immediate Reliability Recommendations

- Prefer semantic actions over visual clicks whenever possible.
- Never treat "click event injected" as equivalent to "task step succeeded."
- Require postcondition evidence before final success.
- Force crop/zoom/grid on small or ambiguous visual targets.
- Track false-success rate separately from raw action success.

## Locked Decisions

The current implementation sequence is now locked to these defaults:

- Phase 2 will use managed Chrome as the default browser-semantic baseline.
- Phase 2 will not treat the default Chrome profile as a supported CDP relaunch target.
- Real default-profile browser automation is now expected to move toward an extension + native-app bridge path.
- The first real-session extension release should start with a store-safer DOM-focused surface and defer `chrome.debugger`.
- Phase 3 will start with standard native controls only:
  - buttons
  - text fields
  - checkboxes and radio buttons
  - dialogs and sheets
  - menu items
  - window focus

These are intentional scoping decisions, not long-term limits. The design should remain extensible so later phases can add:

- richer browser extension capabilities for the user's real browser session
- optional `chrome.debugger` capabilities for proven workflow gaps
- deeper AX traversal for more complex app surfaces
- browser chrome support such as tab strip, toolbar, and omnibox targeting

## Deep-Dive Reference

For the full experiment log, reproduced failures, standalone test matrix, and updated root-cause analysis, see:

- `.docs/research/automation/automation_research.md`
- `.docs/research/automation/automation_strategy/README.md`

## Sources Consulted

- Anthropic computer use documentation
- OpenAI computer use documentation
- OSWorld benchmark paper and project page
- ScreenSpot-Pro grounding work
- Visual test-time scaling work for GUI grounding
- public Retina / coordinate mismatch automation issues
- macOS UI automation ecosystem documentation
- official Chrome guidance on remote debugging restrictions for the default data directory
- official Playwright guidance on using a separate user data directory for automation
- current Chrome extension and Web Store policy guidance relevant to extension-based browser automation

## Real-Profile Investigation Appendix
## Deep Research: Alternatives for Default-Profile Browser Automation (April 2026)

This section presents deep research into all major approaches for automating a user's real/default Chrome browser session now that Chrome 136+ blocks CDP `--remote-debugging-port` for the default data directory.

### Background: What Chrome 136 Changed

Starting in Chrome 136 (released 2025), `--remote-debugging-port` and `--remote-debugging-pipe` switches are silently ignored when Chrome runs against its default data directory. This was a deliberate security measure to prevent attackers from exploiting the debugging interface to extract cookies after App-Bound Encryption made direct credential theft harder. The restriction is enforced at launch: Chrome checks whether the data directory is the default one and, if so, refuses to open the debugging port. A custom `--user-data-dir` is now required for CDP to function.

Google's recommended alternatives are: (a) use Chrome for Testing (which preserves old behavior), or (b) use a custom `--user-data-dir`.

Sources: https://developer.chrome.com/blog/remote-debugging-port, https://github.com/browser-use/browser-use/issues/1520

---

### Approach 1: Chrome Extension + Native Messaging Host

**How it works:**

A Chrome extension runs inside the user's real browser session with full access to their cookies, logins, and tab state. The extension communicates with an external native application (the "native messaging host") via stdin/stdout message passing. Chrome starts the host as a separate process and communicates using length-prefixed JSON messages. The native app registers itself via a manifest JSON file placed in a platform-specific directory (on macOS: `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`).

The architecture is: Native App <-> Native Messaging Host <-> Chrome Extension Service Worker <-> Content Scripts (per tab).

**Capabilities:**

- Content scripts: Full DOM read/write access on any matched page. Can inject CSS, read page structure, modify elements, listen to events. Run in an isolated JavaScript world but share the page's DOM.
- `chrome.tabs.captureVisibleTab()`: Takes screenshots of the active tab's visible area (returns base64 PNG/JPEG).
- `chrome.debugger` API: If the extension also requests the `debugger` permission, it gets access to a large subset of CDP domains (see Approach 2 below), including `Input.dispatchMouseEvent`, `Input.dispatchKeyEvent` for trusted event injection, `Page.captureScreenshot` for full-page screenshots, `DOM.*` for shadow DOM and iframe access, `Network.*` for request interception, and `Runtime.evaluate` for arbitrary JS execution.
- `chrome.webNavigation`: Monitor navigation events across all tabs.
- Network interception: In MV3, the blocking `webRequest` API is restricted to policy-installed extensions. Regular extensions must use Declarative Net Request (DNR) for rule-based blocking/modification, or use `chrome.debugger` + `Fetch.enable` for full programmatic interception.
- Native messaging throughput: Messages are limited to 1MB per message. Communication is asynchronous via stdin/stdout.

**Permissions required:**

- `"permissions": ["debugger", "tabs", "activeTab", "nativeMessaging", "webNavigation"]`
- `"host_permissions": ["<all_urls>"]`
- Native messaging host manifest with `allowed_origins` listing the extension ID.

**Security restrictions:**

- Cannot access `chrome://*` pages, the Chrome Web Store, or other extensions' pages.
- Content scripts cannot call privileged Chrome APIs directly; they must message the service worker.
- The `debugger` permission triggers Chrome Web Store scrutiny during review.
- The `debugger` permission causes a visible yellow warning bar (see Approach 2).

**Real-world examples:**

- Claude in Chrome (Anthropic): Uses exactly this architecture. Extension service worker + native messaging host that creates a Unix domain socket. Claude Code communicates via the socket to drive browser automation through the extension. The extension can open tabs, interact with DOM, read console output, and take screenshots.
- Playwright MCP Chrome Extension (Microsoft): Extension uses `chrome.debugger` to attach to tabs, establishes a WebSocket connection to a relay server, and forwards CDP commands between the MCP server and browser tabs. Supports token-based auth and manual approval workflows.
- Browser MCP: Similar extension-based architecture for MCP tool integration.

**Feasibility:** High. This is the most proven path for real-profile automation. Multiple production tools already use it.

**Reliability:** High. The extension runs inside Chrome's own process model, so it inherits Chrome's stability. Native messaging is a well-tested IPC channel.

**Security implications:** Moderate. The extension has broad access to all web content. Native messaging is scoped to a single registered host. The `debugger` permission gives CDP-level access but is gated by Chrome's permission model and Web Store review.

**User experience impact:** The `chrome.debugger` warning bar is the main UX concern. It can be suppressed with `--silent-debugger-extension-api` launch flag, or by using only content-script-based interactions (which produce no banner but have less capability). Extensions installed via enterprise policy suppress the banner automatically.

**Maintenance burden:** Moderate. Must track Chrome extension API changes (MV3 evolution), handle Chrome updates that may change permission behavior, and maintain the native messaging host binary for each platform.

Sources: https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging, https://code.claude.com/docs/en/chrome, https://github.com/microsoft/playwright-mcp/blob/main/packages/extension/README.md

---

### Approach 2: Chrome DevTools Protocol via chrome.debugger Extension API

**How it works:**

A Chrome extension with the `"debugger"` permission can call `chrome.debugger.attach({tabId}, "1.3")` to attach a CDP session to any tab. Once attached, it can send arbitrary CDP commands via `chrome.debugger.sendCommand()` and receive events via `chrome.debugger.onEvent`. This gives the extension nearly the same power as a direct CDP WebSocket connection, but from inside the browser process.

**Accessible CDP domains:**

Accessibility, Audits, CacheStorage, Console, CSS, Database, Debugger, DOM, DOMDebugger, DOMSnapshot, Emulation, Fetch, IO, Input, Inspector, Log, Network, Overlay, Page, Performance, Profiler, Runtime, Storage, Target, Tracing, WebAudio, WebAuthn.

**What you can do:**

- Full-page screenshots via `Page.captureScreenshot` (including beyond-viewport with `captureBeyondViewport: true`)
- Trusted mouse/keyboard event injection via `Input.dispatchMouseEvent` / `Input.dispatchKeyEvent` (these generate browser-level trusted events, unlike JS-dispatched events)
- Full accessibility tree via `Accessibility.getFullAXTree`
- DOM query/modification including shadow DOM and iframes via `DOM.*`
- Network interception and modification via `Fetch.*` / `Network.*`
- JavaScript evaluation via `Runtime.evaluate`
- Device/geolocation/timezone emulation via `Emulation.*`
- CSS read/write via `CSS.*`
- Cross-origin iframe support via flat sessions (Chrome 125+, using `sessionId` parameter)

**Limitations vs direct CDP:**

- Restricted domain list: Not all CDP domains are available. Some domains (HeapProfiler, etc.) are restricted.
- Cannot debug `chrome://*` pages, Web Store, or other extensions.
- Cannot debug extension background pages without `--silent-debugger-extension-api` flag.
- Only one debugger can be attached per tab at a time. If DevTools is open on the same tab, attachment fails.
- Single-page attachment: Puppeteer-in-extension mode attaches to one tab at a time (though you can re-attach to different tabs sequentially).

**The warning banner:**

When `chrome.debugger.attach()` is called, Chrome shows a yellow infobar: "[Extension Name] started debugging this browser." This bar persists while the debugger is attached. Users can dismiss it, but it reappears on re-attach.

Suppression options:
1. Launch Chrome with `--silent-debugger-extension-api` (must be done every launch; a wrapper script can automate this).
2. Install the extension via enterprise/group policy (suppresses the banner automatically).
3. Minimize attach duration: attach only during active operations, detach immediately after.

**Performance:**

The `chrome.debugger` API adds a small overhead compared to direct WebSocket CDP since commands route through Chrome's extension system. However, it eliminates the entire Playwright/Node.js middleman that Browser Use found was adding a second network hop with meaningful latency. For most AI agent use cases, the overhead is negligible.

**Feasibility:** High. This is the most capable approach for real-profile automation.

**Reliability:** High. Uses Chrome's own internal CDP plumbing.

**Security implications:** Moderate. Same as Approach 1 since they are typically used together.

**User experience impact:** The yellow warning bar is the primary concern. Manageable with the suppression strategies above.

**Maintenance burden:** Low to moderate. The CDP domain allowlist is stable. Chrome updates occasionally add new domains. The `chrome.debugger` API itself is mature and well-maintained.

Sources: https://developer.chrome.com/docs/extensions/reference/api/debugger, https://medium.com/@dzianisv/vibe-engineering-chrome-devtools-protocol-from-extensions-you-dont-need-to-fork-chromium-72a9ffb68b6d

---

### Approach 3: WebDriver BiDi

**How it works:**

WebDriver BiDi is the W3C successor to the classic WebDriver protocol. It adds bidirectional communication (WebSocket-based) on top of WebDriver, allowing the browser to push events to the controlling client. Chromium's implementation (`chromium-bidi`) runs as a JavaScript layer inside a Chrome tab that translates BiDi commands to CDP commands internally.

**Can it connect to an already-running Chrome instance with the default profile?**

No. WebDriver BiDi for Chromium still depends on the same underlying debugging infrastructure as CDP. The `chromium-bidi` server connects to Chrome via CDP WebSocket, which means it requires `--remote-debugging-port` or `--remote-debugging-pipe` to be active. Since Chrome 136 blocks these on the default data directory, WebDriver BiDi inherits the same restriction. It cannot connect to a user's normal Chrome instance that was launched without debugging flags.

**Current maturity:**

WebDriver BiDi is still incomplete. Not all CDP features are supported yet; Puppeteer defaults to CDP when connecting to Chrome because BiDi coverage is not yet full. Selenium is actively implementing BiDi support but notes that CDP remains the primary protocol until BiDi reaches parity.

**Feasibility:** Low for real-profile automation. Same underlying restriction as raw CDP.

**Reliability:** Medium. The protocol is still evolving and not at parity with CDP.

**Security implications:** Same as CDP -- requires debugging port, which Chrome blocks on default profiles.

**User experience impact:** Would require relaunching Chrome with flags and a custom user-data-dir, same as raw CDP.

**Maintenance burden:** High. The protocol is still a moving target. Breaking changes are expected as the spec evolves.

Sources: https://w3c.github.io/webdriver-bidi/, https://github.com/GoogleChromeLabs/chromium-bidi, https://developer.chrome.com/blog/webdriver-bidi

---

### Approach 4: macOS Accessibility APIs (AXUIElement)

**How it works:**

macOS exposes an accessibility tree for every running application. Chrome builds this tree from its internal rendering of web content: each DOM node corresponds to an accessibility object with role, name, bounding box, and other properties. External processes can query and act on this tree using the `AXUIElement` C API (or Swift wrappers like AXorcist). The app must have Accessibility permissions granted in System Settings.

**Capabilities:**

- Read: Can traverse the accessibility tree to find elements by role, title, identifier, value. Chrome exposes `AXDOMClassList` and `AXDOMIdentifier` attributes for web content elements.
- Click: Can perform `AXPress` on buttons and interactive elements.
- Type: Can use `AXSetValue` on text fields.
- Position: Can read bounding boxes of elements.
- Focus: Can set focus to elements.

**Limitations:**

- Granularity is limited to what Chrome exposes. Chrome's accessibility tree is a simplified/semantic view of the DOM, not a 1:1 DOM mirror. Many non-interactive or decorative elements may be pruned.
- `AXPress` and `AXSetValue` are unreliable on some elements. Chrome may not expose action handlers for all interactive DOM elements through the accessibility API.
- Scalability: Platform accessibility frameworks struggle with pages containing hundreds of thousands of elements (common on complex web pages). Chrome's accessibility cache helps, but traversal can be slow.
- No network interception, no JavaScript execution, no screenshot capture, no cookie access.
- CSS-complex controls (3D transforms, canvas, WebGL) have no meaningful accessibility representation.
- Cross-origin iframes may appear as opaque subtrees.
- Requires user to grant Accessibility permission to the controlling app.

**What it is good for:**

- Interacting with Chrome's own UI (tab bar, address bar, menus, dialogs, permission prompts) which are native controls not accessible via web APIs.
- Fallback for OS-level dialogs, file pickers, authentication prompts.
- Supplementing extension-based automation for non-DOM surfaces.

**Feasibility:** Low as a primary automation mechanism. Useful as a supplementary layer.

**Reliability:** Medium. Works well for Chrome's native UI. Unreliable for complex web content.

**Security implications:** Low. Accessibility APIs are a standard OS feature. Requires explicit user permission grant.

**User experience impact:** None beyond the initial permission grant. No banners or warnings during use.

**Maintenance burden:** Low for Chrome UI. Higher for web content because Chrome may change its accessibility tree structure across versions.

Sources: https://chromium.googlesource.com/chromium/src/+/HEAD/docs/accessibility/browser/how_a11y_works.md, https://github.com/steipete/AXorcist, https://developer.apple.com/documentation/applicationservices/axuielement_h

---

### Approach 5: Profile Clone with --restore-last-session

**How it works:**

Copy the user's default Chrome profile directory to a custom `user-data-dir`, then launch Chrome with `--user-data-dir=/path/to/copy --remote-debugging-port=9222 --restore-last-session`. The idea is that CDP works with custom user-data-dirs, and the cloned profile would carry over the user's cookies, sessions, and tabs.

**Cookie encryption on macOS:**

On macOS, Chrome encrypts cookies using AES-128-CBC. The encryption key is derived via PBKDF2 (1003 iterations, salt "saltysalt") from a passphrase stored in the macOS login keychain under "Chrome Safe Storage". Critically, this keychain entry is per-user, not per-profile-directory. Any Chrome instance running under the same macOS user account accesses the same keychain entry. This means: when you copy a profile to a different directory on the same machine and same user account, Chrome can still decrypt the cookies because it reads the same "Chrome Safe Storage" key from the keychain.

**On Windows (important caveat):**

Windows uses App-Bound Encryption (Chrome 127+), which binds the encryption key to Chrome's install path. The IElevator COM server validates that the calling EXE lives in the browser's install directory. A profile copy to a different user-data-dir on Windows may fail to decrypt cookies because the app-bound key validation is stricter.

**Will sessions survive the copy?**

- Cookies: Yes on macOS (same keychain). Likely not on Windows (App-Bound Encryption).
- Session/tab state: Yes, if `--restore-last-session` is used and the `Current Session` / `Last Session` files are intact in the copied profile.
- Extension state: Partially. Extensions are registered per-profile, and their state files are in the profile directory. Simple extensions will work; extensions with external auth (OAuth tokens) may need re-authentication.
- localStorage/IndexedDB: Yes, these are plain files in the profile directory.

**Practical challenges:**

- Profile size: A real Chrome profile can be multiple gigabytes. Copying is slow and disk-heavy. Symlinks can mitigate this but introduce lock-file conflicts if both profiles are accessed simultaneously.
- Lock files: Chrome uses profile lock files. Two Chrome instances cannot share the same profile directory. The copy must be a true copy, not a symlink to the same directory.
- Profile staleness: The copy is a point-in-time snapshot. New cookies, bookmarks, or history in the original profile are not reflected. Repeated automation requires repeated copying.
- User disruption: If Chrome is already running with the default profile, you cannot copy the profile safely (open SQLite databases, lock files). You would need to quit Chrome first, copy, then launch the copy -- which is disruptive.

**Feasibility:** Medium. Works on macOS for cookies. Fragile on Windows. Disruptive to the user's workflow.

**Reliability:** Low to medium. Profile copies are point-in-time snapshots that go stale. Lock files and concurrent access are error-prone.

**Security implications:** Low-medium. The copied profile has the same cookies and credentials as the original. If the copy is not cleaned up, it leaves a second copy of sensitive data on disk.

**User experience impact:** High. Requires quitting Chrome, waiting for copy, relaunching a second instance. The user's original Chrome is unavailable during the process unless they accept stale data.

**Maintenance burden:** High. Must handle profile format changes across Chrome versions, platform-specific encryption differences, lock file management, and cleanup of stale copies.

Sources: https://gist.github.com/creachadair/937179894a24571ce9860e2475a2d2ec, https://gist.github.com/aont/c8bd778e33dee4e2063d32364e9e0e8f, https://chromium.googlesource.com/chromium/src/+/master/docs/user_data_dir.md

---

### Approach 6: Puppeteer connectOverCDP to an Already-Running Browser

**How it works:**

Puppeteer's `connect()` and `connectOverCDP()` methods allow attaching to a Chrome instance that exposes a CDP WebSocket endpoint (typically via `--remote-debugging-port=9222`). If Chrome is already running with debugging enabled, you can connect after the fact by reading the WebSocket URL from `http://localhost:9222/json/version`.

**Can you connect to a normally-launched Chrome (no debugging flags)?**

No. If Chrome was launched without `--remote-debugging-port`, there is no WebSocket endpoint to connect to. Puppeteer has no mechanism to inject a debugging port into an already-running Chrome process. The debugging infrastructure must be enabled at launch time.

**What about Chrome 136+ with default profiles?**

Even if the user launches Chrome with `--remote-debugging-port=9222` manually, Chrome 136+ ignores this flag when using the default data directory. So `connectOverCDP` is doubly blocked: (a) Chrome does not open the port on the default profile, and (b) there is no way to enable the port after launch.

**Puppeteer inside a Chrome extension:**

Puppeteer can run inside a Chrome extension using `ExtensionTransport.connectTab(tabId)`. This uses the `chrome.debugger` API as the transport instead of a WebSocket. This works on the user's real profile because the extension is already inside the browser. However, it is limited to one tab at a time and is marked as experimental.

**Chrome M144+ changes:**

Playwright has filed a feature request for Chrome M144+ remote debugging support. The remote debugging protocol is evolving, and `connectOverCDP()` now accepts a `handleDevToolsAsPage` option for newer Chrome versions.

**Feasibility:** Very low for connecting to a normally-launched default-profile Chrome. High if using Puppeteer inside an extension (but then you are really doing Approach 1/2).

**Reliability:** N/A for the primary use case (cannot connect).

**Security implications:** N/A.

**User experience impact:** N/A.

**Maintenance burden:** N/A.

Sources: https://pptr.dev/api/puppeteer.puppeteer.connect, https://pptr.dev/guides/running-puppeteer-in-extensions, https://github.com/puppeteer/puppeteer/issues/3543

---

### Approach 7: Commercial/Open-Source AI Browser Automation Frameworks

**Browser Use:**

Browser Use originally used Playwright but switched entirely to raw CDP for performance. Their architecture now uses direct CDP WebSocket connections with a Python type-binding generator (`cdp-use`). For the Chrome 136 restriction, Browser Use's approach is:

- Open-source mode: Users specify `extra_browser_args=["--user-data-dir=remote-debug-profile"]` to launch Chrome with a custom profile. Users must manually authenticate or copy credentials.
- Cloud mode: Users sync their real Chrome profile to the cloud via a CLI command, or export cookies as JSON. The cloud browser loads these credentials.
- 1Password integration: For the cloud version, credentials are pulled from 1Password service accounts.

Browser Use does NOT solve the default-profile-with-CDP problem. They work around it by requiring a custom user-data-dir or by copying/syncing credentials to a separate environment.

Source: https://browser-use.com/posts/playwright-to-cdp, https://browser-use.com/posts/web-agent-authentication

**Browserbase:**

Browserbase provides cloud-hosted browser instances ("Contexts") with persistent state. Their approach to authentication is:

- Cookie sync: Users can sync cookies from their local Chrome to a Browserbase context, filtered by domain.
- Persistent contexts: Auth state is saved and reused across sessions.

Browserbase also does NOT automate the user's local default Chrome. It runs separate cloud browser instances and copies credentials into them.

Source: https://www.browserbase.com/

**Playwright MCP Chrome Extension (Microsoft):**

This is the most relevant for the default-profile use case. It uses a Chrome extension that employs the `chrome.debugger` API to attach to user tabs, combined with a WebSocket relay server. The MCP server connects to the relay, which forwards commands to the extension. This is essentially Approach 1+2 packaged as an MCP server.

Key features: token-based auth, manual tab selection, uses existing cookies/sessions, no custom profile needed.

Source: https://github.com/microsoft/playwright-mcp

**Claude in Chrome (Anthropic):**

Also uses Approach 1+2. A Chrome extension with native messaging host that bridges to Claude Code via Unix domain sockets. The extension runs in the user's real browser with their real session state.

Source: https://code.claude.com/docs/en/chrome

**Agent Browser (Vercel):**

Uses CDP with fallback handling. Recently filed issues about Chrome 136 breaking their default flow.

Source: https://github.com/vercel-labs/agent-browser

**Summary of how the industry handles this:**

Every major AI browser automation framework has converged on one of two strategies:
1. Extension-based: Use a Chrome extension (with `chrome.debugger` or content scripts) to automate the user's real browser from inside. This is the only approach that works with the default profile without any workarounds. (Claude in Chrome, Playwright MCP Extension, Browser MCP)
2. Profile copy/sync: Copy or sync credentials from the default profile to a custom `user-data-dir` or cloud browser, then use CDP there. (Browser Use, Browserbase, custom setups)

No major framework has found a way to use raw CDP against the default Chrome profile post-136.

---

### Comparative Assessment

| Approach | Feasibility | Reliability | Security | UX Impact | Maintenance | Real Profile? |
|---|---|---|---|---|---|---|
| 1. Extension + Native Messaging | High | High | Moderate | Low (debugger bar) | Moderate | Yes |
| 2. chrome.debugger via Extension | High | High | Moderate | Moderate (bar) | Low-Mod | Yes |
| 3. WebDriver BiDi | Low | Medium | Same as CDP | High (relaunch) | High | No |
| 4. macOS Accessibility | Low (primary) | Medium | Low | None | Low | Partial |
| 5. Profile Clone + CDP | Medium | Low-Med | Low-Med | High (disruptive) | High | Snapshot only |
| 6. Puppeteer connectOverCDP | Very Low | N/A | N/A | N/A | N/A | No |
| 7. Industry frameworks | High | High | Moderate | Low-Mod | Moderate | Via extension |

### Recommendation

For ClickCherry, the clear winner is **Approach 1+2 combined: a Chrome Extension using the `chrome.debugger` API, communicating with the native app via Native Messaging**.

This is the approach used by Claude in Chrome, Playwright MCP Extension, and Browser MCP. It is the only approach that:

- Works with the user's real default Chrome profile
- Preserves all cookies, sessions, and extensions
- Does not require relaunching Chrome or copying profiles
- Provides full CDP-level control (screenshots, DOM, Input, Network, Accessibility tree)
- Generates trusted browser events (not JS-dispatched)
- Has production-proven stability
- Scales to the capabilities needed for an AI agent

The macOS Accessibility API (Approach 4) should be retained as a supplementary layer for Chrome's native UI, OS dialogs, and non-DOM surfaces, as originally planned.

---

## Original Findings (Phase 2 Experiments)

## Summary

The recent Phase 2 browser-semantic experiments showed that ClickCherry's managed Chrome + Playwright/CDP path is viable, but the same approach is not a reliable foundation for the user's default everyday Chrome profile.

The key conclusion is:

- managed or custom Chrome `user-data-dir` profiles work reliably for CDP-backed browser automation
- the default Chrome profile under `~/Library/Application Support/Google/Chrome` should not be treated as a reliable CDP launch target
- real-user-session webpage automation should move toward an extension + native-app bridge path instead of profile takeover via CDP relaunch

This is supported by both local experiments and official Chrome / Playwright guidance.

## Code Snapshot Reference

The experimental browser-action and real-profile takeover code from this investigation is preserved on:

- `codex/browser-action-snapshot`

`main` intentionally keeps the findings, plan, and issue documentation from this spike without carrying the experimental browser-action implementation itself.

## Questions Investigated

1. Can ClickCherry reliably launch Chrome under CDP control and automate webpage content?
2. Can the same mechanism be used against the user's real Chrome profile?
3. If not, is the failure caused by local timing bugs, or by a deeper platform constraint?

## Local Runtime Findings

### 1. Managed Chrome + Playwright works

Using a managed profile with a non-default `user-data-dir`, the browser sidecar was able to:

- launch Chrome
- expose the CDP debugging endpoint
- attach successfully
- reuse the same browser session across follow-up actions
- navigate to `https://www.google.com/`
- return the expected title and URL

This confirms that the basic browser-semantic approach is viable.

### 2. Real-profile takeover failed in the app

When the task requested the real `Farzam` Chrome profile, the app behavior evolved through several debugging stages:

- initial behavior:
  - browser attach failed because the GUI app could not find `node` on `PATH`
- after Node discovery was fixed:
  - browser attach reached Chrome launch, but timed out waiting for the CDP debugging port
- after same-profile takeover was added:
  - the previously running Chrome session was closed
  - Chrome visibly reopened
  - the CDP debugging port still never came up

This ruled out simple launcher visibility issues. Chrome reopened, but not in a state the automation layer could attach to.

### 3. The blank-tab symptom was a launcher side effect

Earlier failures also opened multiple `about:blank` tabs. That came from the sidecar explicitly launching Chrome with `about:blank` before webpage navigation happened.

That behavior was useful for early CDP smoke tests, but not acceptable as a product-facing fallback. It was removed during debugging, and the remaining failure still persisted.

## Standalone Experiments

To avoid overfitting to the app runtime, the browser-launch hypothesis was tested outside the codebase with a standalone probe against four scenarios:

1. managed temporary profile
2. real default profile while Chrome was already running
3. real default profile after graceful quit and immediate relaunch
4. real default profile after graceful quit, full process drain, and delayed relaunch

### Results

- managed temporary profile:
  - CDP became available quickly
- real default profile while Chrome already running:
  - CDP did not become available
- real default profile after graceful quit and immediate relaunch:
  - CDP did not become available
- real default profile after graceful quit, full drain, and delayed relaunch:
  - CDP did not become available

### What This Ruled Out

These experiments ruled out the earlier "relaunch too early" hypothesis.

The failure was not explained by:

- the original Chrome process still running
- helper processes not draining quickly enough
- relaunching too soon after quit

The managed-profile path worked in the same environment, which isolated the problem to the default Chrome profile path rather than CDP itself.

## Official External Findings

Official Chrome and Playwright documentation now explain this behavior directly.

### Chrome

Chrome's official guidance states that, starting with Chrome 136, `--remote-debugging-port` and related switches are ignored for the default Chrome data directory. Automation should use a non-standard `--user-data-dir`.

Source:

- https://developer.chrome.com/blog/remote-debugging-port

### Playwright

Playwright also documents that the default Chrome user data directory is no longer the expected automation target, and that a separate user data directory should be used.

Source:

- https://playwright.dev/docs/codegen

### Chromium source

Chromium source reinforces that remote debugging is guarded against the default data directory path.

Source:

- https://chromium.googlesource.com/chromium/src/+/HEAD/chrome/browser/devtools/remote_debugging_server.cc

## Root Cause

The core issue is not merely local flakiness.

The current "take over the user's real default Chrome profile by relaunching it with CDP flags" approach conflicts with Chrome's current security model for the default data directory.

That means:

- continuing to tune relaunch timing is unlikely to solve the problem
- continuing to invest in real-profile CDP takeover would be working against the platform
- the managed-profile path remains valid because it uses a custom automation `user-data-dir`

## Product Impact

This changes how Phase 2 should be interpreted.

### Still valid

- `browser_action` as the primary semantic surface for webpage DOM interaction
- Playwright/Node sidecar for managed browser automation
- managed/custom profiles for clean browser automation and testing

### No longer a recommended foundation

- CDP-launching the user's default Chrome profile
- same-profile Chrome takeover as the main way to access the user's existing logged-in session

## Recommended Solution

Use two browser-semantic modes instead of one:

### 1. Managed browser mode

Use Playwright + Node sidecar with a managed or custom `user-data-dir` for:

- clean automation
- regression testing
- deterministic browser_action behavior
- tasks that do not require the user's exact live browser session

### 2. Real-user-session browser mode

For the user's real Chrome profile, move to an extension + native-app bridge:

- the extension runs inside the user's actual profile and tab session
- DOM actions happen from inside the real browser session
- the native app remains the orchestrator
- desktop or accessibility control still handles browser chrome, OS dialogs, and non-DOM fallbacks

## Extension Direction

The extension path should begin with a narrower first release than the most powerful possible browser-control design.

### Recommended V1

- Manifest V3 extension
- service worker
- content scripts
- native messaging host
- active-tab DOM actions
- visible screenshot capture for the current tab
- explicit user-facing UX

### Recommended V1 exclusions

- no default dependence on `chrome.debugger`
- no hidden full-browser takeover positioning
- no silent send/post/purchase actions

The first goal is not "maximum power." The first goal is a trustworthy, review-friendlier real-session browser layer that can handle common logged-in webpage tasks.

For the concrete implementation outline, see:

- `.docs/research/automation/automation_strategy/README.md`

## Proposed Follow-Up Work

1. Stop treating real default Chrome profiles as a supported CDP takeover target in the active Phase 2 plan.
2. Keep managed Playwright mode as the supported browser_action baseline.
3. Re-scope real-profile webpage automation around:
   - a Chrome extension
   - a native messaging host or equivalent app bridge
   - a browser_action backend that targets the active tab DOM from inside the user's real profile
4. Preserve desktop and future accessibility actions for:
   - browser chrome
   - OS dialogs
   - non-DOM UI
   - canvas / image-only / custom-rendered surfaces
5. Implement the first extension slice with a DOM-only, store-safer scope before considering `chrome.debugger`.

## Decision

The Phase 2 architecture should now be treated as:

- managed browser automation via Playwright/CDP for custom profiles
- real-profile browser automation via extension/native-app bridge

The real default Chrome profile should not be the CDP relaunch target going forward.
