#!/usr/bin/env bash
# Simulator build, for LAYOUT CHECKS ONLY (headless screenshots, no window: the owner is at the
# Mac). Same serialised lock as scripts/build-device.sh, because every build on this Mac shares
# one DerivedData tree. Usage: scripts/build-sim.sh
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
LOG="${TMPDIR:-/tmp}/roboteer-build-sim-$$.log"
xcodebuild build -project "$ROOT/Roboteer.xcodeproj" -scheme Roboteer -configuration Debug \
  -destination 'generic/platform=iOS Simulator' > "$LOG" 2>&1
STATUS=$?
grep -E "error:|warning: .*(Roboteer/)|BUILD (SUCCEEDED|FAILED)" "$LOG" | head -40
[ $STATUS -ne 0 ] && { echo "full log: $LOG"; exit $STATUS; }
APP="$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/Roboteer-*/Build/Products/Debug-iphonesimulator/Roboteer.app | head -1)"
echo "app: $APP"
