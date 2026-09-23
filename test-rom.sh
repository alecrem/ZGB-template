#!/usr/bin/env bash
# Headless test-ROM harness: builds the host-native runner, builds the
# test ROM, and runs the ROM under the runner to get a pass/fail result.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER_SRC="$ZGB_PATH/test-harness/runner.c"
RUNNER_BIN="$SCRIPT_DIR/.test-rom-runner"

if [ -z "${ZGB_PATH:-}" ]; then
  echo "ZGB_PATH is not set." >&2
  exit 1
fi

echo "== Building runner =="
if ! cc -std=c99 -Wall -Wextra -O2 -o "$RUNNER_BIN" "$RUNNER_SRC"; then
  echo "FAIL (runner failed to compile)"
  exit 1
fi

echo "== Building test ROM =="
if ! make -C "$SCRIPT_DIR/tests" clean BUILD_TYPE=TestRom; then
  echo "FAIL (tests clean failed)"
  exit 1
fi
if ! make -C "$SCRIPT_DIR/tests" BUILD_TYPE=TestRom; then
  echo "FAIL (tests build failed)"
  exit 1
fi

ROM="$SCRIPT_DIR/bin/ZGB_TEMPLATE_TESTS.gb"
if [ ! -s "$ROM" ]; then
  echo "FAIL (no non-empty ROM at $ROM)"
  exit 1
fi

echo "== Running test ROM =="
"$RUNNER_BIN" "$ROM"
RESULT=$?

if [ $RESULT -eq 0 ]; then
  echo "test-rom.sh: PASS"
else
  echo "test-rom.sh: FAIL"
fi
exit $RESULT
