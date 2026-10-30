#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
task_cache="${TMPDIR:-/tmp}/capa-companion-checks-${UID}"
mkdir -p "$task_cache"

(
  cd "$repo_root/bridge"
  python3 -m pytest tests -q
  python3 -m compileall -q capa_bridge
)

export CLANG_MODULE_CACHE_PATH="$task_cache/modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$task_cache/modules"
swift run --package-path "$repo_root/ios/CapaCore" \
  --scratch-path "$task_cache/build" --cache-path "$task_cache/cache" \
  --disable-sandbox CapaCoreChecks

swift build --package-path "$repo_root/macos" \
  --scratch-path "$task_cache/mac" --cache-path "$task_cache/cache" --disable-sandbox
plutil -lint "$repo_root/macos/Resources/Info.plist"

swiftc -frontend -parse "$repo_root"/ios/CAPA/*.swift "$repo_root"/ios/CAPAWidget/*.swift
plutil -lint "$repo_root/ios/CAPA.xcodeproj/project.pbxproj" \
  "$repo_root/ios/CAPA/Info.plist" "$repo_root/ios/CAPA/CAPA.entitlements" \
  "$repo_root/ios/CAPA/PrivacyInfo.xcprivacy" "$repo_root/ios/CAPAWidget/Info.plist"

if xcodebuild -version >/dev/null 2>&1; then
  xcodebuild -project "$repo_root/ios/CAPA.xcodeproj" -scheme CAPA \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$task_cache/native" CODE_SIGNING_ALLOWED=NO build
else
  echo 'Native iOS build SKIPPED: full Xcode and the iOS SDK are required.'
  echo 'Swift syntax and portable core checks passed; native API typechecking is unverified.'
fi
