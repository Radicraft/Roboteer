#!/usr/bin/env bash
# Run every Godot test in Arena/tests in sequence, in a visible window by default (about 6x slower;
# HEADLESS=1 scripts/test-arena.sh is the fast invisible run, and the owner is fine with it).
#
#   scripts/test-arena.sh              run them all
#   scripts/test-arena.sh rules_test   run one (name with or without .gd)
#   GODOT=/path/to/Godot scripts/test-arena.sh
#
# Each test is an `extends SceneTree` script that prints PASS / FAIL lines and exits 0
# only when every check passed. A test whose prerequisites are absent prints SKIP and
# exits 0 (determinism_test does this when agent P's bot scene is missing).
#
# The exit code is 0 only if every test exited 0. The whole suite runs even when one
# fails, so one broken test does not hide the others.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GODOT="${GODOT:-${HOME}/Applications/Godot.app/Contents/MacOS/Godot}"
ARENA_DIR="${REPO_ROOT}/Arena"
DISPLAY_ARGS=""
[ "${HEADLESS:-0}" = "1" ] && DISPLAY_ARGS="--headless"

if [ ! -x "${GODOT}" ]; then
  echo "error: Godot binary not found or not executable: ${GODOT}" >&2
  echo "       set GODOT=/path/to/Godot to override" >&2
  exit 1
fi

# A non editor Godot run cannot resolve `class_name` globals (FightTypes, Bot, FightRules
# and the rest) unless Arena/.godot/global_script_class_cache.cfg exists, and that file is
# written by the editor, not by the game. Arena/.godot is gitignored, so on a fresh clone
# the first thing to do is build it. `--import` does that headlessly in a few seconds.
# Always re-import: a newly added class_name is not resolvable until the class cache is rebuilt.
"${GODOT}" ${DISPLAY_ARGS} --path "${ARENA_DIR}" --import >/dev/null 2>&1 || true

# Test order: the contract first, then the pure rules and the AI, then the other agents'
# suites, then the slow integration test that needs a physics world. Anything in tests/
# that is not listed here still runs, after these.
ORDER=(bridge_test.gd rules_test.gd ai_test.gd ui_test.gd fx_test.gd physics_test.gd builds_test.gd determinism_test.gd)

tests=()
if [ "$#" -gt 0 ]; then
  for arg in "$@"; do
    name="${arg%.gd}.gd"
    if [ ! -f "${ARENA_DIR}/tests/${name}" ]; then
      echo "error: no such test: Arena/tests/${name}" >&2
      exit 1
    fi
    tests+=("${name}")
  done
else
  for name in "${ORDER[@]}"; do
    [ -f "${ARENA_DIR}/tests/${name}" ] && tests+=("${name}")
  done
  # Anything new in tests/ that is not in ORDER still runs, so a test cannot be
  # added and silently never run. Files starting with _ are helpers, not tests.
  for path in "${ARENA_DIR}"/tests/*.gd; do
    [ -e "${path}" ] || continue
    name="$(basename "${path}")"
    case "${name}" in _*) continue ;; esac
    case " ${tests[*]:-} " in *" ${name} "*) continue ;; esac
    tests+=("${name}")
  done
fi

if [ "${#tests[@]}" -eq 0 ]; then
  echo "error: no tests found in ${ARENA_DIR}/tests" >&2
  exit 1
fi

failed=()
for name in "${tests[@]}"; do
  echo ""
  echo "=============================================================="
  echo "  ${name}"
  echo "=============================================================="
  out="$("${GODOT}" ${DISPLAY_ARGS} --path "${ARENA_DIR}" --script "tests/${name}" 2>&1)"
  status=$?
  printf '%s\n' "${out}"
  # A script that fails to load or parse exits 0 with no checks run; treat that as a failure,
  # and require at least one PASS/SKIP/checks line so a silent test cannot pass.
  # Note: never `grep -q` here; with pipefail a grep that quits early kills printf with SIGPIPE
  # and the pipeline reads as failed on large outputs. Count matches instead.
  err_hits="$(printf '%s' "${out}" | grep -c -E "SCRIPT ERROR|Failed to load script|Parse Error|Could not resolve class" || true)"
  ok_hits="$(printf '%s' "${out}" | grep -c -E "PASS|SKIP|checks" || true)"
  if [ "${err_hits}" -gt 0 ]; then
    status=97
  elif [ "${ok_hits}" -eq 0 ]; then
    status=98
  fi
  if [ "${status}" -ne 0 ]; then
    failed+=("${name} (exit ${status})")
  fi
done

echo ""
echo "=============================================================="
if [ "${#failed[@]}" -eq 0 ]; then
  echo "  PASS  ${#tests[@]} test files, 0 failures"
  echo "=============================================================="
  exit 0
fi
echo "  FAIL  ${#failed[@]} of ${#tests[@]} test files failed:"
for entry in "${failed[@]}"; do
  echo "        ${entry}"
done
echo "=============================================================="
exit 1
