# Publishing CAPA

Current repository: https://github.com/evyevans/CAPA (public, published 2026-10-30).
Private vulnerability reporting, secret scanning and push protection are enabled.
The commands below describe recreating publication; do not rerun repo creation
against the existing repository.

The prepared source is free under MIT, experimental, and centered on the Hermes
companion. Preserve assets/capa-branding.jpeg and the implementation/demo table.
No production or App Store readiness claim is made.

## Local handoff

The recovered tree has fresh history, not the deleted repository's original commits.
If you restore the original GitHub repository, review its history and integrate
this source deliberately rather than force-pushing over restored history.

For a new repository, after reviewing the initial local commit:

```sh
gh auth login --hostname github.com
gh repo create evyevans/CAPA --public --source=. --remote=origin --push \
  --description "Free experimental voice companion for Hermes — native Mac/iPhone source, durable tasks, notifications and optional voice."
```

Run from the CAPA root. This command publishes source and creates a public repo;
the initial publication has already been performed. If the name exists, inspect it
before choosing a replacement or adding a remote. Do not overwrite another repo.

## GitHub settings before announcement

- In Settings → Code security, enable private vulnerability reporting and verify
  **Security → Report a vulnerability** is available for a non-owner account.
- Enable available secret scanning and push protection. Keep Actions/workflow
  permissions read-only unless a specific workflow needs more access.
- Review README, license, notices and the exact file list. Do not attach local
  unsigned Mac binaries as a supported release. No signed public download exists.
- Keep experimental labels and current limitations; confirm artwork rights before
  publication. The original banner is retained at the project owner's direction.

## Validation

Run `npm ci`, `npm ls --all`, `npm audit`, `npm run lint`, `npm run typecheck`,
`npm run build`, and `bash scripts/check-companion.sh`. Full Xcode/hardware checks
are separate and must remain explicitly unverified until actually performed.
