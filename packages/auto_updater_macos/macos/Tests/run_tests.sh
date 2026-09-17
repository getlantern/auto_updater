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

xcrun --sdk macosx swiftc -module-cache-path "$build_dir/module-cache" \
  -F "$sparkle_dir" -F "$frameworks_dir" \
  -I "$libraries_dir" -L "$libraries_dir" \
  -Xlinker -rpath -Xlinker "$sparkle_dir" \
  -Xlinker -rpath -Xlinker "$frameworks_dir" \
  -Xlinker -rpath -Xlinker "$developer_dir/Library/PrivateFrameworks" \
  -Xlinker -rpath -Xlinker "$libraries_dir" \
  "$tests_dir/../Classes/AutoUpdater.swift" "$tests_dir/AutoUpdaterTests.swift" \
  -o "$build_dir/AutoUpdaterTests"
"$build_dir/AutoUpdaterTests"
