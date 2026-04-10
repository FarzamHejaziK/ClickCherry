#!/usr/bin/env node

import { chromium } from 'playwright';
import { spawn, spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import fs from 'node:fs/promises';
import http from 'node:http';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

class SidecarError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString('utf8');
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function browserAutomationRoot() {
  return path.join(os.homedir(), 'Library', 'Application Support', 'TaskAgentMacOS', 'browser-automation');
}

function managedProfilesRoot() {
  return path.join(browserAutomationRoot(), 'profiles');
}

function defaultManagedUserDataDir() {
  return path.join(browserAutomationRoot(), 'chrome-profile');
}

function defaultChromeUserDataDir() {
  return path.join(os.homedir(), 'Library', 'Application Support', 'Google', 'Chrome');
}

function normalizeSearchText(value) {
  return String(value ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function sanitizeManagedProfileName(value) {
  const normalized = normalizeSearchText(value).replace(/\s+/g, '-');
  return normalized || 'managed-profile';
}

function httpJson(url) {
  return new Promise((resolve, reject) => {
    const request = http.get(url, (response) => {
      const chunks = [];
      response.on('data', (chunk) => chunks.push(chunk));
      response.on('end', () => {
        const body = Buffer.concat(chunks).toString('utf8');
        if ((response.statusCode ?? 500) >= 400) {
          reject(new Error(body || `HTTP ${response.statusCode}`));
          return;
        }
        try {
          resolve(JSON.parse(body));
        } catch (error) {
          reject(error);
        }
      });
    });
    request.on('error', reject);
  });
}

function findAvailablePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.unref();
    server.on('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      const port = typeof address === 'object' && address ? address.port : null;
      server.close((closeError) => {
        if (closeError) {
          reject(closeError);
          return;
        }
        if (!port) {
          reject(new Error('No port assigned.'));
          return;
        }
        resolve(port);
      });
    });
  });
}

function resolveChromeExecutable() {
  const candidates = [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  ];
  return candidates.find((candidate) => existsSync(candidate)) ?? null;
}

async function waitForCDP(port, timeoutMs = 15000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const version = await httpJson(`http://127.0.0.1:${port}/json/version`);
      if (version.webSocketDebuggerUrl) {
        return version;
      }
    } catch {}
    await wait(250);
  }
  throw new SidecarError('execution_failed', `Timed out waiting for Chrome debugging port ${port}.`);
}

function terminateLaunchedChrome(pid) {
  if (!pid) {
    return;
  }
  try {
    process.kill(-pid, 'SIGTERM');
  } catch {
    try {
      process.kill(pid, 'SIGTERM');
    } catch {}
  }
}

function isChromeRunning() {
  try {
    const result = spawnSync('/usr/bin/pgrep', ['-x', 'Google Chrome'], {
      stdio: 'ignore',
    });
    return result.status === 0;
  } catch {
    return false;
  }
}

export function shouldTakeOverLiveUserProfileLaunch(launchOptions = {}, chromeRunning = false) {
  return Boolean(chromeRunning) && launchOptions.kind === 'user_profile';
}

async function waitForChromeExit(timeoutMs = 8000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (!isChromeRunning()) {
      return true;
    }
    await wait(250);
  }
  return !isChromeRunning();
}

async function takeOverRunningChromeForManagedLaunch(launchOptions) {
  spawnSync('/usr/bin/osascript', ['-e', 'tell application "Google Chrome" to quit'], {
    stdio: 'ignore',
  });

  if (await waitForChromeExit(8000)) {
    return;
  }

  spawnSync('/usr/bin/pkill', ['-TERM', '-x', 'Google Chrome'], {
    stdio: 'ignore',
  });

  if (await waitForChromeExit(5000)) {
    return;
  }

  throw new SidecarError(
    'profile_in_use',
    `Chrome is already running with the '${launchOptions.display_name}' profile and could not be closed for managed relaunch.`
  );
}

export function buildChromeLaunchArgs(port, launchOptions) {
  const args = [
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${launchOptions.user_data_dir}`,
    '--no-first-run',
    '--no-default-browser-check',
  ];

  if (launchOptions.profile_directory) {
    args.push(`--profile-directory=${launchOptions.profile_directory}`);
  }

  return args;
}

async function launchChrome(port, launchOptions) {
  const chromeExecutable = resolveChromeExecutable();
  if (!chromeExecutable) {
    throw new SidecarError('chrome_not_found', 'Google Chrome was not found in /Applications.');
  }

  if (shouldTakeOverLiveUserProfileLaunch(launchOptions, isChromeRunning())) {
    await takeOverRunningChromeForManagedLaunch(launchOptions);
  }

  const userDataDir = launchOptions.user_data_dir;
  await fs.mkdir(userDataDir, { recursive: true });
  const args = buildChromeLaunchArgs(port, launchOptions);

  const child = spawn(
    chromeExecutable,
    args,
    {
      detached: true,
      stdio: 'ignore',
    }
  );
  child.unref();
  try {
    await waitForCDP(port);
  } catch (error) {
    terminateLaunchedChrome(child.pid ?? null);
    throw error;
  }
  return child.pid ?? null;
}

async function getPrimaryContext(browser) {
  const context = browser.contexts()[0];
  if (!context) {
    throw new SidecarError('execution_failed', 'Chrome did not expose a browser context over CDP.');
  }
  return context;
}

async function getTargetId(page) {
  const session = await page.context().newCDPSession(page);
  try {
    const { targetInfo } = await session.send('Target.getTargetInfo');
    return targetInfo?.targetId ?? null;
  } finally {
    try {
      await session.detach();
    } catch {}
  }
}

async function describePage(page) {
  return {
    title: await page.title().catch(() => ''),
    url: page.url() || 'about:blank',
    target_id: await getTargetId(page),
  };
}

async function readJsonFile(filePath) {
  try {
    const raw = await fs.readFile(filePath, 'utf8');
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function profileToolData(profile) {
  return {
    kind: profile.kind,
    display_name: profile.display_name,
    profile_directory: profile.profile_directory ?? null,
    user_data_dir: profile.user_data_dir,
    is_default: profile.is_default,
  };
}

async function discoverUserProfiles(userDataDir = defaultChromeUserDataDir()) {
  const localState = await readJsonFile(path.join(userDataDir, 'Local State'));
  const infoCache = localState?.profile?.info_cache ?? {};
  const order = Array.isArray(localState?.profile?.profiles_order) ? localState.profile.profiles_order : [];
  const profilesByDirectory = new Map();

  function addProfile(directory, info = {}) {
    if (!directory) {
      return;
    }
    const displayName = String(info.name ?? info.gaia_name ?? directory).trim() || directory;
    profilesByDirectory.set(directory, {
      kind: 'user_profile',
      display_name: displayName,
      profile_directory: directory,
      user_data_dir: userDataDir,
      is_default: directory === 'Default',
    });
  }

  for (const [directory, info] of Object.entries(infoCache)) {
    addProfile(directory, info);
  }

  for (const directory of order) {
    if (!profilesByDirectory.has(directory)) {
      addProfile(directory);
    }
  }

  try {
    const entries = await fs.readdir(userDataDir, { withFileTypes: true });
    for (const entry of entries) {
      if (!entry.isDirectory()) {
        continue;
      }
      const directory = entry.name;
      if (directory === 'Default' || directory.startsWith('Profile ') || directory.startsWith('Guest Profile')) {
        if (!profilesByDirectory.has(directory)) {
          addProfile(directory);
        }
      }
    }
  } catch {}

  return Array.from(profilesByDirectory.values()).sort((lhs, rhs) => {
    if (lhs.is_default !== rhs.is_default) {
      return lhs.is_default ? -1 : 1;
    }
    return lhs.display_name.localeCompare(rhs.display_name);
  });
}

async function discoverManagedProfiles() {
  const root = managedProfilesRoot();
  const profiles = [];

  try {
    const entries = await fs.readdir(root, { withFileTypes: true });
    for (const entry of entries) {
      if (!entry.isDirectory()) {
        continue;
      }
      profiles.push({
        kind: 'managed',
        display_name: entry.name,
        profile_directory: null,
        user_data_dir: path.join(root, entry.name),
        is_default: false,
      });
    }
  } catch {}

  return profiles.sort((lhs, rhs) => lhs.display_name.localeCompare(rhs.display_name));
}

async function discoverProfiles(options = {}) {
  const userDataDir = options.user_data_dir ?? defaultChromeUserDataDir();
  const profiles = [];
  profiles.push(...await discoverUserProfiles(userDataDir));
  profiles.push(...await discoverManagedProfiles());
  profiles.push({
    kind: 'managed',
    display_name: 'Managed Default',
    profile_directory: null,
    user_data_dir: defaultManagedUserDataDir(),
    is_default: true,
  });
  return profiles;
}

function scoreProfileMatch(profile, hint) {
  const normalizedHint = normalizeSearchText(hint);
  if (!normalizedHint) {
    return 0;
  }

  const texts = [
    profile.display_name,
    profile.profile_directory,
    path.basename(profile.user_data_dir),
  ]
    .map((value) => normalizeSearchText(value))
    .filter(Boolean);

  let score = 0;
  for (const text of texts) {
    if (text === normalizedHint) {
      score = Math.max(score, 100);
    } else if (text.startsWith(normalizedHint) || normalizedHint.startsWith(text)) {
      score = Math.max(score, 85);
    } else if (text.includes(normalizedHint) || normalizedHint.includes(text)) {
      score = Math.max(score, 72);
    }

    const hintTokens = normalizedHint.split(/\s+/).filter(Boolean);
    if (hintTokens.length > 0 && hintTokens.every((token) => text.includes(token))) {
      score = Math.max(score, 70 + Math.min(hintTokens.length, 5));
    }
  }

  if (profile.kind === 'user_profile') {
    score += 1;
  }
  return score;
}

function summarizeProfiles(profiles) {
  return profiles
    .slice(0, 5)
    .map((profile) => {
      const suffix = profile.profile_directory ? ` (${profile.profile_directory})` : '';
      return `${profile.display_name}${suffix}`;
    })
    .join(', ');
}

export function hasExplicitLaunchSelection(options = {}) {
  return Boolean(
    options.force_relaunch === true ||
    options.profile_mode ||
    options.profile_hint ||
    options.profile_name ||
    options.profile_directory ||
    options.user_data_dir
  );
}

export function currentLaunchProfileFromState(state = {}) {
  const profileMode = state.profile_mode === 'user_profile' ? 'user_profile' : 'managed';
  return {
    profile_mode: profileMode,
    display_name: state.profile_display_name
      ?? (profileMode === 'user_profile' ? state.profile_directory ?? 'Chrome Profile' : 'Managed Default'),
    user_data_dir: state.user_data_dir
      ?? (profileMode === 'user_profile' ? defaultChromeUserDataDir() : defaultManagedUserDataDir()),
    profile_directory: state.profile_directory ?? null,
    is_default: false,
    kind: profileMode,
  };
}

export function shouldReuseExistingSession(state = {}, options = {}) {
  return Boolean(state.debugging_port) && !hasExplicitLaunchSelection(options);
}

async function resolveLaunchProfile(state, options = {}) {
  const profileMode = options.profile_mode ?? 'auto';
  const profileHint = options.profile_hint ?? options.profile_name ?? null;
  const explicitUserDataDir = options.user_data_dir ?? null;
  const explicitProfileDirectory = options.profile_directory ?? (profileMode === 'user_profile' ? 'Default' : null);

  if (profileMode === 'managed') {
    const managedName = options.profile_name ?? options.profile_hint ?? 'Managed Default';
    const isDefaultManaged = !options.profile_name && !options.profile_hint;
    return {
      profile_mode: 'managed',
      display_name: managedName,
      user_data_dir: isDefaultManaged
        ? defaultManagedUserDataDir()
        : path.join(managedProfilesRoot(), sanitizeManagedProfileName(managedName)),
      profile_directory: null,
      is_default: isDefaultManaged,
      kind: 'managed',
    };
  }

  if (!profileHint && !explicitProfileDirectory) {
    return {
      profile_mode: 'managed',
      display_name: 'Managed Default',
      user_data_dir: defaultManagedUserDataDir(),
      profile_directory: null,
      is_default: true,
      kind: 'managed',
    };
  }

  const profiles = await discoverProfiles({ user_data_dir: explicitUserDataDir ?? undefined });
  let matches = profiles;

  if (profileMode === 'user_profile') {
    matches = matches.filter((profile) => profile.kind === 'user_profile');
  }

  if (explicitProfileDirectory) {
    const exact = matches.find((profile) => profile.profile_directory === explicitProfileDirectory);
    if (!exact) {
      throw new SidecarError(
        'profile_not_found',
        `No Chrome profile directory matched '${explicitProfileDirectory}'. Available profiles: ${summarizeProfiles(matches)}.`
      );
    }
    return {
      profile_mode: exact.kind,
      display_name: exact.display_name,
      user_data_dir: exact.user_data_dir,
      profile_directory: exact.profile_directory ?? null,
      is_default: exact.is_default,
      kind: exact.kind,
    };
  }

  const scored = matches
    .map((profile) => ({ profile, score: scoreProfileMatch(profile, profileHint) }))
    .filter((entry) => entry.score > 0)
    .sort((lhs, rhs) => rhs.score - lhs.score);

  if (scored.length === 0) {
    throw new SidecarError(
      'profile_not_found',
      `No Chrome profile matched '${profileHint}'. Inspect Chrome profiles via terminal or choose one of: ${summarizeProfiles(matches)}.`
    );
  }

  if (scored.length > 1 && scored[0].score - scored[1].score <= 3) {
    throw new SidecarError(
      'profile_ambiguous',
      `Profile hint '${profileHint}' matched multiple profiles: ${summarizeProfiles(scored.map((entry) => entry.profile))}.`
    );
  }

  const resolved = scored[0].profile;
  return {
    profile_mode: resolved.kind,
    display_name: resolved.display_name,
    user_data_dir: resolved.user_data_dir,
    profile_directory: resolved.profile_directory ?? null,
    is_default: resolved.is_default,
    kind: resolved.kind,
  };
}

function launchTargetsEqual(state, launchProfile) {
  return (
    state.user_data_dir === launchProfile.user_data_dir &&
    (state.profile_directory ?? null) === (launchProfile.profile_directory ?? null)
  );
}

function terminateManagedChrome(pid) {
  terminateLaunchedChrome(pid);
}

async function collectPages(browser) {
  const context = await getPrimaryContext(browser);
  const pages = context.pages();
  const described = [];
  for (let index = 0; index < pages.length; index += 1) {
    const page = pages[index];
    described.push({
      index,
      page,
      info: await describePage(page),
    });
  }
  return described;
}

async function resolveSelectedPage(browser, state, createIfMissing = true) {
  const pages = await collectPages(browser);

  let selected = null;
  if (state.selected_target_id) {
    selected = pages.find((entry) => entry.info.target_id === state.selected_target_id) ?? null;
  }
  if (!selected && pages.length > 0) {
    selected = pages[0];
  }

  if (!selected && createIfMissing) {
    const context = await getPrimaryContext(browser);
    const page = await context.newPage();
    selected = {
      index: context.pages().length - 1,
      page,
      info: await describePage(page),
    };
  }

  if (!selected) {
    throw new SidecarError('execution_failed', 'No Chrome tab is available.');
  }

  await selected.page.bringToFront().catch(() => {});
  state.selected_target_id = selected.info.target_id;
  return selected;
}

function buildLocator(page, query) {
  if (!query) {
    throw new SidecarError('missing_selector', 'Browser action requires an element selector.');
  }

  if (query.locator) {
    return page.locator(query.locator);
  }
  if (query.css) {
    return page.locator(query.css);
  }
  if (query.role) {
    const options = {};
    if (query.name) {
      options.name = query.name;
    }
    return page.getByRole(query.role, options);
  }
  if (query.test_id) {
    return page.getByTestId(query.test_id);
  }
  if (query.label) {
    return page.getByLabel(query.label);
  }
  if (query.placeholder) {
    return page.getByPlaceholder(query.placeholder);
  }
  if (query.text) {
    return page.getByText(query.text);
  }
  if (query.name) {
    return page.getByText(query.name);
  }

  throw new SidecarError('missing_selector', 'Browser action requires a supported selector.');
}

async function ensureBrowser(state, options = {}) {
  const reuseExistingSession = shouldReuseExistingSession(state, options);
  const launchProfile = reuseExistingSession
    ? currentLaunchProfileFromState(state)
    : await resolveLaunchProfile(state, options);
  const nextState = reuseExistingSession
    ? {
        debugging_port: state.debugging_port ?? null,
        selected_target_id: state.selected_target_id ?? null,
        managed_chrome_pid: state.managed_chrome_pid ?? null,
        profile_mode: state.profile_mode ?? launchProfile.profile_mode,
        profile_directory: state.profile_directory ?? launchProfile.profile_directory ?? null,
        user_data_dir: state.user_data_dir ?? launchProfile.user_data_dir,
        profile_display_name: state.profile_display_name ?? launchProfile.display_name,
      }
    : {
        debugging_port: state.debugging_port ?? null,
        selected_target_id: state.selected_target_id ?? null,
        managed_chrome_pid: state.managed_chrome_pid ?? null,
        profile_mode: launchProfile.profile_mode,
        profile_directory: launchProfile.profile_directory,
        user_data_dir: launchProfile.user_data_dir,
        profile_display_name: launchProfile.display_name,
      };

  const forceRelaunch = options.force_relaunch === true;
  const needsNewTarget = reuseExistingSession ? false : forceRelaunch || !launchTargetsEqual(state, launchProfile);

  if (nextState.managed_chrome_pid && needsNewTarget) {
    terminateManagedChrome(nextState.managed_chrome_pid);
    nextState.managed_chrome_pid = null;
    nextState.debugging_port = null;
    nextState.selected_target_id = null;
  } else if (!nextState.managed_chrome_pid && state.debugging_port && needsNewTarget) {
    throw new SidecarError(
      'profile_switch_requires_restart',
      'Chrome is already attached with a different profile. Start the run with the chosen profile before webpage actions begin.'
    );
  }

  let launched = false;
  if (!nextState.debugging_port) {
    nextState.debugging_port = await findAvailablePort();
  }

  try {
    await waitForCDP(nextState.debugging_port, 1000);
  } catch {
    nextState.managed_chrome_pid = await launchChrome(nextState.debugging_port, launchProfile);
    launched = true;
  }

  const browser = await chromium.connectOverCDP(`http://127.0.0.1:${nextState.debugging_port}`);
  return { browser, state: nextState, launched, launchProfile };
}

function normalizeTimeoutSeconds(value, fallbackSeconds = 10) {
  const numeric = Number.isFinite(value) ? value : fallbackSeconds;
  return Math.max(0.1, Math.min(60, numeric));
}

async function handleCommand(command, state, payload) {
  const { browser, state: nextState, launched, launchProfile } = await ensureBrowser(state, payload.options ?? {});
  try {
    switch (command) {
      case 'attach_or_launch_chrome': {
        const current = await resolveSelectedPage(browser, nextState, true);
        const tabs = await collectPages(browser);
        return {
          message: launched
            ? `Launched Chrome and attached over CDP using ${launchProfile.display_name}.`
            : `Attached to Chrome over CDP using ${launchProfile.display_name}.`,
          data: {
            debugging_port: nextState.debugging_port,
            launched,
            tab_count: tabs.length,
            current_page: await describePage(current.page),
            profile: profileToolData(launchProfile),
          },
          state: nextState,
        };
      }
      case 'list_tabs': {
        const tabs = await collectPages(browser);
        return {
          message: `Listed ${tabs.length} Chrome tab(s).`,
          data: tabs.map((entry) => ({
            index: entry.index,
            title: entry.info.title,
            url: entry.info.url,
            target_id: entry.info.target_id,
            is_selected: entry.info.target_id === nextState.selected_target_id,
          })),
          state: nextState,
        };
      }
      case 'select_tab': {
        const tabs = await collectPages(browser);
        const selection = payload.selection ?? {};
        let selected = null;
        if (Number.isInteger(selection.index)) {
          selected = tabs.find((entry) => entry.index === selection.index) ?? null;
        } else if (selection.title_contains) {
          selected = tabs.find((entry) => entry.info.title.includes(selection.title_contains)) ?? null;
        } else if (selection.url_contains) {
          selected = tabs.find((entry) => entry.info.url.includes(selection.url_contains)) ?? null;
        } else {
          throw new SidecarError('execution_failed', 'select_tab requires index, title_contains, or url_contains.');
        }

        if (!selected) {
          throw new SidecarError('execution_failed', 'No Chrome tab matched the requested selection.');
        }
        await selected.page.bringToFront().catch(() => {});
        nextState.selected_target_id = selected.info.target_id;
        return {
          message: `Selected tab ${selected.index}.`,
          data: {
            index: selected.index,
            title: selected.info.title,
            url: selected.info.url,
            target_id: selected.info.target_id,
            is_selected: true,
          },
          state: nextState,
        };
      }
      case 'goto': {
        if (!payload.url) {
          throw new SidecarError('invalid_url', 'goto requires a URL.');
        }
        const current = await resolveSelectedPage(browser, nextState, true);
        await current.page.goto(payload.url, { waitUntil: 'domcontentloaded' });
        const page = await describePage(current.page);
        nextState.selected_target_id = page.target_id;
        return {
          message: `Navigated to ${page.url}.`,
          data: page,
          state: nextState,
        };
      }
      case 'click': {
        const current = await resolveSelectedPage(browser, nextState, true);
        const locator = buildLocator(current.page, payload.query);
        await locator.first().click({ timeout: 10000 });
        const page = await describePage(current.page);
        nextState.selected_target_id = page.target_id;
        return {
          message: `Clicked ${payload.query?.role ?? payload.query?.text ?? payload.query?.css ?? 'browser element'}.`,
          data: page,
          state: nextState,
        };
      }
      case 'type': {
        if (!payload.text) {
          throw new SidecarError('missing_value', 'type requires text.');
        }
        const current = await resolveSelectedPage(browser, nextState, true);
        const locator = buildLocator(current.page, payload.query);
        await locator.first().fill(payload.text, { timeout: 10000 });
        if (payload.press_enter) {
          await current.page.keyboard.press('Enter');
        }
        const page = await describePage(current.page);
        nextState.selected_target_id = page.target_id;
        return {
          message: `Typed into ${payload.query?.role ?? payload.query?.text ?? payload.query?.css ?? 'browser field'}.`,
          data: page,
          state: nextState,
        };
      }
      case 'press': {
        if (!payload.key) {
          throw new SidecarError('missing_value', 'press requires a key.');
        }
        const current = await resolveSelectedPage(browser, nextState, true);
        await current.page.keyboard.press(payload.key);
        const page = await describePage(current.page);
        nextState.selected_target_id = page.target_id;
        return {
          message: `Pressed ${payload.key}.`,
          data: page,
          state: nextState,
        };
      }
      case 'wait_for': {
        const current = await resolveSelectedPage(browser, nextState, true);
        const condition = payload.condition ?? {};
        const timeoutMs = normalizeTimeoutSeconds(condition.timeout_seconds) * 1000;

        if (condition.url_contains) {
          await current.page.waitForFunction((needle) => window.location.href.includes(needle), condition.url_contains, { timeout: timeoutMs });
        } else if (condition.title_contains) {
          await current.page.waitForFunction((needle) => document.title.includes(needle), condition.title_contains, { timeout: timeoutMs });
        } else if (condition.text) {
          await current.page.getByText(condition.text).first().waitFor({ state: 'visible', timeout: timeoutMs });
        } else if (condition.role) {
          await buildLocator(current.page, { role: condition.role, name: condition.name ?? null }).first().waitFor({ state: 'visible', timeout: timeoutMs });
        } else {
          throw new SidecarError('execution_failed', 'wait_for requires a supported condition.');
        }

        const page = await describePage(current.page);
        nextState.selected_target_id = page.target_id;
        return {
          message: `Waited for ${condition.url_contains || condition.title_contains || condition.text || condition.role}.`,
          data: {
            condition_description: condition.url_contains
              ? `URL contains '${condition.url_contains}'`
              : condition.title_contains
                ? `Title contains '${condition.title_contains}'`
                : condition.text
                  ? `Text '${condition.text}' is visible`
                  : condition.name
                    ? `Role '${condition.role}' named '${condition.name}' is visible`
                    : `Role '${condition.role}' is visible`,
            page,
          },
          state: nextState,
        };
      }
      case 'snapshot': {
        const current = await resolveSelectedPage(browser, nextState, true);
        const rawText = await current.page.locator('body').innerText({ timeout: 2000 }).catch(() => '');
        const textExcerpt = rawText.replace(/\s+/g, ' ').trim().slice(0, 2000);
        const page = await describePage(current.page);
        nextState.selected_target_id = page.target_id;
        return {
          message: 'Captured browser DOM snapshot.',
          data: {
            page,
            text_excerpt: textExcerpt,
          },
          state: nextState,
        };
      }
      case 'get_url': {
        const current = await resolveSelectedPage(browser, nextState, true);
        const page = await describePage(current.page);
        nextState.selected_target_id = page.target_id;
        return {
          message: `Current URL is ${page.url}.`,
          data: page.url,
          state: nextState,
        };
      }
      case 'get_title': {
        const current = await resolveSelectedPage(browser, nextState, true);
        const page = await describePage(current.page);
        nextState.selected_target_id = page.target_id;
        return {
          message: `Current title is ${page.title}.`,
          data: page.title,
          state: nextState,
        };
      }
      default:
        throw new SidecarError('execution_failed', `Unsupported browser command '${command}'.`);
    }
  } finally {
    await browser.close().catch(() => {});
  }
}

async function main() {
  try {
    const rawInput = await readStdin();
    if (!rawInput.trim()) {
      throw new SidecarError('execution_failed', 'Browser sidecar did not receive a request payload.');
    }

    const request = JSON.parse(rawInput);
    const command = request.command;
    const state = request.state ?? {};
    const payload = request.payload ?? {};

    if (!command) {
      throw new SidecarError('execution_failed', 'Browser sidecar request is missing a command.');
    }

    const result = await handleCommand(command, state, payload);
    process.stdout.write(JSON.stringify({
      ok: true,
      message: result.message,
      data: result.data,
      state: result.state,
    }));
  } catch (error) {
    process.stdout.write(JSON.stringify({
      ok: false,
      message: error instanceof Error ? error.message : String(error),
      error: error instanceof SidecarError ? error.code : 'execution_failed',
    }));
    process.exitCode = 0;
  }
}

const isMainModule = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isMainModule) {
  await main();
}
