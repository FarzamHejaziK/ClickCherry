# Visual Grounding Investigation

## Purpose

This document captures the visual-grounding issue discovered in the OpenAI desktop execution loop, along with the debugging and replay workflow built to investigate it using real app runs.

This is a dedicated investigation note only. It does not replace the ongoing execution queue in `.docs/next_steps.md` or the issue tracker in `.docs/open_issues.md`.

## Problem Summary

The execution agent could often see the desktop image at a coarse level, but still made incorrect fine-grained visual claims about Dock icons and cursor placement outcomes.

Observed failure pattern:

- The model correctly recognized broad scene elements:
  - desktop wallpaper
  - Finder window
  - Dock visible at the bottom
- The model often failed at fine-grained Dock grounding:
  - claimed the cursor was already over Google Chrome when it was not
  - claimed success without performing the required move
  - selected the wrong icon inside a correct Dock crop

Typical false-success example:

- Task goal: hover over Google Chrome in Dock
- Actual screenshot: cursor in Finder window or over another Dock app
- Model response: `SUCCESS` claiming Chrome hover was complete

## Root-Cause Areas Investigated

The debugging work showed that the problem was not just one thing.

### 1. Screenshot transport / rendering bugs

Several image-path bugs had to be fixed first because they confounded model evaluation:

- transformed screenshots were sometimes upside down
- crop Y-axis mapping returned the wrong strip of the screen
- cursor overlay was initially drawn in the wrong visual location
- the first screenshot path was inconsistent with later decorated screenshots

These were implementation bugs in the screenshot-transform and capture pipeline, not model behavior.

### 2. Prompt-conditioned hallucination

After screenshot transport was fixed, the model could still hallucinate target identity.

Key finding:

- A simple raw vision prompt outside the app could correctly describe the cursor location in the screenshot.
- The same screenshot, when combined with the execution prompt and task goal, could produce a false claim that the cursor was already over Chrome in the Dock.

This indicates task-conditioned hallucination:

- the model over-relied on the task goal
- the task text acted like evidence
- visual grounding lost to goal pressure

### 3. Fine-grained Dock icon identification

Prompt changes improved first-step behavior:

- from full-screen false `SUCCESS`
- to requesting a Dock crop first

But even with correct Dock crops, the model could still misidentify which icon inside the crop was Chrome.

## Debugging Infrastructure Added

To make this investigation reproducible, the runtime was extended so each run persists the actual model inputs and outputs needed for replay.

### Persisted screenshots

Each run now writes the exact outbound images sent to the LLM into a run-specific screenshots folder.

Pattern:

- `agent-run-<timestamp>-<id>.json`
- `agent-run-<timestamp>-<id>-screenshots/`

Typical files:

- `001-initial_prompt_image.png`
- `002-action_screenshot.png`
- `003-post_action_snapshot.png`
- `manifest.json`

Important property:

- these are the exact image bytes sent to the model, not just raw local captures

### Persisted raw LLM exchanges

Each run now writes raw request/response bodies for every turn.

Pattern:

- `agent-run-<timestamp>-<id>-llm-exchanges/`

Typical files:

- `001-request.json`
- `001-response.json`
- `002-request.json`
- `002-response.json`
- `manifest.json`

Important property:

- these files make it possible to replay a real app turn outside the app loop
- they include the exact prompt text, image data URLs, tool schema, and raw model responses

### Prompt/version logging

Each run logs:

- prompt name
- prompt version
- model
- reasoning settings
- resolved prompt file path

This avoids ambiguity about which prompt variant was active during a bad run.

## Replay-Based Test Method

The main debugging method developed during this investigation is:

1. Run the task in the real app.
2. Collect the exact screenshot files from the run’s `-screenshots` folder.
3. Collect the exact request/response JSON from the run’s `-llm-exchanges` folder.
4. Replay the same request outside the app against the Responses API.
5. Compare:
   - live app behavior
   - replayed model behavior
   - visible evidence in the saved screenshots
6. Modify only one variable at a time:
   - prompt wording
   - prompt structure
   - reasoning settings
   - screenshot context metadata

This replay loop is critical because it separates:

- app/runtime bugs
- prompt effects
- model behavior variability

## What the Replay Method Proved

The replay method established several important facts.

### The model did receive the image

Using the exact saved screenshot outside the app, the raw model could describe:

- the Finder window
- the general cursor region
- the Dock

This ruled out the hypothesis that the model was receiving no image at all.

### The bad behavior was reproducible from the real request

Replaying the exact saved request body reproduced the same bad first-turn false `SUCCESS` behavior that appeared in the live app.

This showed the issue was not just app-loop randomness.

### Strong prompt structure helped more than softer wording

Soft prompt advice like “prefer crop first” was not enough.

Harder structural rules worked better, such as:

- if the task is not visibly complete, call a tool directly
- for Dock-targeting tasks from a full-screen screenshot, the first action must be a Dock crop
- do not return `SUCCESS` unless the latest screenshot proves completion

### Prompt-only tuning was not sufficient

Prompt changes improved behavior from:

- hallucinated immediate `SUCCESS`

to:

- request Dock crop first

But prompt tuning alone did not fully solve the deeper fine-grained icon-identification problem.

## Prompt Experimentation Strategy

The effective prompt-testing workflow became:

1. Use a real failed run as the seed artifact set.
2. Replay turn 1 exactly from `001-request.json`.
3. Swap only the prompt body.
4. Keep the same:
   - screenshot
   - tool schema
   - model
   - reasoning settings
5. Evaluate:
   - did the model still return false `SUCCESS`?
   - did it request a Dock crop?
   - did it later select a plausible mouse target in the crop?

This is the preferred method for prompt tuning in this area because it keeps the experiment grounded in an actual production failure.

## Runtime Changes That Improved Debugging

The investigation led to several concrete runtime improvements:

- versioned execution prompts under `Prompts/execution_agent_openai/`
- top-level prompt selector config
- exact prompt/model/version logging
- exact screenshot persistence
- exact request/response persistence
- image-local cursor and corner coordinates injected into prompt context
- explicit screenshot coordinate-system text:
  - origin is top-left
  - x increases right
  - y increases downward

These changes make future visual-grounding failures easier to reproduce and compare.

## Current Best-Known Interpretation

The current best reading of the issue is:

- coarse image visibility is mostly working
- prompt-conditioned hallucination is real
- Dock crop-first behavior is a meaningful improvement
- fine-grained icon selection inside the Dock crop remains unreliable

So the investigation moved the issue from:

- “is the model even seeing the image?”

to:

- “how do we make fine-grained cursor/target grounding robust after the crop?”

## Recommended Ongoing Workflow

For future work on this issue:

1. Always debug from persisted run artifacts first.
2. Replay the exact request before changing the prompt.
3. Distinguish:
   - screenshot/render bugs
   - prompt-induced behavior
   - model visual grounding limits
4. Prefer evidence-preserving instrumentation over speculative changes.
5. Treat prompt tuning and code guardrails as complementary, not mutually exclusive.

## Manual Validation Checklist

When changing this area, validate all of the following:

- the first screenshot sent to the LLM matches the logged screenshot
- the cursor overlay visually matches the cursor location
- crop screenshots show the intended region
- the prompt version logged in the run matches the expected active version
- `-llm-exchanges` contains request and response files for every turn
- replaying `001-request.json` produces behavior consistent with the live run

## Notes

- This document intentionally focuses on the investigation method and findings.
- It does not serve as the canonical queue, issue tracker, or worklog.
- Related operational context may also live in:
  - `.docs/open_issues.md`
  - `.docs/testing.md`
  - `.docs/worklog.md`
