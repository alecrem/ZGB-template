# Headless test-ROM harness (Tier 2 testing/harnessing)

Status: design approved by user, not yet implemented.

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
  - `TEST_DONE()` — writes `DONE`, then the ROM halts (infinite loop).
- `Makefile.testrom` — minimal build recipe (analogous to
  `MakefileCommon`, but without requiring a full game's resource set) that
  turns one test `.c` file into one small `.gb`.

### `tests/` (ZGB-template, and any game repo adopting this)

- `tests/*.c` — one file per test suite, each `#include`-ing
  `TestAssert.h` and exercising real engine/game functions.
- `tests/Makefile` — includes `$(ZGB_PATH)/test-harness/Makefile.testrom`,
  same pattern as `src/Makefile` including `MakefileCommon`.
- `test-rom.sh` (repo root) — analogous to `smoke-test.sh`: builds the
  fork's `runner` binary once, builds each `tests/*.c` to its own `.gb`,
  runs the runner against each, aggregates PASS/FAIL/TIMEOUT across all
  test ROMs, non-zero exit on any failure.

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
- Multi-ROM-per-binary aggregation — each test suite file currently
  compiles to its own standalone `.gb`; revisit if per-ROM build time
  becomes a problem.

## Open follow-ups (not blocking)

- Exact cycle-count ceiling for the timeout safety net needs picking
  empirically once `runner.c` exists (needs to comfortably exceed the
  longest real test's runtime without making a genuine hang take too long
  to report).
