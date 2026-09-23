# spec.md

Project decisions and change log for ZGB-template.

## Testing / harness strategy

Agreed 3-tier plan (see `ZGB` fork's handoff notes for full context):

1. **Build-matrix smoke test** — compile all `BUILD_TYPE` variants, check each produces a valid `.gb`/`.gbc`. Implemented here as `smoke-test.sh`.
2. **Test-ROM pattern** — in-ROM assertions reported over the emulated serial port, run headless via Peanut-GB. Implemented here as `test-rom.sh` + `tests/`.
3. **Host-native unit tests** — clang + Unity/cmocka for hardware-independent pure logic, kept separate from hardware-touching code. Not implemented yet.

## Change log

- 2026-09-23: Added `smoke-test.sh` (Tier 1). Builds Release/Debug/ReleaseColor/DebugColor via `make -C src`, verifies a non-empty ROM lands in `bin/` for each. Local-only for now (no CI configured in this repo or in the ZGB fork). Verified both the pass path (all 4 variants) and the failure path (injected a compile error, confirmed the script reports the failing variant and exits non-zero).
- 2026-09-23: Added Tier 2 (`test-rom.sh`, `tests/`). Reuses `MakefileCommon`
  directly (no separate `Makefile.testrom` was needed, unlike the original
  design sketch) via a dedicated `BUILD_TYPE=TestRom` so its object directory
  never collides with `src/`'s (or, on a case-insensitive filesystem, with
  `tests/` itself — `Tests` was the first choice and would have collided).
  Reusable pieces (`runner.c`, `peanut_gb.h`
  vendored at v1.3.0, `TestAssert.h`) live in the ZGB fork under
  `common/test-harness/` and `common/include/`. Verified both the pass path
  and the failure path (temporarily broke an assertion, confirmed
  `test-rom.sh` reports FAIL and exits non-zero).
