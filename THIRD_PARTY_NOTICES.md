# Third-party notices

The MIT license applies to CAPA contributors' original code. Dependencies retain
their own licenses. Review npm's package-lock.json and bridge/pyproject.toml when
redistributing dependencies; retain their notices where required.

Hermes, Apple, provider names and icons identify external products; no affiliation
or endorsement is implied. Simple Icons artwork and provider marks have their own
terms. Unused legacy glowing-effect components with uncertain attribution and the external
ElevenLabs widget were removed from this distribution. MIT does not relicense
any remaining third-party dependency or mark.
The original CAPA banner has been retained at the owner's request.

See the [npm license inventory](docs/DEPENDENCY_LICENSES.md) for installed package metadata.
Python dependencies are FastAPI (MIT), Uvicorn (BSD-3-Clause), HTTPX (BSD-3-Clause),
PyJWT (MIT), cryptography (Apache-2.0 OR BSD-3-Clause), and pytest (MIT); transitive
dependencies retain their respective licenses. Swift clients use Apple system
frameworks under Apple SDK terms and the local CAPA core, not vendored Hermes code.
