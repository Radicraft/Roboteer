#!/usr/bin/env bash
# Release build for a physical iPhone with the entitlements overridden to an empty set, which is
# what lets automatic signing work from the CLI without Game Center / iCloud on the team profile.
# Serialised: one xcodebuild at a time per Mac, because every build shares the DerivedData tree on
# the build volume. Usage: scripts/build-device.sh [install]
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK=/tmp/roboteer-xcodebuild.lock
until mkdir "$LOCK" 2>/dev/null; do sleep 15; done
trap 'rmdir "$LOCK" 2>/dev/null' EXIT
if [ ! -d /Volumes/RoboteerBuild2 ]; then "$ROOT/scripts/mount-build-volume.sh" || exit 1; fi
if [ -n "$(find "$ROOT" -name '* 2.*' -not -path '*/.git/*' | head -1)" ]; then
  echo "error: iCloud duplicate files present (' 2.' suffix); remove them before building" >&2; exit 1
fi
if [ -n "$(find "$ROOT/Arena" -newer "$ROOT/Roboteer/Resources/arena.pck" -type f -not -path '*/.godot/*' | head -1)" ]; then
  "$ROOT/scripts/export-pck.sh" || exit 1
fi
# The phone: $DEVICE if set, else the first paired physical iPhone devicectl can see (the owner
# has more than one). With a concrete device the build registers it on the team profile itself
# (-allowProvisioningDeviceRegistration), which a generic build cannot do.
DEVICE="${DEVICE:-$(xcrun devicectl list devices 2>/dev/null | grep -v simulated | grep -i "iphone" | grep -i "paired" | head -1 | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}')}"
if [ -n "$DEVICE" ]; then DEST="id=$DEVICE"; else DEST="generic/platform=iOS"; fi
LOG="${TMPDIR:-/tmp}/roboteer-build-$$.log"
xcodebuild build -project "$ROOT/Roboteer.xcodeproj" -scheme Roboteer -configuration Release \
  -destination "$DEST" -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  CODE_SIGN_ENTITLEMENTS="$ROOT/scripts/Empty.entitlements" > "$LOG" 2>&1
STATUS=$?
grep -E "error:|BUILD (SUCCEEDED|FAILED)" "$LOG" | head -20
[ $STATUS -ne 0 ] && { echo "full log: $LOG"; exit $STATUS; }
APP="$(ls -dt "$HOME"/Library/Developer/Xcode/DerivedData/Roboteer-*/Build/Products/Release-iphoneos/Roboteer.app | head -1)"  # newest: several DerivedData trees exist
echo "app: $APP"
if [ "${1:-}" = "install" ]; then
  [ -z "$DEVICE" ] && { echo "error: no paired iPhone found; plug one in and trust the Mac" >&2; exit 1; }
  xcrun devicectl device install app --device "$DEVICE" "$APP" 2>&1 | grep -E "error|App installed|installed" | head -3
fi
