#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
bridge_python="${1:?Usage: bash scripts/install-bridge.sh /path/to/venv/bin/python}"
build_context="$(mktemp -d "${TMPDIR:-/tmp}/capa-bridge-install.XXXXXX")"
trap 'rm -rf "$build_context"' EXIT
# Do not let an old setuptools build/lib cache replace newer source in a wheel.
cp "$repo_root/bridge/pyproject.toml" "$repo_root/bridge/LICENSE" "$build_context/"
cp -R "$repo_root/bridge/capa_bridge" "$build_context/"
"$bridge_python" -m pip install "$build_context"
"$bridge_python" -c 'from importlib.metadata import version; from capa_bridge.store import Store; assert hasattr(Store, "workspace_for"); print("Installed workspace-aware CAPA bridge", version("capa-bridge"))'
