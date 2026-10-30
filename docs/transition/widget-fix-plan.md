# Widget recording repair

Confirmed: native shared Swift client successfully reads the live Mac workspace.
A saved unsent memo exists. Current recording refuses it and hides the reason
in the hub; the waveform is not clickable. Preserve all saved audio and request
identities. Present recovery at the widget; never silently replace an unsent memo.

Implement a centered icon-only whole-control button, voice-level and pitch analysis
only during deliberate recording, reduced-motion support, accessible state labels,
and visible recovery/errors in a popover. Keep hub access in the context menu and
menu bar. Disable conflicting typed submission while recording or transcribing.

Local recognition errors may fall back only to already configured Hermes host
speech. Preserve audio on failure. Optional capabilities/heartbeat errors must not
block delivery of persisted events. Interrupted speech gets notification recovery.

Check silence and generated pitches/amplitudes, recorder-action safety, native
build, bridge regression suite, independent review, installed app, actual user
recording, and notification appearance/opening. Hardware and user permission
results must be reported separately from automated checks.


## Verification

43 bridge tests and 33 shared Swift checks pass. Native Mac build, signed preview
packaging and pure native widget rendering pass. A real Swift client read task,
event, identity and device data, capabilities, and availability sync from the
paired workspace; its temporary device was revoked afterward.

Observed system configuration: preferred `en_GB@rg=cazzzz` had no offline model;
on-device `en-CA` and `en-US` were available. The new selector picked `en-CA` in
a real platform probe. Hermes's configured OpenAI speech provider resolved to
unavailable, so no new provider was enabled and no audio was uploaded for this
fix. The user's existing unsent recording is preserved.

UI changes: entire capsule is clickable; no visible words or secondary icon;
real recorder metering drives height, optional local PCM analysis estimates pitch;
reduced motion supported. Context menu opens the hub. Attention state opens a
recovery popover, and errors appear there rather than only in the main window.

Audit corrections: conflicting typed sends blocked; successful recovery clears
stale errors; local recognition failure can use already configured host speech;
capability checks run separately and cannot delay saved result delivery; speech
interruption can notify later without falsely acknowledging playback.

Independent review found no additional significant defects in the revised paths.
Actual updated-widget capture, audible/screen behavior and notification appearance
still require interactive user acceptance; automated checks do not establish them.
