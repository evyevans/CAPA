# CAPA — a voice companion for Hermes

![CAPA — One sentence. Everything done.](assets/capa-branding.jpeg)

An experimental, free, MIT-licensed companion for your existing Hermes agent.
Click a small recorder, speak a request, and return when Hermes has a result or
needs your input. Notifications come first; spoken replies are optional.
The image above is the original project artwork, not a guarantee of task completion.

CAPA is a community prototype, not an official Hermes product or a production
service. It does not include a hosted agent, provider credits or a CAPA cloud.
Your configured Hermes providers and infrastructure may still cost money.

## What is real, and what is a demo?

| Component | Implemented behavior | Verification / limitation |
|---|---|---|
| `bridge/` | Python service with SQLite task persistence, device pairing/revocation, shared workspaces, Hermes run routing, controls, delivery events and playback leases | Automated tests exercise persistence and API flows with external Hermes/APNs transports replaced. Live setup required. |
| `macos/` | Native hub, movable recording bar, menu entry, saved memos, task results, local notifications and optional speech | Local compilation/package checks; hardware and live Hermes acceptance remain to be completed. Mac must be awake and app running. |
| `ios/` | Native iPhone source, widget entry, task/settings UI, device linking and experimental Push to Talk | Full Xcode, signing and physical iPhone tests required. Locked-screen speech is not verified or guaranteed. |
| `src/` | Older React visual showcase: animated interface, sample tasks/replies and simulated connector settings | Not wired to the bridge. Guest-only navigation; no actual accounts, checkout or tool authorization. Sample exchange uses no microphone or agent. |

Native Connections lists toolsets/skills reported by Hermes. Configure and authorize
tools in Hermes itself; CAPA does not supply a third-party OAuth connector catalog.
Linked devices are trusted with all tasks and controls in their workspace.
Android and Windows clients are not implemented.

## Try the Hermes companion

You need an existing compatible Hermes API, Python 3.11+, and a trusted HTTPS
address for the bridge. No Hermes/provider API key belongs in the frontend.

1. Follow [bridge setup](bridge/README.md) on the Hermes host.
2. Follow [Mac build and pairing](macos/README.md), or [iPhone setup](ios/README.md).
3. Link additional devices using an invitation from the first paired device.
4. Run the [physical/cross-device acceptance procedure](docs/transition/device-validation.md)
   before relying on completion alerts or spoken delivery.

No signed public download or App Store release is supplied. Build the local Mac
preview with `bash scripts/package-mac.sh`; public distribution requires signing
and notarization. Use harmless tasks while evaluating the prototype.

## Explore the older visual demo

With Node.js 22 LTS and npm, from this directory:

```sh
npm ci
npm run dev
```

Open the local address and choose **Explore visual demo**. No login or payment.
Connector buttons and successful sample replies do not authorize services or execute
work. Preferences persist in browser storage. The sample exchange uses no external voice widget. Google Fonts load externally.

```sh
npm run lint
npm run typecheck
npm run build
```

The demo's static output is `dist/`. It is separate from the native companion.

## Check the companion

Install the bridge test dependencies as described in its README, then:

```sh
bash scripts/check-companion.sh
```

This checks the bridge, shared Swift logic, native Mac build, and iOS syntax/plists.
An iOS Simulator build runs only when full Xcode is available. Automated checks
cannot establish microphone behavior, APNs delivery or real task completion.

## Contribute or reuse

Fork, experiment, and reuse CAPA under the [MIT license](LICENSE). Start with
[CONTRIBUTING.md](CONTRIBUTING.md), [security notes](SECURITY.md), and the
[release readiness checklist](docs/OPEN_SOURCE_READINESS.md) and [publication steps](docs/PUBLISHING.md).
Dependencies and third-party marks retain their own terms; see [notices](THIRD_PARTY_NOTICES.md).
Architecture and earlier investigation notes live in `docs/transition/` and are
historical context, not evidence that hardware or distribution checks passed.
