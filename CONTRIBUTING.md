# Contributing

CAPA is an experimental Hermes companion. Small fixes, clear documentation and
reproducible reports are welcome. No response-time or maintenance commitment is made.

Keep the browser showcase visibly simulated. Keep agent execution/tool credentials
in Hermes, and preserve notifications as the default. Do not claim success before
Hermes confirms it. Preserve request identity on uncertain retries and require
exact current controls for approvals/clarifications.

For changes, describe the behavior and how you checked it. Run `npm run typecheck`
and `npm run build` for web changes and `bash scripts/check-companion.sh` for
companion changes. Report skipped SDK/hardware checks explicitly. Do not include
real tasks, transcripts, pairing codes, database files or credentials in reports.
