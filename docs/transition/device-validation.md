# Physical iPhone acceptance procedure

Status: **not run**. This is the release gate for automatic background speech,
not an assertion that iOS grants arbitrary agent background execution.

## Prepare

- Full Xcode and iOS SDK; CAPA signed for a physical iPhone under the intended
  team, bundle ID and Push to Talk provisioning.
- An existing Hermes profile with its API server enabled, canonical controls and
  a harmless research toolset. Record the Hermes commit/version and capabilities.
- CAPA bridge running as one process, reachable over trusted HTTPS from both
  Wi-Fi and cellular/private VPN. Pair using a new one-use code.
- Match development/production APNs configuration to the installed build. Enable
  notifications and the explicit **Reply delivery → Spoken** setting, select this iPhone, and enable incoming voice in its own section. Complete the
  microphone and speech permission prompts while the app is in the foreground.
- First test device-native speech, then repeat with the optional Hermes host
  speech configuration. Note language/on-device recognition availability.
- Use an innocuous research request with a brief and links. Avoid consequential
  actions until approvals have been independently verified.

Record device model, iOS version, build, network, audio route, Focus/silent state,
power state, timestamps, task/run/event IDs, expected behavior and observed result.
Do not include credentials, private memo contents, or signing keys in reports.

## Core scenario

1. Tap the CAPA widget. Verify it opens the recorder rather than attempting to
   record in WidgetKit. On a paired device, the listening indicator must reflect
   actual capture readiness.
2. Dictate a research request with several sources. Include distinct first and
   last words; verify both survive the recording boundary.
3. Stop recording. Confirm the app gives an acceptance acknowledgment only after
   the bridge has a Hermes run ID. Check the accepted-task counter once.
4. For the first pass, use a research task that completes promptly to verify the
   complete transport. Then arrange a harmless test run that stays pending for
   at least 25 minutes, using a controlled Hermes test tool/delay in a dedicated
   test profile. Do not rely on a model merely promising to wait.
5. Lock the iPhone, put it down and leave the PTT channel joined. Do not maintain
   an open audio stream or play silence during the wait.
6. When Hermes completes, verify that CAPA wakes through PTT and speaks one useful
   brief. Record completion, push acceptance, audio-start and audio-finish times.
   The screen must remain locked; the microphone must remain inactive.
7. In a separate run, have Hermes create a canonical clarification. Confirm the
   spoken question arrives, then deliberately use the system PTT control to
   answer from the Lock Screen. Verify the existing run resumes and no second
   task is created. If a permission prompt or speech processing cannot complete
   in background, record the failure; the audio must remain recoverable.
8. Reopen CAPA. Verify the full result and working source links. Successful
   playback must not be repeated merely because the app reopened.

Repeat the 25-minute case three times per supported speech route. This is a
proposed pilot gate, not evidence of a reliability percentage. Do not claim
reliability until real trials and their failure rates have been recorded.

## Interruptions and recovery

| Scenario | Required observation |
|---|---|
| Turn availability off before completion | No unsolicited speech; notification/result remains available |
| Leave the channel in system UI | CAPA reflects off state and invalidates host PTT registration |
| Headphones removed during speech | Playback stops; no continuation on speaker; event stays recoverable |
| Cellular or FaceTime call | CAPA yields audio; no false playback receipt |
| PTT denied/unavailable | Normal notification and tap-to-hear work where permitted |
| App force-terminated | No guaranteed speech claim; verify supported behavior and result recovery |
| Notifications denied or Focus silences them | No false delivery claim; result appears on reopening |
| Phone offline at completion | No delayed stale PTT push; recover event when connectivity returns |
| Wi-Fi to cellular/VPN change | Reconnect without submitting the task twice |
| Lost task-creation response | Same idempotency key; one accepted task |
| Bridge restart during work | Poll the existing Hermes run; do not create a replacement |
| Hermes restart/unknown outcome | Show interrupted/unknown; require review rather than replay |
| Recording interrupted or recognition fails | Preserve audio; another recording cannot overwrite it |
| App terminated with saved reply | Retry still targets the same task and generation |
| Question resolved elsewhere | Retire its pending event; refuse stale responses |
| Approval includes command/edit | Display all details; only exact supported approve-once/deny choices |
| Two completion updates close together | One PTT utterance in flight; neither result lost |
| APNs accepts but playback never acknowledges | Attempt standard alert after 45 seconds |
| Device revoked on host | Reject reads/controls and send no further pushes |

## Release decision

- Pass the real-device core scenario, relevant interruption cases and native build
  checks before labeling automatic locked-screen voice as supported.
- If automatic speech fails or Apple's permitted use does not cover this product,
  ship the accepted notification/tap-to-hear fallback and state its behavior
  plainly. A technically successful development build is not App Store approval.
- Review distribution privacy declarations, provider data handling, app icons and
  provisioning for the final build. Keep the gold visual identity; do not revise
  the personal website's positioning until the working experience is verified.
- Measure setup effort, accepted task count, missing/duplicate announcements and
  whether interruptions were useful. No market moat, ROI or latency claim follows
  from passing automated tests alone.

References: [Apple PTT implementation](https://developer.apple.com/documentation/pushtotalk/creating-a-push-to-talk-app),
[background push limitations](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app),
[Hermes API contract](https://hermes-agent.nousresearch.com/docs/user-guide/features/api-server).


## Cross-device acceptance (not yet run on hardware)

1. Pair Mac from a phone-issued invitation; confirm both list the same workspace
   and existing tasks. A fresh host code must create a separate identity.
2. Submit on Mac, close its hub while leaving the app running, open the task on
   iPhone, and resolve a current clarification there. Verify one Hermes run.
3. Complete the task after the originating device is revoked. The surviving
   device must retrieve the result and receive the next eligible notification.
4. Race Read aloud on both devices: one lease wins. Interrupt playback, wait for
   lease expiry, and explicitly recover the update. No failed playback receipt.
5. Change preferred delivery while speech synthesis is pending; the old device
   must refuse automatic playback. Verify notifications remain the default.
6. Deny notifications, disconnect the bridge, sleep/wake Mac, remove headphones,
   interrupt a recording, and quit/reopen with an unconfirmed submission. Verify
   saved work, honest status, and idempotent retry. A sleeping Mac does not speak.
7. Confirm Connections reflects the Hermes API toolsets, including unavailable
   discovery, without showing credentials or claiming third-party OAuth setup.
