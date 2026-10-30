# Compact glass widget — 2026-10-25

Use a Jobs-inspired design lens: one obvious primary action, restrained visual
feedback, and removal of ambiguity. This is a design interpretation, not a claim
about what Steve Jobs would have chosen.

## Desktop implementation

Visible capsule: 120 × 30 points (previously 154 × 42), about 44% less visible area.
Panel including its transparent padding: 132 × 42. Waveform stays mathematically
centered. No visible text. The right-hand expand/app arrow is restored.

Recording is a 64 × 30 target centered at x=60. The app arrow is a separate
20 × 26 target centered at x=108. A six-point gap has no action; left background
is available for dragging. No parent tap gesture and no nested buttons. Decorative
views cannot intercept pointer events. The arrow is disabled during preparation
and recording, while the middle remains the stop/send target. Controls never
move or resize between idle/listening states. App/menu access remains available.

Use native Liquid Glass on macOS 26, ultrathin material on earlier supported
macOS. Surface opacity is 60%; glyphs remain opaque for legibility. The thin RGB
outline is static and faint when idle, and rotates slowly at 60% opacity during
capture/processing/playback. No idle flashing or layout expansion. Reduced Motion
stops edge and waveform animation; Reduced Transparency supplies an opaque base.
An attention dot and accessible labels preserve recovery/error state.

## Phone strategy — not an implemented mobile floating overlay

Do not shrink desktop pointer targets into phone touch targets. The current iOS
WidgetKit implementation opens CAPA's recorder via capavoice://record. Keep that
system-widget entry a single action; do not add a competing tiny launch arrow.
Inside CAPA's recorder, use a 56 × 56 main recording target and a separate minimum
44 × 44 hub/navigation target, with at least 16 points between them. Keep positions
fixed; disable navigation during active capture and retain the standard in-app
navigation path afterward. WidgetKit's system families determine exterior sizing.

Phone acceptance must include one-handed use, accidental-tap trials, VoiceOver,
Dynamic Type, reduced motion/transparency, and keyboard/switch navigation. Native
mobile build and hardware validation remain outstanding.

## Verification

Shared geometry checks cover center, arrow, neutral gap, and disabled navigation
during capture. Existing recording/recovery/language-selection checks remain.
Native compilation and a rendered widget preview verify appearance and layout;
actual pointer/capture and notification acceptance remain a runtime user check.


Release checks: 43 bridge tests and 38 shared Swift checks passed; native Mac
compilation and preview packaging passed. Independent review found no significant
action-hitbox regressions. Rendered preview verifies size, centered waveform and
arrow separation; actual pointer and microphone acceptance remains interactive.

Reference: [Apple glassEffect API](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)).
