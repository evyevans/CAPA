# CAPA bridge

A private service beside an existing Hermes installation. It owns durable task
receipts and delivery events while client devices are offline or suspended. It does not replace
Hermes, grant it new tools, or host an additional language model.

## Install locally

Use Python 3.11 or later. From this directory:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -e '.[test]'
```

Configure variables in your own terminal or service manager. `Settings.from_env`
reads the process environment; it does not automatically load `.env` files.
Copy `.env.example` to a private location, fill the Hermes API key, and export
its variables. For a trusted shell-format copy:

```sh
set -a
source /absolute/private/path/capa.env
set +a
.venv/bin/capa-bridge serve
```

This binds to `127.0.0.1:8787`. Expose it to your phone through a trusted HTTPS
endpoint on your private network or an existing HTTPS reverse proxy. A VPN alone
does not provide HTTPS. iOS uses normal certificate validation: self-signed or
untrusted certificates are not bypassed. Keep Hermes itself on loopback when
the bridge shares its host. Remote Hermes URLs must use HTTPS.

For direct TLS, the CLI accepts `serve --host ADDRESS --tls-cert PATH --tls-key PATH`.
It refuses an unencrypted non-loopback listener. Run **one bridge process**;
the reconciliation worker is in process. Multi-worker deployment is not supported.
The bridge is run manually until you deliberately configure your own service
manager; this implementation does not change existing Hermes configuration,
install a daemon, or open firewall ports.

## Pair and revoke

In another terminal, using the same database path and OS account:

```sh
.venv/bin/capa-bridge pair
.venv/bin/capa-bridge devices
.venv/bin/capa-bridge revoke DEVICE_ID
```

The generated high-entropy pairing code expires after five minutes and can be
consumed once. The iPhone receives an independent revocable device credential;
the bridge stores its hash, and iOS stores the credential in Keychain. It never
receives Hermes's API key or Apple's signing key. Device revocation removes push
tokens and access; already accepted Hermes work is not automatically cancelled.

Pairing attempts are rate limited. Credentials belong only in Authorization
headers, not URLs. Keep the database and its WAL/SHM files private and back them
up together while the bridge is stopped. The default location is
`~/.local/share/capa/bridge.sqlite3`; `CAPA_DATABASE` overrides it. Cached voice
audio is stored in `capa-audio/` beside the database. No automatic retention or
remote telemetry is configured. To erase pilot history, stop the service and
remove its database, sidecars and audio cache; this unpairs every device and does
not erase Hermes history or cancel its work.

## Link devices and shared work

The initial host-generated code creates a new workspace. In CAPA’s Devices page,
choose **Link another device** and enter its short-lived code plus the same HTTPS
bridge URL on the other device. Alternatively use `capa-bridge pair --link-device
DEVICE_ID` on the host. A plain `pair` creates a separate workspace; do not use it
to recover shared history. Any linked device is trusted with all workspace tasks
and controls, and can invite or revoke others. No email account or CAPA cloud is
required. Keep a host backup if every device is revoked.

Existing devices migrate into separate workspaces without changing their Hermes
sessions or task ownership. Migration does not automatically merge histories.
Before upgrading, stop the bridge and back up the database and sidecars. Mixing
older and newer client versions is discouraged; old clients do not honor workspace
reply settings or playback claims.

Notifications are the default. Optional speech goes to one selected active device.
Changing that preference reroutes pending updates; existing playback leases remain
until expiry to prevent overlap. Revoking the origin does not cancel accepted work
if another trusted device remains. Expiring leases support recovery, not a promise
of exactly-once audible delivery after every possible crash.

Mac uses local notifications while its app runs, and polls the same durable API.
Its notifications are not included in the bridge’s APNs `notified` counter. Mac
cannot receive updates while asleep. Mobile background alerts require APNs.

## Enable background delivery

Create a token-based Apple Push Notification service key in your own Apple
Developer account. Set `CAPA_APNS_TEAM_ID`, `CAPA_APNS_KEY_ID`,
`CAPA_APNS_KEY_PATH` and `CAPA_APNS_BUNDLE_ID`; never put that key in the app.
Use `CAPA_APNS_SANDBOX=true` for development builds and `false` for distribution.

During an active channel, the phone registers its ephemeral PTT token and channel
identifier. The bridge sends `pushtotalk` pushes to `BUNDLE_ID.voip-ptt`, priority
10, expiration 0. Acknowledged playback clears the event. After 45 seconds without
acknowledgment, the bridge attempts an ordinary alert instead of repeating speech.
Only one PTT update per device is in flight at a time. APNs accepting a push does
not prove delivery. Network errors are retried with bounded backoff; all outcomes
remain retrievable through the API even without push configuration.

Disabling incoming voice invalidates the stored PTT token. Ordinary completion
notifications remain enabled independently. Alert payloads contain an event ID
and a generic message, not task contents. The APNs key may be used from this
user-hosted service; no CAPA-managed relay is required for the personal pilot.

## Speech and Hermes compatibility

Default: iPhone on-device recognition and native speech. To reuse the user's
existing Hermes voice configuration, explicitly set `CAPA_HERMES_PYTHON` and
`CAPA_HERMES_REPOSITORY`. Set `HERMES_HOME` to the same profile used by the API
key. The selected interpreter needs that Hermes installation's dependencies.

The helper calls Hermes's existing `transcribe_audio` and `text_to_speech_tool`
functions. It inherits the configured profile/provider environment. It does not
provision providers or fall back to a CAPA-owned API key. Existing paid-provider
usage still costs money. Host audio is prepared before PTT delivery where
possible and cached per event to avoid repeated synthesis. Provider failures
leave native voice and notification recovery available.

Verified contract reference: Hermes `v0.22.5` installed source. Start runs through
`POST /v1/runs` with a durable `Idempotency-Key`, poll `/v1/runs/{id}`, and resolve
canonical generation-bound controls. The installed capability table omits
`run_clarify` despite exposing the route; CAPA permits it only after reading a
live clarify control and the `run_approval_response` feature. Hermes validates
the final prompt identity and generation. Unsupported installations must be
upgraded or operated directly; CAPA does not invent a successful connection.

Each workspace has an API-owned session shared by its explicitly linked devices. It does not attach to a Telegram or
CLI-owned session. Follow-ups reuse that API session and the profile's existing
tools and memory. CAPA asks Hermes to await work rather than detach it beyond the
run's lifetime. Work independently detached by a skill is not a tracked CAPA task;
this pilot does not monitor arbitrary cron jobs or all other Hermes channels.

Ambiguous admissions retry their original key for at most 23 hours, inside the
documented 24-hour Hermes ledger window. After that, CAPA records an unknown
outcome and requires review. Missing runs and interrupted outcomes are surfaced;
CAPA never silently recreates the work. A stopped run stays tracked until Hermes
reports its terminal state.

## HTTP interface

Except `/health` and `/v1/pair`, all routes require a device bearer credential.
Task, event, control, speech and metric access are scoped to the authenticated device’s workspace. Push tokens and availability remain device-specific.

| Route | Purpose |
|---|---|
| `POST /v1/pair` | `{code,name,platform}` → `{device_id,token,workspace_id}` |
| `GET /v1/me`, `PUT /v1/workspace` | Shared identity, reply mode and preferred delivery device |
| `GET /v1/devices`, `POST /v1/devices/link` | Trusted devices and one-use workspace invitations |
| `DELETE /v1/devices/{id}` | Revoke a device in this workspace |
| `GET /v1/connections` | Read-only toolset/skill metadata from Hermes |
| `GET /v1/capabilities` | Hermes contract plus push/host-speech configuration |
| `PUT /v1/device` | Availability and push-token registration; false clears PTT state |
| `DELETE /v1/device` | Revoke the current device |
| `POST /v1/tasks` | `{request_id,text}` → durable task receipt; same ID/text reuses the task |
| `GET /v1/tasks`, `GET /v1/tasks/{id}` | Recover task state, output and pending controls |
| `POST /v1/tasks/{id}/control` | Exact prompt ID/generation plus answer or once/deny |
| `POST /v1/tasks/{id}/stop` | Request stop without pretending the task has already stopped |
| `GET /v1/events`, `GET /v1/events/{id}` | Pending updates or an individual authenticated update |
| `POST /v1/events/{id}/claim` | `{token,manual}` → 120-second exclusive playback lease |
| `POST /v1/events/{id}/ack` | Successful-playback receipt with the same claim token |
| `POST /v1/events/{id}/audio` | Cached host voice where explicitly configured |
| `POST /v1/transcribe` | Up to 8 MB raw `audio/mp4`; no client-supplied path or command |
| `GET /v1/metrics` | Workspace-scoped counts of tasks, pending/notified/acknowledged result updates |

Pending control events retire when Hermes reports them resolved. The metrics
endpoint excludes those retirements from result acknowledgment counts. Use these
counts alongside the device validation log; they do not establish ROI, market
differentiation or end-to-end delivery reliability.

## Tests

```sh
.venv/bin/python -m pytest tests -q
```

Tests use real SQLite persistence and the real ASGI routes. Hermes and Apple HTTP
are replaced at the external transport boundary; tests never execute real user
tasks, use provider credits or send pushes to a real device.


## Installed-build and real-provider checks

For a clean non-editable install, run `bash scripts/install-bridge.sh
/path/to/venv/bin/python` from the repository root. This builds from a clean
context so stale setuptools `build/lib` output cannot silently ship older code.
The installed 0.2.0 runtime includes workspace migration and shared identity.

The opt-in `python3 scripts/verify-live.py --submit --report /private/path/report.json`
checks an actual bridge and configured Hermes provider. It prompts for a one-use
host pairing code without echo, creates two temporary clients, verifies shared
identity, real discovery, one logical task after retry and completion recovery,
then revokes the temporary clients. Provider usage applies. No secrets are printed.
Use `--bridge https://...` for a remote bridge; loopback HTTP is accepted locally.
This verifies backend transport, not microphone hardware or OS notifications.
