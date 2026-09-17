#!/usr/bin/env bash
set -euo pipefail

# Use the same Sparkle framework that CocoaPods resolved for the example app.
sparkle_dir=$(cd "${1:?Pass the directory containing Sparkle.framework}" && pwd)
tests_dir=$(cd "$(dirname "$0")" && pwd)
developer_dir="$(xcrun --sdk macosx --show-sdk-platform-path)/Developer"
frameworks_dir="$developer_dir/Library/Frameworks"
libraries_dir="$developer_dir/usr/lib"
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
test_app="$build_dir/AutoUpdaterTests.app/Contents"
mkdir -p "$test_app/MacOS"
# Sparkle stores scheduling preferences under the host's bundle identifier.
cat > "$test_app/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.getlantern.auto-updater-tests.$(uuidgen)</string>
<key>CFBundleExecutable</key><string>AutoUpdaterTests</string>
</dict></plist>
EOF

xcrun --sdk macosx swiftc -module-cache-path "$build_dir/module-cache" \
  -F "$sparkle_dir" -F "$frameworks_dir" \
  -I "$libraries_dir" -L "$libraries_dir" \
  -Xlinker -rpath -Xlinker "$sparkle_dir" \
  -Xlinker -rpath -Xlinker "$frameworks_dir" \
  -Xlinker -rpath -Xlinker "$developer_dir/Library/PrivateFrameworks" \
  -Xlinker -rpath -Xlinker "$libraries_dir" \
  "$tests_dir/../Classes/AutoUpdater.swift" "$tests_dir/AutoUpdaterTests.swift" \
  -o "$test_app/MacOS/AutoUpdaterTests"
"$test_app/MacOS/AutoUpdaterTests"
