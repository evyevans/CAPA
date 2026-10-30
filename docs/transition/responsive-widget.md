# Responsive widget correction — 25 October 2026

The user's screenshot and report reject the cramped 50-point revealed bar. The latest requirement is a revealed bar close to the earlier 120-point CAPA design, slightly smaller, retaining the compact resting state and hover-to-reveal behavior. This supersedes the earlier request to match Flow's declared ready-state width exactly.

## Findings and change

The prior path sampled pointer location every 80ms, then imposed 120ms dwell. Depending on sample timing, deliberate reveal could wait roughly 120–240ms before rendering. It also enumerated WindowServer metadata synchronously during reveal. These are source-confirmed sources of avoidable latency, not a measured attribution of every reported glitch. Conditional removal/recreation of SwiftUI controls and movement of the open anchor were additional stability risks.

- Revealed capsule: 104×30 native points (about 13% narrower than the previous 120-point version). Resting handle remains 40×8.
- Recording target: 52×30; arrow: 20×26 centered at x=92; four-point neutral gap. Restored the seven-bar waveform and legible arrow. Neither hover nor gap clicks perform an action.
- Mouse-only local/global NSEvent monitors schedule coalesced UI updates. The local monitor returns events unchanged; no keyboard events are observed. Event monitors are removed on termination. A common-mode 100ms timer handles stationary-pointer timeout/state changes and acts as a fallback.
- First trigger reveals immediately; the 900ms leave delay remains for stability. A 128-point approach zone and 140-point corridor make the open bar easier to reach from the screen edge.
- Recording/navigation views remain mounted, with opacity, hit testing and accessibility toggled. Hover/focus/recovery state no longer depends on reconstructing the control subtree.
- Open anchor stays fixed until hide, wake or display invalidation; reinitialization also works when already open. It may rise if reserved system UI would overlap it, but does not oscillate downward during use.
- Usable screen bounds remain the baseline. Optional Dock geometry runs on a background utility queue, at most one request in flight and roughly 750ms apart near the bottom edge. The main actor consumes only cached CGRect values. Old-display results are discarded. Cache is cleared on collapse or leaving the probe region; late results cannot repopulate it while tucked away. No window titles or content are retained. Dock metadata may be unavailable; there is no universal promise of clearance during every transient auto-hide/magnification animation.
- Native menu tracking holds the widget open while its context menu is in use. Recording, speech, processing, recovery, held pointer buttons, accessibility reveal and the always-visible preference retain their existing protections.

## Referenced repository

Inspected the specifically requested [MIT-LCP/mimic-code repository](https://github.com/MIT-LCP/mimic-code). Its README describes analysis utilities for the MIMIC critical-care databases. The user clarified that its role is methodological: study a reference, reproduce behavior, retain provenance and validate results. Apply that reproducibility discipline to Flow documentation, inspected shipped UI styles and an explicit CAPA acceptance matrix. The repository does not itself supply a macOS hover framework; no clinical-analysis dependency is introduced into CAPA.

[Apple's event monitoring documentation](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html) documents the distinction between local and global monitors, main-thread handlers, preserving events and lifecycle cleanup. Mouse monitoring does not require the keyboard-specific Accessibility entitlement described there.

## Validation and practical limit

56 shared checks pass, including immediate first-hover reveal, leave hysteresis, long capture/recovery hold, revised control geometry and placement rules. Native release build, signature and ZIP integrity checks pass. A native off-screen render was inspected for spacing; it does not verify live pointer delivery or frame latency.

Source review caught the open-anchor reinitialization issue; corrected before installation. Existing Hermes pairing/tasks/audio are unaffected. Physical acceptance still requires cross-app hover, approaching from both sides, Dock hidden/visible/magnified, right-click menu, waveform/arrow clicks, recording with the pointer elsewhere and wake/full-screen/Space changes. We have removed specific avoidable delays; equality with Flow's runtime responsiveness is not established by these checks.
