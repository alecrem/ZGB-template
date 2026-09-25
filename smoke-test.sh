#!/usr/bin/env bash
# Build-matrix smoke test: compiles every BUILD_TYPE variant and checks
# that each one produced a non-empty .gb/.gbc ROM in bin/.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_TYPES=(Release Debug ReleaseColor DebugColor)
FAILED=()

for BUILD_TYPE in "${BUILD_TYPES[@]}"; do
  echo "== $BUILD_TYPE =="

  if ! make -C "$SCRIPT_DIR/src" clean "BUILD_TYPE=$BUILD_TYPE"; then
    echo "FAIL $BUILD_TYPE (clean failed)"
    FAILED+=("$BUILD_TYPE")
    continue
  fi

  if ! make -C "$SCRIPT_DIR/src" "BUILD_TYPE=$BUILD_TYPE"; then
    echo "FAIL $BUILD_TYPE (build failed)"
    FAILED+=("$BUILD_TYPE")
    continue
  fi

  ROMS=("$SCRIPT_DIR"/bin/*.gb "$SCRIPT_DIR"/bin/*.gbc)
  ROM=""
  for candidate in "${ROMS[@]}"; do
    if [ -f "$candidate" ]; then
      ROM="$candidate"
      break
    fi
  done

  if [ -z "$ROM" ] || [ ! -s "$ROM" ]; then
    echo "FAIL $BUILD_TYPE (no non-empty ROM in bin/)"
    FAILED+=("$BUILD_TYPE")
    continue
  fi

  echo "PASS $BUILD_TYPE ($ROM, $(wc -c < "$ROM") bytes)"
done

echo
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "All build variants OK."
  exit 0
else
  echo "Failed variants: ${FAILED[*]}"
  exit 1
fi
