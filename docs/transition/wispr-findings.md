# Wispr Flow investigation and CAPA adaptations

## Target and method

Research performed October 23, 2026, using the requested
[Elon Frame skill](/Users/evy/Desktop/repositories/skills/elon-42-question-engine/SKILL.md)
and [evyevans/rea](https://github.com/evyevans/rea).

- Target: `/Applications/Wispr Flow.app`, desktop version `1.6.1253`.
- Container: `Contents/Resources/app.asar`, SHA-256
  `2097584578d26b8dac046af09fdff4d5f16c2cd0657273e1dd7c3c25f8b1bfd0`.
- Local REA checkout at investigation time: version `6.5.0`, commit `fffb074`,
  remote `https://github.com/evyevans/rea.git`.
- Selected sources: root package manifest, bundled recorder AudioWorklet, and
  bundled status renderer. 180 other inventoried files were outside analysis.
- Partial REA Evidence ID:
  `ev_a9c27f5f60251c827a1652cb7105e0ddb4c0cbae5a358ef07eabf2521f5296c5`.
  The original local result was retained at
  `/private/tmp/capa-wispr-rea-evidence.json`; that temporary file is not a
  permanent project artifact and may be removed by the OS.

The analysis reported mismatches between declared hashes and several unpacked
native components. It was explicitly retried in record-and-continue mode without
changing the app. Its final result was `cleanup_incomplete` because process-table
inspection was denied. No further REA target was opened after that result. This
does not establish full application integrity, complete semantic reconstruction,
runtime execution, or iOS behavior. Do not cite it as any of those.

## Findings and implementation decisions

| Evidence | Bounded observation | CAPA adaptation | Verification |
|---|---|---|---|
| Recorder Worklet, direct static source inspection | Stop handles residual buffered samples before emitting completion | Finalize the native recording before recognition reads it | Native recorder finalization implemented; first/last-word device test pending |
| Recorder Worklet | Capture uses explicit start/stop messages and tracks recording state | Listening state follows successful audio capture, not the initial tap | Capture-readiness device test pending |
| Status renderer, static inspection | Separate initializing/listening/stopping/processing/retry/error states exist | Show microphone preparation, recording, transcription, unconfirmed admission, agent work and recoverable errors separately | Bridge state tests; native UI requires Xcode/device validation |
| Status renderer plus Flow's published recovery documentation | Recovery is distinct from a new recording | Retain unsent memos; stable request identity; deliberate discard | Bridge deduplication tests and portable Swift checks; recording hardware test pending |
| Published iOS microphone and permission documentation | iOS capture and permissions differ from desktop | Native permission flow and system audio lifecycle; no desktop hotkey or accessibility injection architecture | Permission/device acceptance cases specified |

These are independent CAPA implementations informed by observed behaviors, not
copies of Flow's proprietary implementation. In particular, CAPA does not embed
Flow, use its backend, extract its credentials, imitate its brand or depend on
its desktop text-insertion mechanism.

## Framing outcome

The consequential question is whether the user can delegate and later be
re-engaged usefully while away from the screen. Transcription alone does not
answer it. Therefore the architecture prioritizes durable Hermes runs,
user-controlled availability, generation-bound replies and verified playback
receipts before UI polish.

Apple's PTT framework, not the desktop Flow artifact, supplies the candidate
background receive-audio mechanism. Suitability for an AI remote participant and
real-world reliability remain open until device and distribution validation.

Supporting vendor documentation:
[Flow hands-free behavior](https://docs.wisprflow.ai/articles/6391241694-use-flow-hands-free),
[missing first words and recording recovery](https://docs.wisprflow.ai/articles/3566082841-fix-missing-first-words-in-transcriptions),
[iOS behavior and permissions](https://docs.wisprflow.ai/articles/6269634092-adapting-to-ios-26-4).
