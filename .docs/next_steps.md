---
description: Short, continuously updated plan of the immediate next implementation steps and priorities
---

# Next Steps

1. Step: Step 4 execution agent (active, highest priority).
2. Why now: User explicitly prioritized execution-agent delivery as the most important milestone.
3. Code tasks:
   - Build first concrete runner implementing `AutomationEngine`.
   - Add `HEARTBEAT.md` execution-plan parser and map to desktop action intents.
   - Integrate Anthropic computer-use path with `claude-opus-4-6`.
   - Execute app-agnostic desktop actions (open app, click, type, shortcuts, scroll/drag/wait).
   - Append unresolved runtime questions into `HEARTBEAT.md` `## Questions` on ambiguity/failure.
   - Implement current baseline policies:
     - allow run with unresolved questions and ask clarifications from run report.
     - zero retries before generating clarification questions.
     - no per-step confirmation gates and no app allowlist/blocklist.
     - failure-only screenshot artifacts and no max step/runtime limits.
   - Keep provisional choices tracked in `.docs/revisits.md`.
   - Persist run artifacts under `runs/` and surface run status in task detail.
4. Automated tests:
   - Execution-plan parser tests.
   - Automation-engine outcome tests (`success`/`needs clarification`/`failed`).
   - Markdown runtime-question append/dedup tests.
   - State-store tests for run-trigger and heartbeat update persistence.
5. Manual tests:
   - Run at least one real task and verify desktop actions occur.
   - Validate ambiguity/failure writes blocking questions to `HEARTBEAT.md`.
   - Answer generated question and rerun to confirm progression.
6. Exit criteria: First execution-agent baseline can run a task, generate blocking questions when needed, and persist outcomes.

1. Step: Keep `OI-2026-02-08-003` open (deferred clarification-panel local verification).
2. Why now: Clarification UI verification is deferred while execution-agent milestone is in progress.
3. Code tasks:
   - Keep clarification parser/apply behavior unchanged during Step 4 execution-agent work.
   - Preserve regression tests for question parsing and markdown apply.
4. Automated tests:
   - Keep `HeartbeatQuestionService` tests passing.
   - Keep `MainShellStateStore` clarification persistence tests passing.
5. Manual tests:
   - Deferred by decision; do not run now.
6. Exit criteria: Issue remains tracked until deferred local verification is executed and confirmed.

1. Step: Defer `OI-2026-02-07-001` microphone selection bug (backlog).
2. Why now: Mitigation remains available via `System Default Microphone`; execution-agent baseline has higher delivery priority.
3. Code tasks:
   - Keep current mitigation and fallback messaging unchanged.
   - Resume mic diagnostics after Step 4 execution-agent baseline lands.
4. Automated tests: N/A (deferred backlog item).
5. Manual tests: N/A (deferred backlog item).
6. Exit criteria: Issue remains tracked in `.docs/open_issues.md` with mitigation and clear next action.

1. Step: Step 5 scheduling while app is open (next, after Step 4 baseline).
2. Why now: Scheduling depends on a reliable execution-agent run path.
3. Code tasks:
   - Add natural-language schedule input and deterministic validation.
   - Persist schedule config per task and show `next run` and `last run` in task detail.
   - Wire scheduler trigger path while app is open and write run history updates.
4. Automated tests:
   - Schedule parser validation tests.
   - Scheduler trigger/deduplication tests.
   - State-store tests for schedule persistence and status projection (`next run`/`last run`).
5. Manual tests:
   - Configure short interval and verify scheduled run triggers while app is open.
   - Restart app and verify schedule reload behavior.
   - Confirm task detail status updates after at least one scheduled fire.
6. Exit criteria: At least one task runs successfully on schedule with correct status updates.
