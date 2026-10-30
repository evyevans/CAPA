# CAPA for Mac — local preview

Native SwiftUI hub with Tasks, Connections, Devices and Preferences, plus a menu
bar entry and a draggable recording bar. macOS 14+, built for the current machine’s
architecture. No external Swift dependencies; the Apple client uses shared
CapaCore networking, Keychain storage and task models with iPhone.

## Build and run

```sh
bash scripts/package-mac.sh
open artifacts/macos/CAPA.app
```

Run from the repository root with Apple Command Line Tools. The output zip is a
local ad-hoc-signed preview, not a notarized public download. A release requires
Developer ID signing, notarization, final app artwork and testing on supported
Apple Silicon/Intel targets. Do not describe this zip as an App Store release.

First run opens the connection screen. Enter `http://127.0.0.1:8787` for a bridge on this Mac, or a trusted HTTPS bridge URL, and
one-use pairing code. Use an invitation from an existing CAPA device to share
its workspace; a new host code starts a separate workspace. Device credentials
stay in Keychain; Hermes/provider credentials stay on the host. Setup still
requires a functioning Hermes installation and reachable bridge.

Close the hub to keep the bar/menu running. Click once to
record and again to send. The microphone permission prompt appears on deliberate
first recording. Shift-Command-R works while CAPA is active; this build does not
register a global keyboard shortcut. No Accessibility permission or ambient
microphone recording is required. Capture is capped at three minutes; failed
recognition or an uncertain submission preserves the memo for recovery.

Notifications are the default and must be enabled explicitly. Notification clicks
open the full task. Optional spoken results use native speech or the user's
configured Hermes speech provider; no extra CAPA model synthesizes summaries.
Only the selected device can automatically claim an update. Permission, sleep,
Focus and network conditions affect timely delivery. Results remain retrievable.
The Mac must be awake with CAPA running; it does not wake a sleeping computer.

Connections displays actual Hermes API toolsets/skills. Connect accounts in the
Hermes profile; this preview does not provision OAuth integrations. Any linked
device can read/control the shared tasks and revoke other devices. Use the
Devices page to link or revoke; no separate cloud/email identity is implemented.

## Local runtime

Follow the bridge README to configure your own environment. This source release
does not install or assume a login LaunchAgent, existing local credential file,
or running Hermes service. Local pilot details from the original development
machine are not portable installation instructions.

## Verification

`bash scripts/check-companion.sh` runs bridge tests, portable Swift checks,
a native Mac build, iOS syntax/plist checks, and an iOS Simulator build when full
Xcode exists. Local compilation does not verify microphone hardware, notifications,
Keychain prompts, cross-device networking or product-market fit. Complete the
[cross-device acceptance cases](../docs/transition/device-validation.md) with a
real Hermes profile before a public pilot. iOS overlays and locked-screen audio
have separate platform rules; Mac’s floating panel is not a promise for mobile.


## Widget recording repair

The widget is a centered icon with no visible words. The center is the
record/stop control. The separate right-hand arrow opens CAPA; it is disabled during
recording to avoid accidental navigation. Right-click also opens CAPA or hides it. During actual
capture, the waveform follows measured loudness and an estimated vocal pitch;
there is no simulated listening animation. Reduced Motion keeps the glyph still.
Analysis is local and is stopped with capture; no raw samples are retained by it.

A dot/orange icon means a saved memo or error needs attention. Click for recovery
and retry/discard actions. Saved audio is never silently overwritten. Successful
recovery clears the stale error. Typed submission is disabled during capture and
recognition. Device changes stop and preserve capture.

Offline recognition picks an installed model in the user's existing language,
keeping the preferred locale where installed and then trying the current region.
This avoids an unavailable British English model blocking Canadian English on a
Mac configured with regional overrides. A configured Hermes provider may be used
if native recognition fails; no new provider is silently provisioned.

CAPA requests the macOS notification prompt once after pairing. Results are
processed independently of the periodic Hermes capabilities check. Interrupted
speech remains unacknowledged and can generate a notification; disabling
notifications does not falsely mark the result as delivered.


The 104 × 30-point glass widget stays visible until explicitly hidden. Drag anywhere on it to place it on a connected display; its position is saved between launches. Click the waveform to record/send and the separate arrow to open CAPA. Dragging never triggers either action.

Preferences and the right-click menu offer Reset widget position. Automatic hiding, the resting handle and hover-trigger monitoring have been removed. See [current draggable widget behavior](../docs/transition/free-position-widget.md).
