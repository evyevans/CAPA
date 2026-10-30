# CAPA mobile transition — implementation ledger

Approved goal: delegate to the user's Hermes from iPhone, remain available until
disabled, and receive useful spoken updates while locked where Apple's supported
Push to Talk path permits. Standard notifications and recovery on reopen are
required fallbacks. Microphone capture is deliberate, never ambient listening.

## Decisions

- Work in place: this directory has no `.git` metadata; do not initialize or move it.
- Keep the Vite showcase intact. Native companion code lives in `bridge/`, `ios/` and `macos/`.
- Use SwiftUI and Apple's native frameworks; use a host-side Python/FastAPI
  service with SQLite persistence, httpx and token-authenticated APNs.
- Use an API-owned Hermes session per workspace shared by explicitly linked devices; do not attach to Telegram
  sessions. Continue the same session for follow-up questions.
- Read live capabilities before starting work. A lost submission response is
  retried using the same durable idempotency key, within Hermes's retention
  window; never retry an ambiguous submission after that window automatically.
- Pair through a short-lived code issued locally on the host. CAPA device
  credentials are independent of Hermes and Apple credentials.
- Availability controls speech eligibility; standard notifications still report
  task outcomes when speech is unavailable. Disabling it also invalidates the
  stored PTT channel token. Revocation disables all device access and delivery.
- Prefer on-device speech recognition. Explicitly configured host speech can use
  the user's Hermes providers; no new provider account is silently provisioned.
- Full Xcode, signing, an Apple Developer team, APNs credentials, a reachable
  Hermes API and physical iPhone are external prerequisites. Do not alter the
  user's running Hermes configuration or install services automatically.

## Sequence and acceptance

1. Durable bridge: pairing, revocation, idempotent submission, run reconciliation,
   pending controls, delivery events and acknowledgments; tested at HTTP boundaries.
2. Push delivery: separate task completion from notification delivery, retry
   failures and keep results recoverable; test auth, opt-out and APNs payloads.
3. Native app: pairing, widget entry, capture, task/result UI, deliberate controls,
   PTT session, interruption handling and notification fallback.
4. Evidence and operations: install instructions, REA ledger, device test script,
   automated checks and an explicit list of unverified device behavior.

## Progress

- Context and approved design reviewed. No product code changed in the showcase.
- Baseline: no bridge/native app or tests existed; full Xcode is absent.
- Bridge implemented with authenticated workspace scope, durable idempotency,
  atomic task/result-event snapshots, canonical controls, persisted playback
  receipts, APNs backoff/fallback and opt-in Hermes speech with cached briefs.
- Native SwiftUI source, WidgetKit shortcut, project/scheme, Keychain pairing,
  recording recovery, durable reply intent, PTT lifecycle and notification
  handling added. No full iOS build or physical-device claim is made.
- Ruling: the actual v0.22.5 capability table lacks `run_clarify` although the
  canonical route exists. Permit it only for a live clarify prompt with the
  canonical control feature, and retain generation checks at Hermes.
- Ruling: terminal task state and its recoverable update commit in one SQLite
  transaction; a simulated event-write failure must leave the task pollable.
- Review: a fresh reviewer identified native imports, missing approval details,
  clarification capability mismatch and audio delegate identity races. Those
  findings were corrected; review ended before a complete independent pass.
  Remaining verification is explicit in the device acceptance procedure.
- REA findings and limitations recorded in `wispr-findings.md`; no Flow code or
  credential was incorporated. No later REA run was started after incomplete cleanup.
- Setup instructions and repeatable checks added. Distribution assets, Apple
  provisioning and actual iOS background behavior remain external validation.
- Automated verification: bridge API/persistence/push/speech tests pass; portable
  Swift delivery, approval and saved-reply checks pass; native Swift syntax and
  project/plist validation pass. See the check script for fresh results.
- Recognition is bounded and cancellable. iOS background-time expiration leaves
  the recording and any ambiguous submission/reply identity recoverable.


## Continuity revision — 2026-10-24

Applied the Elon Frame v3 skill to focus this iteration on reliable dispatch and
recoverable outcomes. See `continuity-design.md`: notifications default, optional
speech, trusted-device workspace pairing, read-only discovery instead of a second
OAuth catalog. The first customer hypothesis is existing Hermes users; demand is
not established by implementing these features.

- Transactional, repeatable migration gives each legacy device an isolated
  workspace while preserving its original session. Invitations explicitly link
  new devices. Shared task reads, controls, retries, metrics and results are scoped
  to that workspace; credentials and push tokens remain per-device.
- Preferred destination and exclusive playback leases prevent concurrent speech.
  Receipt tokens survive reconnect. Preference switches reroute pending delivery,
  and revocation preserves active work for other trusted devices.
- Shared Apple network/Keychain/workspace models support the iPhone settings and
  a native Mac hub, menu entry, deliberate recorder and movable floating bar.
- Independent review found restored PTT intent, in-flight delivery handoff,
  revocation during playback, and delayed speech/capture races. Corrections and
  bridge regressions cover those cases; hardware behavior still needs validation.
- Mac local packaging supports a current-architecture ad-hoc-signed preview.
  Public release needs Developer ID/notarization and device acceptance. iOS still
  needs full Xcode, provisioning and physical testing. Android/Windows are API
  targets, not delivered clients.
