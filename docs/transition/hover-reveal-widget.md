# Bottom hover-reveal widget — 25 October 2026

The latest user instruction supersedes the proposed drag-anywhere change. That drag staging branch was never installed. CAPA stays anchored at bottom center, reduces to a tiny resting handle, and reveals interactive controls when approached. Scope is native Mac UI; Hermes, pairing, saved audio and task routing are unchanged.

## Actual REA work and dimensions

Used the requested REA repository's JavaScript workflow, reusing retained evidence rather than repeating the previous expensive application analysis. The installed Flow app is v1.6.1264. ASAR SHA-256: `e43cc5c91c0870bacfd3cddc4e5dbefdbd54399f1e8d20fda485e46107bd2c57`.

REA v6.7.0 `inspect-analysis-view` successfully validated/projected the retained partial evidence:

- Parent: `ev_ebcafd762f4e157aa42cb2e745229f6dd3d934d4a252c98519ffcd4c0a0c6009`.
- Summary view: `ev_594fb6ff39438284258a799c6a3fd930a9c5abf667bd9539f9af84d5f72838ed`.
- Exact widget stylesheet-module view: `ev_8973d41143ef42e2dea6a021e1fb84c2aca62f2fcf132ef9302f2232bd5a810a`.
- Selected module node: `jag_node_76e3068950ada776a03c9c69df92de876b259bff0102cf19ab2a6c880364fd2c`, webpack module `31201`, exported `A`.
- Bundle `.webpack/renderer/status/index.js`, SHA-256 `f74e27a53383979e57dd1456e82746dee441bd879698bde1296001864c07f215`; REA source range line 1, columns 699257–726168. Module source hash `9171b1198f4f831ee3e06c76b254403a5fa7aa41abcbf687134ce71c8e54f269`.

Supplementary format-aware static inspection of that module's CSS locals and bottom-position selectors identifies a 40×8 resting thought bubble and a 50×30 ready bubble. Other Flow states have other widths. These are declared CSS layout dimensions, not a runtime pixel measurement across zoom/display scales. CAPA matches the resting/ready dimensions in native points; its other states retain the small 50×30 control surface.

The prior application analysis remains partial: main bundle timeout, bounded semantic coverage, three unrelated native integrity contradictions. Successful evidence projection does not repair those limits or prove Flow runtime behavior. Vendor source remains only in private temporary research files; no proprietary implementation was copied into CAPA. The public [Flow positioning documentation](https://docs.wisprflow.ai/articles/1790396454-move-and-dock-the-flow-bar-on-desktop) supports clearing system UI, but does not establish that Flow has the identical hover-only hiding policy requested here. CAPA's policy below is our implementation decision.

## Interaction contract

- Resting: 40×8 handle at physical bottom center. Its containing window ignores pointer events, so it does not steal clicks from the Dock or underlying application.
- Approach: 120ms dwell within an 88×20 bottom-center or usable-edge hotspot reveals the 50×30 capsule. Cheap global pointer-position polling every 80ms requires no global event monitor or Accessibility permission.
- Reveal: determine usable screen/Dock bounds before enabling hit testing, then place controls above reserved Dock space. A 96-point-wide corridor connects the edge with the revealed controls, keeping them visible while the pointer crosses the Dock-to-widget gap.
- Leave: tuck away after 900ms outside the corridor and control bounds. Hovering never starts recording or opens CAPA.
- Active capture, permission preparation, transcription, sending and speech keep controls visible. Recovery popover and held pointer buttons also prevent hiding. The stop target remains reachable during long recording.
- Accessibility: resting handle exposes a reveal action that keeps controls open for five seconds. Preferences includes an auto-hide toggle; turning it off keeps the small capsule visible. Menu-bar recording/open controls remain available.
- Geometry: centered 22×30 recording target; separate 10×24 arrow target at x=45; four-point neutral gap. Arrow remains disabled during recording/preparation. No visible text in the capsule.
- Existing glass, subtle RGB edge, measured audio waveform and Reduced Motion/Transparency support remain. Rest/reveal does not require animated window movement.
- No drag gestures or saved custom position are installed.

## Verification

56 shared core checks passed, including hover dwell, leave hysteresis, corridor retention, long-running capture visibility, recovery hold, exact resting/ready constants and resized disjoint click targets. Native Mac release builds, signature verification and ZIP integrity passed. An off-screen native SwiftUI render of both sizes was inspected; it is a design render, not a screenshot of the installed app.

Remaining real-device acceptance: hover near the bottom center with Dock visible and hidden, move through the corridor, click waveform/arrow separately, recording while pointer leaves, recovery/context menus, VoiceOver activation, full-screen/Space switches and Dock magnification. Native pointer and OS animation behavior cannot be proven by geometry tests. If Dock metadata is unavailable, usable screen bounds remain the fallback; no screen-recording permission is requested just for placement.

## Mobile follow-up

Phones have no pointer hover. Use a deliberate tap on the platform's widget/shortcut to open the recorder; keep the recording control large and navigation separate inside the app. Do not copy this Mac edge hotspot or shrink phone touch targets to 50×30. Mobile implementation is outside this update.
