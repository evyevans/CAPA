# CAPA local pilot verification — 2026-10-24

## Observed against the real default Hermes profile

Hermes API was configured for authenticated loopback access. A private backup of
the original environment was saved before changing it. The drain-aware restart
exited without a supervisor; the same default gateway command was relaunched.
CAPA's bridge runs through the user login LaunchAgent `app.capa.bridge`, backed
by its own Python environment and private SQLite database. No external listener,
provider account, cloud deployment or firewall rule was created.

A real no-tools verification request completed through Hermes. Two temporary
paired clients shared a workspace and recovered the same task/result. Reusing the
request ID from the second client retained one CAPA task. A real Hermes run ID
and completion delivery event were observed. All test devices were revoked after
the check. Real discovery returned 27 toolsets; Hermes's skills endpoint returned
HTTP 500. CAPA now reports that partial failure without hiding working toolsets.

The installed Hermes toolsets response uses a `data` envelope, rather than the
bare array in earlier contract examples. Regression coverage includes this shape
and skills failure. Bridge installation now uses a clean build context to avoid
copying stale `build/lib` package content into an installed wheel.

## Checks and artifacts

- 43 bridge API/persistence/delivery tests passed.
- 23 portable/shared Apple client checks passed, including Mac-only loopback URL
  acceptance and rejection of insecure remote URLs/credentials in addresses.
- Native Mac compilation, app signature verification and zip integrity passed.
- iPhone syntax and property list checks passed; full iOS SDK build is unavailable.
- The reusable opt-in backend test is `scripts/verify-live.py`; its report is
  `docs/transition/live-backend-result.json`. It never logs bearer credentials.

## Remaining physical and distribution gates

Native microphone recording, speech permissions, real macOS notification delivery,
window/bar interaction, sleep/wake and network interruptions require interactive
acceptance. Backend completion events do not prove a visible OS notification.
The Mac must be awake with the app running. It remains a local ad-hoc-signed preview.
Public distribution needs signing, notarization, app assets and supported-device
acceptance. iPhone needs full Xcode, provisioning, trusted HTTPS, APNs setup and
physical testing. No locked-screen speech support or App Store approval is claimed.
