#!/bin/bash
# Roboteer's build trees live on the external drive inside an APFS sparse image, because the
# internal disk is nearly full and the ExFAT drive cannot hold Xcode build trees directly.
# ~/Build (the custom SwiftGodotKit with the simulator OpenGL slice) and the Roboteer DerivedData
# folder are symlinks into /Volumes/RoboteerBuild. Run this before building if that volume is not mounted.
set -euo pipefail
IMG="/Volumes/New Volume/RoboteerBuild.sparsebundle"
if [ -d /Volumes/RoboteerBuild ]; then echo "RoboteerBuild already mounted"; exit 0; fi
if [ ! -d "$IMG" ]; then echo "error: $IMG not found; plug in the external drive (New Volume)" >&2; exit 1; fi
hdiutil attach -quiet "$IMG" -mountpoint /Volumes/RoboteerBuild
echo "mounted /Volumes/RoboteerBuild"
