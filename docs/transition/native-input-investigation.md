# Native input investigation — 25 October 2026

User reports all physical widget actions still fail. Earlier method-level tests and hosted synthetic-event tests did not establish live WindowServer delivery; do not present those as proof of a working physical widget.

Investigation confirmed one running installed CAPA process. The actual FloatingBarView, native glass, pointer overlay and app model respond to arrow/drag events delivered through NSApplication.sendEvent in an isolated panel. System input-posting and Accessibility access are unavailable to the tool host. A passive external trace observed no events, but the user did not confirm performing its requested click; that is inconclusive.

A subsequent sample of the running installed process established a concrete freeze: its main UI thread was blocked in `MacModel` initialization → `CredentialStore.load` → `SecItemCopyMatching` waiting for Keychain access. This explains why event-injection helpers that disabled Keychain interaction could pass without proving the real app responsive.

The repair removes credential reads from model property initialization. Startup performs a non-interactive lookup on a detached task. The existing item uses the legacy macOS Keychain, which continued waiting despite LAContext.interactionNotAllowed. CredentialStore now serializes its operations and scopes the legacy per-process interaction flag for reads, restoring its prior value afterward; iOS continues using LAContext. A live lookup of the actual saved item returned without interaction in 25ms. Explicit restore enables the authorization dialog on a background task. Explicit restore/pairing/revocation also run Keychain reads/writes/deletion off the main actor. A denied or delayed Keychain operation must not freeze dragging, the arrow, or connection UI. The widget is now present even while disconnected; its center opens connection setup instead of silently ignoring the click. The native build compiles and the shared checks pass; physical acceptance is still separate.

The new build also makes native panel policy explicit: a borderless WidgetPanel can become key, cannot become main, becomes key only if needed, and explicitly accepts mouse events. Floating-panel configuration precedes status-bar level assignment (the prior order left its live window at layer 3). A faint native backing/pointer paint avoids relying exclusively on the SwiftUI glass surface for the interactive window's pixels. These are controlled changes to test; the remaining physical-input cause has not been conclusively established.

An opt-in `CAPA_WIDGET_DIAGNOSTICS=1` trace records this widget's window/pointer/action transitions, pairing presence and recording-state booleans. It excludes keys, audio, credentials and task text; ends after 15 minutes and caps output at 64KiB per process. Files are private in `~/Library/Application Support/CAPA/Diagnostics`. Normal launches without this environment variable do not trace.

If saved credentials fail to load before application launch completes, the app retries restoration after launch and offers Restore saved connection on the pairing screen. It preserves the existing Keychain item/workspace. Restoring mirrors the normal notification-permission check. Pairing copy no longer implies the local API address is a browser sign-in page.

Validation: actual FloatingBarView arrow callback and drag/drop callbacks pass through NSApplication event dispatch in the explicit native panel; panel key/main/input flags are asserted. Native release compilation, signature and package checks pass. Physical user acceptance remains required: arrow opens hub, drag moves and stays, center opens saved-memo recovery or starts recording. The environment lacks authorized system input posting, so do not claim a fully automated physical click test.

Hosted check command now includes the native panel file:

```
swiftc macos/Sources/CAPAMac/WidgetPanel.swift macos/Sources/CAPAMac/WidgetPointerSurface.swift macos/Checks/WidgetInputCheck.swift -o /tmp/capa-widget-input-check
/tmp/capa-widget-input-check
```
