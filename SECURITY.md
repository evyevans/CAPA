# Security and privacy

This prototype grants trusted paired devices access to the configured Hermes
profile's tasks and controls. It is not a hardened multi-tenant hosting service.
Use a private, trusted HTTPS endpoint; keep Hermes API keys and Apple signing/APNs
keys on the host. Do not expose Hermes directly or weaken certificate validation.

Revoke lost devices, protect and back up the bridge database with its sidecars,
and inspect exact approval details. Revocation does not cancel already accepted
work. Speech may be audible nearby; provider processing depends on your setup.
The visual demo uses a sample exchange and does not activate a microphone or external voice widget.

Do not post exploit details, tokens or user data in public issues. Once this
repository is hosted on GitHub and private vulnerability reporting is enabled,
use **Security → Report a vulnerability** to send a private report. The maintainer
must enable and test that option before announcing the public repository. If the
option is absent, do not post a public vulnerability report. No security support
SLA or production-readiness guarantee is offered.
