# CAPA continuity and simple dispatch — 2026-10-24

Apply Elon Frame v3 to the user's current intent: reliable voice delegation to
their own Hermes, outside its chat UI, with shared identity across devices.

Notifications and readable outcomes are the default. Spoken acceptance and
automatic spoken updates are optional. Hermes writes a concise opening brief;
CAPA optionally reads it aloud without adding a second summarizing agent.

Sign-in for this self-hosted pilot is device pairing to a workspace. A trusted
device issues a one-use invitation for another device; no fictitious email or
social login. Legacy device histories remain isolated until explicitly linked.
Use an API-owned session per workspace; retain existing sessions and task IDs.

Desktop UX: first-run connection -> hub with Tasks, Connections, Devices,
Preferences; compact movable edge bar and menu-bar entry for everyday recording.
The bar records, sends and shows acceptance/error. The hub holds complete
results, source links, exact approvals and recovery. Preserve CAPA's gold and
charcoal identity, not Flow's branding or extraneous navigation.

iPhone UX: the same shared work/settings with platform-supported widget entry.
No promise of a global floating overlay. Default notifications open the result;
Read aloud is explicit. Experimental PTT remains opt-in.

Connections discovers actual Hermes toolsets and skills, read-only. Show unknown
state honestly. Tool authentication stays with Hermes; a separate OAuth catalog
and CAPA-owned provider credentials are outside this phase.

Implementation sequence: transactionally migrate workspace identity; add explicit
device invitations/revocation and shared history; add delivery destination and
playback leases; real connector discovery; share Apple network/Keychain code;
update iPhone; implement native Mac hub/bar and local downloadable app; verify.

Acceptance: linked Mac/iPhone see the same task, result and current question;
replies resume that question, idempotent retries never duplicate work; another
workspace cannot access them. One selected device receives automatic speech;
concurrent playback is refused while a lease is active. A late or lost receipt
can require manual recovery; exactly-once audible delivery is not promised. Revoking the origin does not abandon another
authorized device's task. Existing DB migrations must be repeatable and never
merge strangers. Capture remains deliberate and failed audio recoverable.

Market hypothesis: existing Hermes users value delegating outside chat and
returning only when needed. Measure setup abandonment, time to first accepted
task, lost/duplicate work, useful alerts, repeat use and willingness to pay.
Implementation alone establishes neither demand nor product-market fit.

Native iPhone background behavior still requires full Xcode, signing and physical
device validation. Mac distribution needs signing/notarization before publication.
Android and Windows clients can use the shared API but are not implemented by
adding their names to a platform list.
