---
description: Decision record for client-side LLM transport hardening and user-facing provider error handling.
last_updated: 2026-04-01
---

# LLM Calls Hardening

## Context

- Ongoing issue: intermittent HTTPS/TLS failures during LLM calls, most visible with VPN enabled.
- Prior evidence in open issues: `NSURLErrorDomain -1200` and `_kCFStreamErrorCodeKey=-9820` (`errSSLPeerBadRecordMac`) in Anthropic-era transport traces.
- Current user goal: improve robustness of LLM calls and make critical provider failures actionable in-app.
- Current execution-loop goal: reduce per-turn transport overhead on the multi-turn OpenAI Responses runner while preserving a safe HTTP recovery path.

## Constraints

- No server-side proxy/gateway is allowed for this phase.
- Keep solution fully client-side in the macOS app.
- Support provider-specific handling while preserving a unified user experience.

## Observed Runtime Pattern

- Failures are more common on later calls in sequential tool loops (3rd/4th call pattern), consistent with pooled HTTPS connection reuse under unstable VPN/proxy paths.
- Existing mitigation had retries, but user-facing remediation guidance was inconsistent and mostly raw message text.

## Decisions

1. Transport policy: **new `URLSession` per LLM request call** (client-side only).
   - Applied to OpenAI execution requests and Gemini extraction requests.
   - Goal: avoid stale/poisoned connection reuse across request turns.

2. OpenAI execution transport policy: **prefer Responses WebSocket per execution run, with HTTP fallback**.
   - Applied only to the OpenAI execution runner.
   - The WebSocket path reuses one connection across turns and sends `response.create` events with the same request semantics as the HTTP `/v1/responses` path.
   - Default rollout mode is `webSocketPreferred`; HTTP remains available as both an explicit mode and a recovery path.
   - Fallback rules:
     - initial socket-connect failure -> fall back to HTTP for the rest of the run
     - `previous_response_not_found` -> fall back to HTTP for the current run
     - `websocket_connection_limit_reached` -> open a fresh socket and retry the turn once
   - Safety rule:
     - partial socket output must never trigger local tool execution; only a fully normalized response can advance the run loop

3. User-facing LLM error taxonomy (explicitly handled):
   - `invalid_credentials`
   - `rate_limited`
   - `quota_or_budget_exhausted`
   - `billing_or_tier_not_enabled`

4. Provider-specific classification is normalized into one model:
   - New shared type: `LLMUserFacingIssue` + `LLMUserFacingIssueKind`.
   - OpenAI and Gemini each map HTTP status + provider payload fields into this model.

5. UX contract for these four error classes:
   - Render as a dedicated canvas card (`LLMUserFacingIssueCanvasView`) instead of plain red text.
   - Include actionable CTAs:
     - `Open Settings` for credential/tier setup paths.
     - `Open Billing` / provider console links where relevant.
   - Keep technical diagnostics visible in-card (`HTTP`, provider code, request id/message when available).

6. Surface integration:
   - Run-task flow (Task Detail page): show issue canvas when active.
   - Recording extraction flow (Recording Finished dialog): show issue canvas when active.
   - Generic non-classified failures continue using existing error text path.

## Error Mapping Summary

### OpenAI

- `401` or invalid key signals -> `invalid_credentials`
- `429` + quota/budget/billing-limit signals -> `quota_or_budget_exhausted`
- `429` (non-quota) -> `rate_limited`
- `400/403` + billing/tier/payment/verification signals -> `billing_or_tier_not_enabled`

### Gemini

- `403` / `PERMISSION_DENIED` / invalid-key signals -> `invalid_credentials`
- `429` / `RESOURCE_EXHAUSTED` + quota/budget/billing tokens -> `quota_or_budget_exhausted`
- `429` / `RESOURCE_EXHAUSTED` (non-quota) -> `rate_limited`
- `400/403` + `FAILED_PRECONDITION` / billing/tier-not-enabled tokens -> `billing_or_tier_not_enabled`

## Non-Goals (this iteration)

- No backend proxy/service mesh.
- No provider failover routing.
- No redesign of all existing error surfaces beyond the LLM-focused flows above.

## Validation Plan

- Automated:
  - Build passes for app target.
  - OpenAI runner tests include user-facing classification checks.
  - OpenAI runner tests include WebSocket transport/fallback coverage.
  - Gemini client tests include user-facing classification checks.
- Manual (pending local runtime verification):
  - Inspect new canvas previews for all four error classes.
  - Trigger representative provider failures and verify CTA behavior (`Open Settings`, `Open Billing`).
  - Compare one safe multi-turn OpenAI run in HTTP mode vs `webSocketPreferred` mode and verify fallback/logging behavior.
