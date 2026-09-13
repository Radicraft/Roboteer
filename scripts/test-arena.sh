#!/usr/bin/env bash
# Run the headless Godot bridge contract test. Exit code is the test's.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GODOT="${GODOT:-${HOME}/Applications/Godot.app/Contents/MacOS/Godot}"
ARENA_DIR="${REPO_ROOT}/Arena"

if [ ! -x "${GODOT}" ]; then
  echo "error: Godot binary not found or not executable: ${GODOT}" >&2
  echo "       set GODOT=/path/to/Godot to override" >&2
  exit 1
fi

exec "${GODOT}" --headless --path "${ARENA_DIR}" --script tests/bridge_test.gd
