# Open-source readiness — 2026-10-30

CAPA is prepared as a free experimental Hermes companion under MIT for its original
contributions. The original README banner is preserved byte-for-byte. The older
web interface is a labeled, local sample demo, separate from native agent routing.

## Completed

- Recovered source out of Trash; original retained. No original Git history was present.
- Removed checkout, pricing, mock credential login and external voice-agent widget.
- Removed unused legacy UI snippets with uncertain attribution and unused auth/speech dependencies.
- Added MIT license, third-party notices/license inventory, contribution/security guidance.
- Updated web dependencies and removed incompatible unused postprocessing package.
- Independent readiness review found no material blocker in the reviewed source/docs.
- Tracked-file scan found no matches for the credential patterns checked or excluded
  private artifacts. This is a bounded check, not proof that no secrets ever existed.
- Local memory, credentials, database sidecars, generated builds and signing files
  are ignored and excluded from source publication. Public GitHub noreply commit identity.

## Verification

Fresh web lint, typecheck and production build pass. The 3D demo retains a bundle
size warning. Bridge tests: 43 passed. Shared Swift checks: 52 passed. Native Mac
compilation and iOS syntax/plists pass. Full native iOS build is skipped because
full Xcode/iOS SDK is absent. Live hardware/device acceptance is not claimed.
A historical local smoke-test report in transition notes is not current validation.

Clean `npm ci` and `npm ls --all` pass; the npm audit reports zero known
vulnerabilities on 2026-10-30. pip-audit also reports no known vulnerabilities
for a fresh resolution of the declared Python runtime/test requirements, not
a certification of every older version permitted by their ranges. Advisory data
changes over time; rerun after updates.

## Remaining external steps

- Confirm rights to the original project artwork before public publication; its
  retention was explicitly requested by the project owner. Third-party marks and
  dependencies retain their terms; MIT does not relicense them.
- Create or restore the intended GitHub repository. If restoring, review existing
  history for secrets and integrate without blindly overwriting it.
- Enable and verify GitHub private vulnerability reporting and available secret
  scanning/push protection before announcement; see SECURITY.md and PUBLISHING.md.
- Signing/notarization and physical iPhone/live Hermes acceptance precede any
  supported binary release. No App Store or production-readiness claim is made.

This preparation creates local source history only; it does not create, restore,
push or expose a GitHub repository. No live Hermes configuration or tasks changed.
