# Always-visible draggable widget — 25 October 2026

The latest instruction replaces automatic hiding with direct placement. Keep the current 104×30 capsule, let the user drag it anywhere in connected displays' usable area, and remember its position. No resting handle, hover trigger, auto-hide preference, pointer monitoring, timer-driven relocation, or Dock probing remains in the Mac implementation. Explicit Show floating bar/Hide widget controls remain available.

A native pointer surface handles left-button down/drag/up. Five points of movement starts a drag; dropping saves the position without invoking recording or navigation. Click actions are deferred to mouse-up and require matching press/release hit targets, preventing small movements across the recording/arrow gap from activating the wrong control. The first click works while another app is active. Control-click/right-click pass through to the existing context menu. The underlying SwiftUI buttons retain keyboard and accessibility actions; decorative glass does not intercept input.

Window placement is stored separately from pairing/tasks/audio in local UserDefaults. Display changes and wake clamp saved coordinates into an available display's usable bounds. The window does not activate the hub when moved. Preferences and the widget context menu provide Reset widget position, returning it to the primary display's usable bottom center. No drag or reset action transcribes, submits, or discards a memo.

Validation: 52 shared checks, including custom-position clamping, click-target matching and boundary jitter, plus the existing recording/voice/bridge-contract checks. Native off-screen pointer-method checks pass for first click, deferred action, small jitter, drag suppression, movement and drop. Native Mac release build, signature and ZIP integrity pass. These checks are not a replacement for physical cross-display dragging, actual mouse-event routing and VoiceOver acceptance in the installed app.

Existing Hermes pairing, saved audio and task history are preserved. Older hover-reveal and research documents describe superseded iterations, not current behavior.
