# Headless test-ROM harness (Tier 2 testing/harnessing)

Status: implemented.

## Context

Part of the 3-tier testing/harnessing plan noted in the ZGB fork's handoff
notes (`HANDOFF-NOTES.md`, "Testing/harness — discussed, not implemented"):

1. Build-matrix smoke test — implemented (`smoke-test.sh` in ZGB-template).
2. **Test-ROM pattern (this doc).**
3. Host-native unit tests for pure logic — not designed yet.

Tier 2 targets logic that depends on real Game Boy hardware timing/behavior
(interrupts, memory-mapped I/O, engine subsystems), which Tier 3's plain
host-native unit tests can't exercise. It runs actual compiled `.gb` ROMs
against a headless emulator core and reads pass/fail out of them.

## Scope decision

The harness is split so it can be reused by any ZGB-based game, not just
this template:

- **ZGB fork (`common/`)** owns the reusable infrastructure: the emulator
  core binding, the assertion macros, and the minimal build recipe for a
  test ROM.
- **Each game repo** (starting with ZGB-template) owns its own test-ROM
  source files — the actual test cases exercising that game's code — and a
  thin script that builds and runs them against the fork's harness.

## Components

### `common/test-harness/` (ZGB fork)

- `peanut_gb.h` — vendored single-header emulator core
  ([deltabeard/peanut-gb](https://github.com/deltabeard/peanut-gb)), chosen
  over SameBoy's scripting/CLI because it embeds directly into a small C
  harness with no GUI and no external process to drive.
- `runner.c` — a host-native C program (compiled with `cc`, not SDCC/GBDK):
  loads a `.gb` file from `argv[1]`, implements Peanut-GB's serial-write
  callback to accumulate output lines, steps the CPU until it sees the
  `DONE` sentinel line or hits a hard cycle-count ceiling (safety net
  against a test that never finishes). Exits 0 only if every reported
  assertion line was `PASS`; exits 1 and prints a summary otherwise
  (including a `TIMEOUT` case if `DONE` was never seen).
- `TestAssert.h` — GBDK-side header for test-ROM authors:
  - `TEST_ASSERT(cond, name)` — writes `PASS <name>` or `FAIL <name>` over
    the serial link depending on `cond`. Both outcomes are written (not
    just failures) so a hang is distinguishable from silent success.
  - `TEST_DONE()` — writes `DONE` and returns normally; the ROM does not
    halt itself. `START()` calls `TEST_DONE()` and returns, and the
    engine's main loop keeps calling `UPDATE()` afterward (a no-op in this
    test). This is harmless in practice because the runner stops advancing
    emulated frames once it sees the `DONE` line, but the code makes no
    halt guarantee.
**Refinement made while writing the implementation plan:** no separate
`Makefile.testrom` turned out to be needed. `MakefileCommon` already
discovers its sources/resources purely from relative paths (`./*.c`,
`../res/*.gbr`, etc.), so a `tests/Makefile` that includes it directly —
exactly like `src/Makefile` does — works unmodified, as long as the test
build uses its own `BUILD_TYPE` value (`TestRom`) so its object directory
never collides with `src/`'s (or, on a case-insensitive filesystem, with
`tests/` itself).

### `tests/` (ZGB-template, and any game repo adopting this)

- `tests/*.c` — one file per test suite, each `#include`-ing
  `TestAssert.h` and exercising real engine/game functions.
- `tests/Makefile` — includes `$(ZGB_PATH)/src/MakefileCommon` directly,
  same pattern as `src/Makefile`.
- `test-rom.sh` (repo root) — analogous to `smoke-test.sh`: builds the
  fork's `runner` binary once, builds all of `tests/*.c` into a single
  test ROM (`bin/ZGB_TEMPLATE_TESTS.gb` — `MakefileCommon` globs every
  `.c` file under `tests/` into one link), and runs the runner against
  that ROM, non-zero exit on any failure.

## Protocol

Plain text lines over the emulated serial link:

```
PASS <name>
FAIL <name>
...
DONE
```

The runner treats anything other than an all-`PASS`-then-`DONE` sequence
as a failure, and a missing `DONE` (cycle ceiling reached) as `TIMEOUT`.

## First test case

To validate the pipeline end-to-end, the first test-ROM in ZGB-template
mirrors `StateGame.c::START()`: calls `SpriteManagerAdd(SpritePlayer, 50,
50)` and `InitScroll(...)` the same way the real game does at startup, then
asserts the returned sprite handle is valid and the scroll position lands
at the expected value. This exercises real ZGB engine code under actual
hardware timing, not just this template's own (currently trivial) game
logic.

## Out of scope for this design

- Tier 3 (host-native unit tests for pure logic) — separate design.
- CI wiring for either `smoke-test.sh` or `test-rom.sh` — both are local
  scripts for now, matching the Tier 1 decision (no CI configured in
  either repo yet).
- Multi-suite / multi-ROM support — all of `tests/*.c` link into a single
  ROM (`bin/ZGB_TEMPLATE_TESTS.gb`); the ZGB engine's state machine only
  ever runs the one state named by `next_state` at boot, so a second
  `tests/StateY.c` would compile and link but never execute at runtime.
  Adding a genuinely independent, separately-runnable test suite requires
  (a) adding a new state to the `STATES` macro in `include/ZGBMain.h`,
  (b) adding a new `tests/StateWhatever.c` implementing that state's
  `START()`/`UPDATE()`, and (c) switching which state `next_state` points
  to — there's no mechanism yet to select which state runs at test-time
  beyond that. This is a real, current limitation, not something this
  plan solved.

## Open follow-ups (not blocking)

- Resolved while writing the implementation plan: the safety net is a
  frame-count ceiling (`gb_run_frame()` is Peanut-GB's actual execution
  primitive, not a raw cycle count), set to 600 frames (~10s of emulated
  time). Measured against the real first test-ROM: `DONE` arrives at
  frame 27, not "the first frame" as originally assumed — MAX_FRAMES
  still gives a wide (~20x) safety margin.
