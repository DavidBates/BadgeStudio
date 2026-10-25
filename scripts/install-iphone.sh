#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 1 || -z "$1" ]]; then
  echo 'Usage: DEVELOPMENT_TEAM=YOUR_TEAM_ID BUNDLE_ID=com.example.yourbadgeapp ./scripts/install-iphone.sh DEVICE_ID' >&2
  exit 2
fi
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple development team ID}"
: "${BUNDLE_ID:?Set BUNDLE_ID to your unique app bundle identifier}"
device="$1"
xcodebuild -project BadgeStudio.xcodeproj -scheme BadgeStudio -configuration Debug -destination "id=$device" -derivedDataPath build -allowProvisioningUpdates "DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM" "PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID" build
xcrun devicectl device install app --device "$device" build/Build/Products/Debug-iphoneos/BadgeStudio.app
xcrun devicectl device process launch --device "$device" "$BUNDLE_ID"
