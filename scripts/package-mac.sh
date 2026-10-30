#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
task_cache="${TMPDIR:-/tmp}/capa-mac-package-${UID}"
output="${1:-$repo_root/artifacts/macos}"
mkdir -p "$task_cache" "$output"
export CLANG_MODULE_CACHE_PATH="$task_cache/modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$task_cache/modules"
swift build --package-path "$repo_root/macos" --configuration release \
  --scratch-path "$task_cache/build" --cache-path "$task_cache/cache" --disable-sandbox
binary_dir="$(swift build --package-path "$repo_root/macos" --configuration release \
  --scratch-path "$task_cache/build" --cache-path "$task_cache/cache" --disable-sandbox --show-bin-path)"
app="$output/CAPA.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/CAPAMac" "$app/Contents/MacOS/CAPAMac"
cp "$repo_root/macos/Resources/Info.plist" "$app/Contents/Info.plist"
# Local preview only. Distribution requires a Developer ID and notarization.
codesign --force --sign - --identifier app.capa.companion.mac "$app"
codesign --verify --deep --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/CAPA-Mac-preview.zip"
echo "Local preview: $output/CAPA-Mac-preview.zip"
echo 'This build targets the current Mac architecture and is not notarized.'
