#!/usr/bin/env bash
# Export the Godot arena project to Roboteer/Resources/arena.pck.
# Works without export templates: --export-pack only packs resources.
set -euo pipefail
# The part catalogue is authored at Shared/parts.json; Godot needs it inside res://.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GODOT="${GODOT:-${HOME}/Applications/Godot.app/Contents/MacOS/Godot}"
ARENA_DIR="${REPO_ROOT}/Arena"
OUT_DIR="${REPO_ROOT}/Roboteer/Resources"
OUT_PCK="${OUT_DIR}/arena.pck"

if [ ! -x "${GODOT}" ]; then
  echo "error: Godot binary not found or not executable: ${GODOT}" >&2
  echo "       set GODOT=/path/to/Godot to override" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"
rm -f "${OUT_PCK}"

echo "Godot: $("${GODOT}" --version)"
echo "Importing ${ARENA_DIR} ..."
cp "$(dirname "$0")/../Shared/parts.json" "$(dirname "$0")/../Arena/data/parts.json"
"${GODOT}" --headless --path "${ARENA_DIR}" --import >/dev/null

echo "Exporting pack to ${OUT_PCK} ..."
"${GODOT}" --headless --path "${ARENA_DIR}" --export-pack "iOS" "${OUT_PCK}"

if [ ! -f "${OUT_PCK}" ]; then
  echo "error: export produced no pck at ${OUT_PCK}" >&2
  exit 1
fi

SIZE_BYTES=$(stat -f%z "${OUT_PCK}")
if [ "${SIZE_BYTES}" -lt 1024 ]; then
  echo "error: pck is only ${SIZE_BYTES} bytes, that cannot be right" >&2
  exit 1
fi

echo "OK: ${OUT_PCK} (${SIZE_BYTES} bytes, $(du -h "${OUT_PCK}" | cut -f1))"
