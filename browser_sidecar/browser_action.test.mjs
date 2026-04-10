import test from 'node:test';
import assert from 'node:assert/strict';

import {
  buildChromeLaunchArgs,
  currentLaunchProfileFromState,
  hasExplicitLaunchSelection,
  shouldTakeOverLiveUserProfileLaunch,
  shouldReuseExistingSession,
} from './browser_action.mjs';

test('reuses an attached browser session when no new launch selection is provided', () => {
  const state = {
    debugging_port: 61234,
    user_data_dir: '/tmp/clickcherry-profile',
    profile_display_name: 'Farzam profile',
    profile_mode: 'managed',
  };

  assert.equal(shouldReuseExistingSession(state, {}), true);
  assert.deepEqual(currentLaunchProfileFromState(state), {
    profile_mode: 'managed',
    display_name: 'Farzam profile',
    user_data_dir: '/tmp/clickcherry-profile',
    profile_directory: null,
    is_default: false,
    kind: 'managed',
  });
});

test('does not reuse an attached session when a new profile hint is requested', () => {
  const state = { debugging_port: 61234 };

  assert.equal(hasExplicitLaunchSelection({ profile_hint: 'work chrome' }), true);
  assert.equal(shouldReuseExistingSession(state, { profile_hint: 'work chrome' }), false);
});

test('does not reuse an attached session when relaunch is explicitly requested', () => {
  const state = { debugging_port: 61234 };

  assert.equal(hasExplicitLaunchSelection({ force_relaunch: true }), true);
  assert.equal(shouldReuseExistingSession(state, { force_relaunch: true }), false);
});

test('reconstructs user-profile launch state without drifting to managed defaults', () => {
  const state = {
    debugging_port: 61234,
    profile_mode: 'user_profile',
    profile_display_name: 'Farzam Hejazi',
    profile_directory: 'Default',
    user_data_dir: '/Users/ferzamh/Library/Application Support/Google/Chrome',
  };

  assert.deepEqual(currentLaunchProfileFromState(state), {
    profile_mode: 'user_profile',
    display_name: 'Farzam Hejazi',
    user_data_dir: '/Users/ferzamh/Library/Application Support/Google/Chrome',
    profile_directory: 'Default',
    is_default: false,
    kind: 'user_profile',
  });
});

test('chrome launch args do not force an about blank tab', () => {
  const args = buildChromeLaunchArgs(61234, {
    kind: 'managed',
    user_data_dir: '/tmp/clickcherry-profile',
    profile_directory: null,
  });

  assert.deepEqual(args, [
    '--remote-debugging-port=61234',
    '--user-data-dir=/tmp/clickcherry-profile',
    '--no-first-run',
    '--no-default-browser-check',
  ]);
  assert.equal(args.includes('about:blank'), false);
});

test('live user-profile launches trigger managed takeover behavior', () => {
  assert.equal(shouldTakeOverLiveUserProfileLaunch({ kind: 'user_profile' }, true), true);
  assert.equal(shouldTakeOverLiveUserProfileLaunch({ kind: 'managed' }, true), false);
  assert.equal(shouldTakeOverLiveUserProfileLaunch({ kind: 'user_profile' }, false), false);
});
