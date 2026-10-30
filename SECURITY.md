# Security and privacy

This prototype grants trusted paired devices access to the configured Hermes
profile's tasks and controls. It is not a hardened multi-tenant hosting service.
Use a private, trusted HTTPS endpoint; keep Hermes API keys and Apple signing/APNs
keys on the host. Do not expose Hermes directly or weaken certificate validation.

Revoke lost devices, protect and back up the bridge database with its sidecars,
and inspect exact approval details. Revocation does not cancel already accepted
work. Speech may be audible nearby; provider processing depends on your setup.
The visual demo uses a sample exchange and does not activate a microphone or external voice widget.

Do not post exploit details, tokens or user data in public issues. Private
vulnerability reporting is enabled for this repository. Use
[Report a vulnerability](https://github.com/evyevans/CAPA/security/advisories/new)
or **Security → Report a vulnerability** on GitHub to submit a private report.
If the option is unavailable, do not post a public vulnerability report.
No security support SLA or production-readiness guarantee is offered.
