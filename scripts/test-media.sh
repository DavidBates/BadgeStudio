#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /private/tmp/badge-media.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
xcodebuild -project BadgeStudio.xcodeproj -scheme BadgeStudio -configuration Debug -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath "$test_dir/build" CODE_SIGNING_ALLOWED=NO build > "$test_dir/build.log" 2>&1 || { cat "$test_dir/build.log"; exit 1; }
app="$test_dir/build/Build/Products/Debug-maccatalyst/BadgeStudio.app"
codesign --force --deep --sign - "$app"
BADGE_TEST_OUTPUT="$test_dir/result.txt" "$app/Contents/MacOS/BadgeStudio" --self-test
cat "$test_dir/result.txt"
