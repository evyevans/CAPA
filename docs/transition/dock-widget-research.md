# Dock clearance and hover review — 25 October 2026

## The actual question

Keep CAPA available and unmistakably clickable without covering system controls or moving its action targets on hover. The user's requested anchor remains fixed at the bottom center of the primary display. Free dragging stays disabled. Scope is the Mac widget and its explanation in Preferences; Hermes and task routing are unchanged.

Applied Elon Frame v3 from the user-provided local skill and the REA reverse-engineer-anything workflow from the requested repository. The screenshot evidence invalidates the prior assumption that the physical screen edge is always a safe anchor.

| Scenario | What works | What fails / implication |
|---|---|---|
| Browser, Dock not visible | Compact waveform and separate arrow remain recognizable at the bottom | Overlay covers some page content. Fixed overlays do not reserve space in third-party apps. |
| Chat app, Dock not visible | Widget remains accessible across apps | Widget overlaps the bottom composer. Keep it small and provide the existing Show floating bar preference and menu-bar fallback; do not claim Dock clearance prevents all content overlap. |
| Desktop, Dock visible | Stable center anchor is predictable | Physical-edge placement puts the capsule in the Dock region, obscuring it. Use usable screen bounds and qualified Dock geometry. |

## Evidence and implementation decisions

- [Flow docking documentation](https://docs.wisprflow.ai/articles/1790396454-move-and-dock-the-flow-bar-on-desktop): avoids visible Dock/menu regions, reclaims space when hidden, handles Spaces and full-screen changes. CAPA adopts Dock clearance; it retains the user's chosen primary-display anchor rather than following the pointer across displays.
- [Flow release notes](https://wisprflow.ai/whats-new): contextual controls can appear on hover. Adopt progressive emphasis, without cloning language/transform tools irrelevant to routing agent requests.
- [Apple NSScreen.visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe): current usable bounds exclude reserved system areas; re-read them rather than caching. Auto-hide can retain a small edge inset.
- [Apple window metadata](https://developer.apple.com/documentation/coregraphics/required-window-list-keys): optional extra Dock clearance uses only on-screen owner PID, layer, alpha and bounds, filtered to the Dock process and Dock window level. No titles, content capture, Accessibility request, or screen-recording request. Dock identification is a geometry heuristic, not a documented Dock-specific API.

Live read-only display probe: frame 1470×956; usable frame starts at y=60 and ends at y=923. Previous panel origin y=0 ignored that reservation. No eligible Dock metadata was returned during the probe, so the optional reveal heuristic is not live-verified. The usable-frame fallback is the supported baseline.

Implementation: 132×42 panel contains the existing 120×30 capsule with six points padding. Pinned origin uses usable bounds, plus any qualified bottom Dock rectangle intersecting the widget. Side Dock reservations clamp horizontal bounds without falsely lifting the widget. Re-evaluate every 400ms while shown and on display/Space/wake events. Only enumerate WindowServer near the bottom edge, at most once per second. Move only when origin changes; delay lowering 800ms and do not lower under a hovering pointer or during recording. Raising can still move it if needed to clear system UI. Polling never activates the hub or repeatedly orders the panel forward.

Hover: 150ms opacity/color emphasis on the glass edge and waveform, a separate highlight on the arrow, native state-specific tooltips and accessibility labels. Capsule size and both hit targets remain constant. Hover does not capture audio, open the app, animate synthetic voice input, or change position. Reduced Motion disables hover transitions. Existing Reduced Transparency support remains. The recording/navigation gap and capture-disabled arrow remain.

Preferences explains the adaptive position and hover behavior. Existing visibility toggle restores/hides the widget; menu-bar recording remains available. Avoid adding copied Flow settings that CAPA does not need.

## Requested REA inspection: actual result and limits

Requested repository cloned to a private temporary directory at commit `fffb0741936067530d1ce9777461cd53e87398c2`; read its reverse-engineer-anything skill and JavaScript/recovery references. Invoked the installed REA CLI v6.7.0 against the installed Flow v1.6.1264 ASAR as inert static input. Format-aware ASAR inventory preceded selection of exactly `.webpack/renderer/status/index.js` and `.webpack/main/index.js`. No vendor code is copied into CAPA.

- Artifact SHA-256: `e43cc5c91c0870bacfd3cddc4e5dbefdbd54399f1e8d20fda485e46107bd2c57`.
- Partial evidence ID: `ev_ebcafd762f4e157aa42cb2e745229f6dd3d934d4a252c98519ffcd4c0a0c6009`.
- REA parsed one JavaScript source, skipped the main source after the 60-second timeout; inventory reports 183 relevant sources with 181 outside the requested selection. Bounded semantic graph is partial/truncated. Result is `provider_timeout`, not a successful full reconstruction.
- Record-and-continue reported three native artifact integrity contradictions (SQLite, Jabra connector, panel activation). Those native artifacts were not executed or used to implement this change.
- Supplementary ordinary static inspection of status source finds explicit state-dependent waveform/microphone rendering, hover-change handlers, and language-circle focus/hover handlers. These are syntax observations, not proof of runtime behavior, precise timing, or Dock placement. REA did not recover the main process Dock algorithm.
- Retained full output privately in `/private/tmp/capa-flow-dock-rea.json`, source inspection in `/private/tmp/capa-flow-status.js`; neither proprietary bundle nor full vendor output is redistributed in the repository. No remaining matching REA worker was found after the run.

## Validation and remaining physical checks

46 shared core checks pass, including bottom Dock reservation, hidden Dock edge, revealed Dock with unchanged usable frame, side Dock, negative display origin, another display's Dock, unrelated floating Dock windows, coordinate conversion, and unchanged disjoint voice/arrow targets. Native Mac release build and signature verification pass.

Physical acceptance still requires the user's pointer and display session: fixed Dock, auto-hide reveal/hide, magnification, left/right Dock, fullscreen/Space switches, lock/wake, hover both targets, click center and arrow separately, and actual microphone/notification delivery. Public metadata may be unavailable: do not claim every transient Dock animation is solved until that test. Full-screen overlays also need real OS validation. Audio saved before this update must remain intact; do not send/discard it as a test without the user's intent.
