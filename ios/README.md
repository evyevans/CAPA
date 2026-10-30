# CAPA iPhone companion

Native SwiftUI app, WidgetKit shortcut, deliberate audio capture, and a persistent
user-controlled Push to Talk channel to Hermes. The existing Vite showcase remains
separate.

## Build and sign

1. Install full Xcode with an iOS SDK and select it in Xcode's settings. Command
   Line Tools alone cannot compile SwiftUI, WidgetKit, PushToTalk or XCTest.
2. Open `CAPA.xcodeproj`, select the **CAPA** scheme and a physical iPhone running
   iOS 17 or later. PTT and APNs feasibility must be tested on hardware.
3. Set your Apple Development Team for both **CAPA** and **CAPAWidget**. Replace
   the two example bundle identifiers with unique identifiers under that team.
   The widget's identifier must start with the app's identifier plus a dot.
4. Check Signing & Capabilities: Push to Talk, Push Notifications, and Background
   Modes (Push to Talk and Audio) for CAPA. The generated entitlements are inputs
   to provisioning, not proof that Apple has granted the app these capabilities.
5. Set the bridge's `CAPA_APNS_BUNDLE_ID` to the exact app identifier. Debug uses
   development APNs; Release uses production. Match `CAPA_APNS_SANDBOX` on the host.
6. Build and run. Pair with a trusted HTTPS bridge and its one-use host-generated
   code. Notifications are enabled explicitly in Settings; incoming voice has its
   own availability toggle. Microphone and speech permissions do not grant
   unrestricted background execution.

The project has a shared scheme and a local Swift package, with no third-party
iOS dependencies. `python3 generate_project.py` regenerates project metadata;
it restores example bundle identifiers, so preserve intentional signing edits
before regenerating. The generator does not write your source or sign anything.

## Shared identity and settings

Pair the first device using a host code. To share work with a Mac or another phone,
use **Settings → Linked devices → Link another device** on the paired client and
enter that invitation on the new client. This is the pilot’s sign-in experience;
there is no simulated email or social login. Notifications are the default.
Spoken replies and spoken acceptance are separate opt-in settings. Settings also
shows the actual toolsets/skills discovered from Hermes; tool authorization stays
in the Hermes profile. Linked devices see and can control all workspace tasks.

## What the app does

- Widget and `capavoice://record` enter the recorder. The widget itself never
  records. First use still requires pairing and microphone permission.
- Capture starts only after the microphone is ready. A memo is limited to three
  minutes, finalized before transcription, and retained if recognition or delivery
  fails. Recover or explicitly discard it before starting another recording.
- On-device recognition is required for the native route. Unsupported languages
  can use explicitly configured Hermes host speech; the app never silently sends
  recognition to a different provider.
- Sending stores a stable request identifier before networking. An ambiguous
  response keeps that identifier for retry. Only a returned Hermes run ID permits
  the acceptance acknowledgment.
- Task details show the full result, source links, exact approval command and
  structured edit where supplied. Only advertised approve-once/deny choices are
  offered. Speaking a clarification answer resumes that prompt, not another run.
- Incoming voice stays enabled until turned off or the system channel is left.
  An incoming PTT push claims a receive-audio session; no network work blocks its
  synchronous delegate callback. The phone fetches the authenticated update and
  audio, or uses its native voice. The microphone remains off until a deliberate
  transmission.
- Playback acknowledgment happens after audio finishes. Missed pushes, interrupted
  speech and failed playback remain recoverable. Local receipts suppress repeats
  when the acknowledgment's network response is lost.
- Calls and headphone disconnection stop playback. An interrupted recording is
  preserved. Failed PTT delivery falls back to an ordinary notification when APNs
  is configured; notification taps open the saved result. Read aloud is an explicit action.

## Verification boundary

`bash ../scripts/check-companion.sh` runs bridge tests, portable Swift checks,
Swift syntax validation, plist validation and (when available) an unsigned iOS
Simulator build. A syntax check is **not** native framework typechecking.

The initial implementation environment has Command Line Tools but no full Xcode,
iOS SDK, signing team or connected iPhone. Native framework compilation, actual
APNs delivery, background synthesized speech, and the 25-minute locked-screen
scenario are therefore unverified. Use the [device acceptance procedure](../docs/transition/device-validation.md)
before describing CAPA as ready for distribution. The project still needs final
app icons, distribution privacy review and App Store acceptance of this AI PTT use.
