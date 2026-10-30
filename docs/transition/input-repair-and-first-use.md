# Input repair and first use — 25 October 2026

## Reproduced failure

The native pointer view over the SwiftUI widget required `NSApp.currentEvent` to exist and be a left-button event inside `hitTest`. AppKit also performs preflight hit tests before dispatch. A real NSHostingView hierarchy returned the hosting view rather than PointerView for the center of the capsule, explaining why both clicks and drags could fail. Previous direct method tests bypassed this hierarchy and were insufficient.

Removed the event-dependent hitTest override. Standard NSView hit testing now routes to PointerView. Control-click forwarding happens in event handling, with its release suppressed. Existing first-click acceptance, five-point drag threshold, press/release target matching and coordinate conversion remain.

The retained regression harness `macos/Checks/WidgetInputCheck.swift` creates a real NSPanel/NSHostingView with the native representable and verifies center hit testing, NSWindow.sendEvent click routing, drag routing and absence of click-on-drop. It does not inject mouse events into other applications or record audio. Run with a macOS graphical session:

```
swiftc macos/Sources/CAPAMac/WidgetPointerSurface.swift macos/Checks/WidgetInputCheck.swift -o /tmp/capa-widget-input-check
/tmp/capa-widget-input-check
```

52 core checks and the hosted event-routing harness pass. Native Mac release build, signature and ZIP integrity pass. Actual physical pointer and microphone acceptance remain separate.

## Saved memo

An existing 80,574-byte unsent recording prevents fresh capture by design. New recovery action **Keep memo and record a new one** moves the old audio into a private UUID-named file in `~/Library/Application Support/CAPA/Archived Recordings`, then starts fresh capture. It sends no old audio. It is offered only when saved audio exists and the text draft is empty; pending/active work prevents the action. Preferences → Show archived recordings opens that folder. Archive failure retains the old file and reports the error.

## Connection evidence

The local bridge returned HTTP 200. A reply-only test against the default Hermes installation completed with its expected output. Test task `6f1b630a-b38f-479f-beb8-14819fee81ae` produced a completion event routed to paired Mac `9dfff5cb-9e4d-48c6-934b-5a1c3afcab9b`. The temporary verifier was revoked. This verifies backend execution and routing, not microphone capture or visible macOS banners. CAPA's local queued-notification preference did not yet contain this test event when checked; notification authorization/delivery still needs user verification.

## First-use sequence

1. Drag the widget to a clear part of the screen; release. Click the center without moving it.
2. If saved-audio recovery appears, choose **Keep memo and record a new one**. Allow CAPA microphone permission. Existing audio remains archived.
3. Say: “Reply exactly: CAPA voice test succeeded. Do not use tools or perform external actions.” Click the waveform again to stop/send. Allow Speech Recognition if requested.
4. Check the Tasks hub for a completed task and the expected response. If capture/transcription fails, report the displayed error; saved audio is retained for recovery.
5. In Preferences click **Enable notifications on this Mac**, and allow the macOS prompt. If already denied, enable CAPA in macOS System Settings → Notifications. Keep task updates set to Notifications and this Mac selected for updates in Devices.
6. Close the hub window while leaving CAPA running, then send another reply-only request from the widget. Verify its banner and click it to open the result. Do not equate a backend event with a visible OS banner.
7. Use a bounded real task, for example researching a topic and drafting a comparison, initially without sending messages or changing external accounts. Review outputs in Tasks and use the same task's clarification controls when Hermes asks for input.

The local bridge and Hermes gateway must remain running for this Mac connection. Third-party tools/accounts are managed in the user's Hermes installation; CAPA's Connections tab shows the exposed inventory. No new Hermes API key, model account or Telegram setup is required for the already-paired Mac.
