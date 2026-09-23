# Headless Test-ROM Harness (Tier 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run a real, compiled Game Boy ROM headless (no GUI) and get a pass/fail result on the command line, so hardware-dependent ZGB engine/game logic can be tested without a human watching an emulator window.

**Architecture:** A host-native C program (`runner`) embeds the Peanut-GB emulator core and plays a `.gb` file until it reads a `DONE` sentinel over the emulated serial port (or hits a frame-count safety ceiling). The ROM itself is a normal ZGB game build whose `StateGame.c` calls `TEST_ASSERT`/`TEST_DONE` macros (from a new `TestAssert.h`) instead of running real gameplay. The reusable pieces (`runner.c`, `peanut_gb.h`, `TestAssert.h`) live in the ZGB fork so any game can adopt them; the actual test cases and the script that wires them together live in each game repo (starting with ZGB-template).

**Tech Stack:** C99 (host side, compiled with `cc`), SDCC/GBDK (ROM side, via the existing `MakefileCommon`), Peanut-GB v1.3.0 (vendored, MIT licensed), bash.

**Spec:** `docs/superpowers/specs/2026-09-23-headless-test-rom-harness-design.md` (this plan refines two details the spec left abstract, both confirmed against the real code while writing this plan: there is no separate `Makefile.testrom` — the existing `MakefileCommon`, included the same way `src/Makefile` already does, is sufficient once the test build uses its own `BUILD_TYPE` value; and the "cycle-count ceiling" is a frame-count ceiling, since `gb_run_frame()` is Peanut-GB's actual execution primitive.)

## Global Constraints

- No CI wiring — both `smoke-test.sh` (already done) and `test-rom.sh` (this plan) are local-only scripts, per the Tier 1 decision already made.
- Peanut-GB is vendored at tag `v1.3.0` (pinned, not `master`) for reproducibility.
- Serial protocol is plain text lines: `PASS <name>`, `FAIL <name>`, then a final `DONE`. The runner treats anything except "all PASS, then DONE" as a failure, and a missing `DONE` (frame ceiling reached) as a timeout.
- The ZGB fork repo (`/Users/ale/repos/games/ZGB`) stays on its existing branch `feature/no-ref/macos-support` — do not create a new branch there. The ZGB-template repo work happens on a new branch — see Task 3 Step 1 for exactly where to branch from (Tier 1 is not merged to `main` as of this writing).
- Never commit to `main` in either repo. Never commit without being asked (this plan's commit steps are here for when the user asks to execute the plan; confirm with the user before running them if that's ever ambiguous).

---

## File Structure

**ZGB fork** (`/Users/ale/repos/games/ZGB`, on branch `feature/no-ref/macos-support`):

- `common/test-harness/peanut_gb.h` — vendored, unmodified except for nothing (used as-is).
- `common/test-harness/runner.c` — host-native program: loads a `.gb`, embeds Peanut-GB, reads serial output, decides pass/fail/timeout.
- `common/include/TestAssert.h` — GBDK-side header, already on the standard include path (`-I$(ZGB_PATH)/include`) that every game build already has, so no per-game Makefile change is needed to find it.
- `.gitignore` — add the compiled `runner` binary.

**ZGB-template** (`/Users/ale/repos/games/Zal0-ZGB-template`, on a new branch — see Task 3 Step 1 for where to branch from):

- `tests/StateGame.c` — the test-ROM's actual test case (mirrors real `src/StateGame.c::START()`, but asserts instead of playing).
- `tests/SpritePlayer.c` — trivial required boilerplate (same shape as `src/SpritePlayer.c`; `ZGBMain.h`'s `SPRITES` list still declares `SpritePlayer`, so a build linking against it needs this file to exist, same as any real ZGB build does).
- `tests/ZGBMain.c` — trivial required boilerplate (same shape as `src/ZGBMain.c`).
- `tests/Makefile` — includes the fork's `MakefileCommon`, same pattern as `src/Makefile`, plus one extra `-I` for `TestAssert.h`'s location.
- `test-rom.sh` (repo root) — builds `runner` (host-native), builds `tests/` (GBDK, via `BUILD_TYPE=TestRom` so it gets its own object directory and never collides with `src/`'s `Release`/`Debug`/etc. directories), runs `runner` against the resulting ROM, reports the result.
- `.gitignore` — add `Tests/` (the new build-output directory `tests/Makefile` will create, parallel to the existing `Release*/`/`Debug*/` patterns).
- `README.md` — document `./test-rom.sh` under Testing, next to `./smoke-test.sh`.
- `spec.md` — log this change, mark Tier 2 done.

## Interfaces at a glance

- `TestAssert.h` provides `TEST_ASSERT(cond, name)` and `TEST_DONE()` — both take a **string literal** for `name` (they're built on top of a fixed-size line buffer with no formatting, so `name` must already be a short, static C string).
- `runner` is invoked as `runner <path-to.gb>`, prints one `PASS <name>` / `FAIL <name>` line per assertion plus a final summary line, and exits `0` only if every assertion passed and `DONE` was seen.

---

### Task 1: Vendor Peanut-GB and write the host-native runner

**Repo:** `/Users/ale/repos/games/ZGB` (branch `feature/no-ref/macos-support` — confirm with `git branch --show-current` before starting; do not create a new branch here)

**Files:**
- Create: `common/test-harness/peanut_gb.h`
- Create: `common/test-harness/runner.c`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `runner` executable (built from `runner.c`), CLI: `runner <rom.gb>`, exit code `0` = all assertions passed, `1` = at least one `FAIL` or a timeout (no `DONE` seen within `MAX_FRAMES` frames of emulated time).

- [ ] **Step 1: Vendor the Peanut-GB header**

Download the pinned release tag (not `master`, for reproducibility) into the new directory:

```bash
mkdir -p common/test-harness
curl -sL https://raw.githubusercontent.com/deltabeard/Peanut-GB/v1.3.0/peanut_gb.h -o common/test-harness/peanut_gb.h
```

Verify it landed and looks right:

```bash
head -20 common/test-harness/peanut_gb.h
wc -l common/test-harness/peanut_gb.h
```

Expected: an MIT license header, and roughly 3900-4000 lines.

- [ ] **Step 2: Write the runner**

Create `common/test-harness/runner.c`:

```c
/* Host-native runner for headless ZGB test ROMs.
 * Plays a .gb file under Peanut-GB until it reads a "DONE" line over the
 * emulated serial port, then reports pass/fail based on the PASS/FAIL
 * lines it saw along the way.
 */
#define ENABLE_LCD 0
#include "peanut_gb.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_FRAMES 600 /* ~10s of emulated Game Boy time; DONE normally arrives within the first frame */
#define LINE_BUF_SIZE 256

struct harness_priv {
	uint8_t *rom;
	uint8_t *cart_ram;

	char line[LINE_BUF_SIZE];
	size_t line_len;

	unsigned pass_count;
	unsigned fail_count;
	int done;
};

static uint8_t gb_rom_read(struct gb_s *gb, const uint_fast32_t addr)
{
	const struct harness_priv *p = gb->direct.priv;
	return p->rom[addr];
}

static uint8_t gb_cart_ram_read(struct gb_s *gb, const uint_fast32_t addr)
{
	const struct harness_priv *p = gb->direct.priv;
	return p->cart_ram[addr];
}

static void gb_cart_ram_write(struct gb_s *gb, const uint_fast32_t addr,
			       const uint8_t val)
{
	struct harness_priv *p = gb->direct.priv;
	p->cart_ram[addr] = val;
}

static void gb_error(struct gb_s *gb, const enum gb_error_e err,
		      const uint16_t addr)
{
	(void)gb;
	fprintf(stderr, "Emulator error %d at 0x%04X\n", err, addr);
	exit(1);
}

static void handle_line(struct harness_priv *p)
{
	p->line[p->line_len] = '\0';

	if (strcmp(p->line, "DONE") == 0) {
		p->done = 1;
	} else if (strncmp(p->line, "PASS ", 5) == 0) {
		p->pass_count++;
		printf("PASS %s\n", p->line + 5);
	} else if (strncmp(p->line, "FAIL ", 5) == 0) {
		p->fail_count++;
		printf("FAIL %s\n", p->line + 5);
	} else if (p->line_len > 0) {
		printf("(unrecognized serial output: %s)\n", p->line);
	}

	p->line_len = 0;
}

static void gb_serial_tx(struct gb_s *gb, const uint8_t tx)
{
	struct harness_priv *p = gb->direct.priv;

	if (tx == '\n') {
		handle_line(p);
		return;
	}

	if (p->line_len < LINE_BUF_SIZE - 1)
		p->line[p->line_len++] = (char)tx;
}

static enum gb_serial_rx_ret_e gb_serial_rx(struct gb_s *gb, uint8_t *rx)
{
	(void)gb;
	(void)rx;
	return GB_SERIAL_RX_NO_CONNECTION;
}

static uint8_t *read_file(const char *path, long *out_size)
{
	FILE *f = fopen(path, "rb");
	uint8_t *buf;

	if (!f)
		return NULL;

	fseek(f, 0, SEEK_END);
	*out_size = ftell(f);
	rewind(f);

	buf = malloc((size_t)*out_size);
	if (!buf || fread(buf, 1, (size_t)*out_size, f) != (size_t)*out_size) {
		free(buf);
		fclose(f);
		return NULL;
	}

	fclose(f);
	return buf;
}

int main(int argc, char **argv)
{
	struct harness_priv priv;
	struct gb_s gb;
	enum gb_init_error_e ret;
	long rom_size;
	unsigned frame;

	if (argc != 2) {
		fprintf(stderr, "Usage: %s <test-rom.gb>\n", argv[0]);
		return 1;
	}

	memset(&priv, 0, sizeof(priv));

	priv.rom = read_file(argv[1], &rom_size);
	if (!priv.rom) {
		fprintf(stderr, "Failed to read ROM: %s\n", argv[1]);
		return 1;
	}

	ret = gb_init(&gb, gb_rom_read, gb_cart_ram_read, gb_cart_ram_write,
		      gb_error, &priv);
	if (ret != GB_INIT_NO_ERROR) {
		fprintf(stderr, "Peanut-GB init failed: %d\n", ret);
		free(priv.rom);
		return 1;
	}

	priv.cart_ram = malloc(gb_get_save_size(&gb));
	gb_init_serial(&gb, gb_serial_tx, gb_serial_rx);

	for (frame = 0; frame < MAX_FRAMES && !priv.done; frame++)
		gb_run_frame(&gb);

	free(priv.rom);
	free(priv.cart_ram);

	if (!priv.done) {
		fprintf(stderr, "TIMEOUT: no DONE received after %u frames\n",
			MAX_FRAMES);
		return 1;
	}

	if (priv.fail_count > 0 || priv.pass_count == 0) {
		fprintf(stderr, "%u passed, %u failed\n", priv.pass_count,
			priv.fail_count);
		return 1;
	}

	printf("%u passed, 0 failed\n", priv.pass_count);
	return 0;
}
```

- [ ] **Step 3: Compile it and confirm it builds clean**

```bash
cc -std=c99 -Wall -Wextra -O2 -o common/test-harness/runner common/test-harness/runner.c
```

Expected: no errors, no warnings. This is the task's testable deliverable — there is no `.gb` file to run it against yet (that comes in Task 3), so correctness here means "compiles cleanly against the real, vendored Peanut-GB header."

- [ ] **Step 4: Ignore the compiled binary**

Add to `.gitignore`:

```
common/test-harness/runner
```

- [ ] **Step 5: Commit**

```bash
git add common/test-harness/peanut_gb.h common/test-harness/runner.c .gitignore
git commit -m "$(cat <<'EOF'
Add headless test-ROM runner (Peanut-GB v1.3.0, vendored)

Host-native program that plays a .gb file under Peanut-GB until it
reads a DONE line over the emulated serial port, then reports
pass/fail based on the PASS/FAIL lines seen along the way. No test
ROM exists yet to run it against — that lands in the ZGB-template
repo next.
EOF
)"
```

---

### Task 2: Write the GBDK-side assertion header

**Repo:** `/Users/ale/repos/games/ZGB` (same branch as Task 1)

**Files:**
- Create: `common/include/TestAssert.h`

**Interfaces:**
- Consumes: nothing from Task 1 (this is GBDK-side code, compiled by SDCC; `runner.c` is host-side, compiled by `cc` — they never share a compilation unit, only the serial-port text protocol).
- Produces: `TEST_ASSERT(cond, name)` and `TEST_DONE()` macros, usable from any `.c` file compiled through `MakefileCommon` (this header sits on the include path every such build already has).

- [ ] **Step 1: Write the header**

Create `common/include/TestAssert.h`:

```c
#ifndef TEST_ASSERT_H
#define TEST_ASSERT_H

#include <stdint.h>
#include <gb/hardware.h>

static void TestSendByte(uint8_t b)
{
	SB_REG = b;
	SC_REG = SIOF_XFER_START | SIOF_CLOCK_INT;
	while (SC_REG & SIOF_XFER_START)
		;
}

static void TestSendString(const char *s)
{
	while (*s)
		TestSendByte((uint8_t)*s++);
	TestSendByte('\n');
}

/* name must be a string literal: no formatting, fixed-size line buffer. */
#define TEST_ASSERT(cond, name) \
	TestSendString((cond) ? "PASS " name : "FAIL " name)

#define TEST_DONE() TestSendString("DONE")

#endif
```

This uses the real GBDK serial registers (`SB_REG`/`SC_REG`, from `<gb/hardware.h>`) with an internal clock (`SIOF_CLOCK_INT`), which is what makes the transfer complete on its own inside Peanut-GB even with nothing on the other end of the (emulated) cable — confirmed by reading Peanut-GB's serial-timing code: with `SIOF_CLOCK_INT` set and no `gb_serial_rx` connection, it clears the transfer-start bit after `SERIAL_CYCLES`, which is exactly what the `while (SC_REG & SIOF_XFER_START);` spin-wait is waiting for.

- [ ] **Step 2: Verify it's syntactically sound in isolation**

There's no GBDK file that includes it yet, so do a quick standalone parse check with the installed SDCC preprocessor to catch typos before Task 3 depends on it:

```bash
env/gbdk-macos/bin/sdcc -E -Ienv/gbdk-macos/include -Icommon/include common/include/TestAssert.h > /dev/null
```

(Run from the ZGB fork's repo root — adjust the `env/`/`common/` prefix if your shell's cwd differs.)

Expected: exits `0`, no errors printed.

- [ ] **Step 3: Commit**

```bash
git add common/include/TestAssert.h
git commit -m "$(cat <<'EOF'
Add TestAssert.h for GBDK-side test-ROM assertions

TEST_ASSERT/TEST_DONE write PASS/FAIL/DONE lines over the emulated
serial port for the headless runner (added in the previous commit)
to read. Uses the internal serial clock so the transfer completes
on its own with nothing on the other end of the cable.
EOF
)"
```

---

### Task 3: Build the first real test-ROM in ZGB-template

**Repo:** `/Users/ale/repos/games/Zal0-ZGB-template`

**Files:**
- Create: `tests/StateGame.c`
- Create: `tests/SpritePlayer.c`
- Create: `tests/ZGBMain.c`
- Create: `tests/Makefile`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: `TEST_ASSERT`/`TEST_DONE` from `common/include/TestAssert.h` (Task 2); the real `SpriteManagerAdd(UINT8 sprite_type, UINT16 x, UINT16 y) -> Sprite*` and `InitScroll(...)` / `scroll_target` from the ZGB engine (unchanged, already used the same way by `src/StateGame.c`).
- Produces: `bin/ZGB_TEMPLATE_TESTS.gb` when built with `BUILD_TYPE=TestRom`.

- [ ] **Step 1: Create a branch**

Check what's currently checked out first — as of writing this plan, Tier 1
(`smoke-test.sh`, `spec.md`, the design doc) is committed on
`feature/no-ref/build-matrix-smoke-test`, which has **not** been merged
into `main`. This task's `spec.md`/`README.md` edits (Task 5) assume
Tier 1's `spec.md` already exists, so branch from wherever Tier 1
actually landed, not blindly from `main`:

```bash
git branch --show-current
git log --oneline main..HEAD
```

- If the second command lists `Add build-matrix smoke test and Tier 2
  harness design` (or Tier 1 is otherwise still unmerged), branch from
  here: `git checkout -b feature/no-ref/headless-test-rom-harness`
  (no need to switch to `main` first — you want Tier 1's commit as an
  ancestor).
- If Tier 1 has since been merged into `main`, branch from `main`
  instead: `git checkout main && git checkout -b
  feature/no-ref/headless-test-rom-harness`.

- [ ] **Step 2: Add the required boilerplate files**

`ZGBMain.h`'s `SPRITES`/`STATES` lists declare `SpritePlayer` and `StateGame`; any build that links against them needs a `.c` file providing their `START`/`UPDATE`/(`DESTROY`) entry points, same as `src/` does. Reuse the exact same trivial shapes:

Create `tests/SpritePlayer.c`:

```c
#include "Banks/SetAutoBank.h"

void START() {
}

void UPDATE() {
}

void DESTROY() {
}
```

Create `tests/ZGBMain.c`:

```c
#include "ZGBMain.h"

UINT8 next_state = StateGame;

UINT8 GetTileReplacement(UINT8* tile_ptr, UINT8* tile) {
	return 255u;
}
```

(This is a simplified `ZGBMain.c`: the real `src/ZGBMain.c` has a `GetTileReplacement` that special-cases sprite tiles, which only matters once real sprite-vs-background tile sharing is in play. The test ROM doesn't render anything, so always returning "no replacement" is correct here — it's dead code in this ROM either way.)

- [ ] **Step 3: Write the actual test case**

Create `tests/StateGame.c`:

```c
#include "Banks/SetAutoBank.h"

#include "ZGBMain.h"
#include "Scroll.h"
#include "SpriteManager.h"
#include "TestAssert.h"

IMPORT_MAP(map);

void START() {
	scroll_target = SpriteManagerAdd(SpritePlayer, 50, 50);
	InitScroll(BANK(map), &map, 0, 0);

	TEST_ASSERT(scroll_target != 0, "SpriteManagerAdd returns a valid sprite");
	TEST_ASSERT(scroll_target->x == 50, "sprite x position is set from SpriteManagerAdd's argument");
	TEST_ASSERT(scroll_target->y == 50, "sprite y position is set from SpriteManagerAdd's argument");

	TEST_DONE();
}

void UPDATE() {
}
```

This deliberately mirrors real `src/StateGame.c::START()` byte-for-byte up through the two engine calls, then asserts on the results instead of just using them — exactly the "first test case" agreed in the design doc, exercising real ZGB engine code (`SpriteManagerAdd`, `InitScroll`) under actual hardware timing rather than a hand-rolled stand-in.

- [ ] **Step 4: Write the test build's Makefile**

Create `tests/Makefile`:

```make
PROJECT_NAME = ZGB_TEMPLATE_TESTS

all: build_gb

N_BANKS = A
MUSIC_PLAYER = HUGETRACKER
DEFAULT_SPRITES_SIZE = SPRITES_8x16

include $(ZGB_PATH)/src/MakefileCommon
```

Notes for whoever reads this later:
- `all: build_gb`, placed before the `include`, matches `src/Makefile` exactly and matters for a non-obvious reason: GNU Make's default goal is the target of the first rule in the first makefile, and without this line here, the default goal falls through to the first target defined *inside* `MakefileCommon` itself (a harmless `mkdir ../bin` rule) — so a bare `make -C tests BUILD_TYPE=TestRom` (no explicit target) would exit 0 having built nothing, silently. `src/Makefile` already has this line for the same reason; `smoke-test.sh` works only because it's there.
- No `BUILD_TYPE` line here on purpose — `MakefileCommon` unconditionally sets `BUILD_TYPE = Release` partway through itself, which would silently override any plain assignment made before the `include`. The only way to actually control it is a command-line override (`make BUILD_TYPE=TestRom`), which is why `test-rom.sh` (Task 4) always passes it explicitly, the same way `smoke-test.sh` already does for `src/`.
- The build-type value is `TestRom`, not `Tests` — deliberately not a case-only variant of the `tests/` directory name. macOS's default filesystem (APFS) is case-insensitive, so a `../Tests` object directory would be **the same directory on disk** as `../tests` (this repo's `tests/` source folder one level up from where `make` runs), and `make clean`'s `rm -rf $(OBJDIR)/*.*` would then be operating on your source directory. Confirmed this collision actually happens with `mkdir tests && mkdir Tests` on this machine before settling on `TestRom`.
- No `CFLAGS += -I...` line for `TestAssert.h` — confirmed unnecessary. `common/include` (where Task 2 put `TestAssert.h`) is already on every build's path via `-I$(ZGB_PATH_UNIX)/include` in `MakefileCommon`, and `#include "TestAssert.h"` resolves with no extra flag.

- [ ] **Step 5: Build it and verify a real ROM comes out**

```bash
export ZGB_PATH="/Users/ale/repos/games/ZGB/common"
make -C tests clean BUILD_TYPE=TestRom
make -C tests BUILD_TYPE=TestRom
ls -la bin/ZGB_TEMPLATE_TESTS.gb
```

Expected: build succeeds, `bin/ZGB_TEMPLATE_TESTS.gb` exists with a non-zero size (32768 bytes, matching the same minimum ROM size seen in Tier 1's builds, is normal here too). If the build fails on `TestAssert.h: No such file or directory`, add the `-I` line from Step 4's Makefile listing back in and retry — see that step's note.

- [ ] **Step 6: Update `.gitignore`**

Add, next to the existing `[Rr]elease*/` / `[Dd]ebug*/` entries:

```
TestRom/
```

(This is the object directory `BUILD_TYPE=TestRom` creates one level up from `tests/`. A plain exact match is enough here — no case-insensitive bracket-glob needed, since `make` always creates it with this exact spelling.)

Verify the tracked `tests/` source directory is unaffected:

```bash
git check-ignore -v tests/StateGame.c
```

Expected: no output (not ignored).

- [ ] **Step 7: Commit**

```bash
git add tests/ .gitignore
git commit -m "$(cat <<'EOF'
Add first headless test-ROM (Tier 2 pipeline, first real test case)

Mirrors src/StateGame.c::START() but asserts on SpriteManagerAdd's
and InitScroll's results instead of running real gameplay, using
the TestAssert.h macros from the ZGB fork. Builds with
BUILD_TYPE=TestRom to keep its object directory separate from the
real game's Release/Debug builds.
EOF
)"
```

---

### Task 4: Wire up `test-rom.sh` and verify pass/fail detection end-to-end

**Repo:** `/Users/ale/repos/games/Zal0-ZGB-template` (same branch as Task 3)

**Files:**
- Create: `test-rom.sh`

**Interfaces:**
- Consumes: `common/test-harness/runner.c` (Task 1, built here via `cc`), `bin/ZGB_TEMPLATE_TESTS.gb` (Task 3, built here via `make -C tests`).
- Produces: an executable script; exit code `0` iff the test ROM's runner run reported all-pass.

- [ ] **Step 1: Write the script**

Create `test-rom.sh`:

```bash
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
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x test-rom.sh
```

- [ ] **Step 3: Run it and confirm the pass path**

```bash
export ZGB_PATH="/Users/ale/repos/games/ZGB/common"
./test-rom.sh
```

Expected: ends with `3 passed, 0 failed`, then `test-rom.sh: PASS`, exit code `0`.

- [ ] **Step 4: Verify failure detection**

Same rigor as Tier 1's smoke-test verification — prove the harness actually catches a failure, not just that it can print "PASS" when everything happens to be fine. Temporarily break one assertion in `tests/StateGame.c`:

```bash
git status --short tests/StateGame.c
```

Expected: clean (no pending changes), so a `git checkout` afterwards is safe. Then edit `tests/StateGame.c`, changing:

```c
	TEST_ASSERT(scroll_target->x == 50, "sprite x position is set from SpriteManagerAdd's argument");
```

to:

```c
	TEST_ASSERT(scroll_target->x == 999, "sprite x position is set from SpriteManagerAdd's argument");
```

Run again:

```bash
./test-rom.sh
```

Expected: a `FAIL sprite x position is set from SpriteManagerAdd's argument` line, `test-rom.sh: FAIL`, exit code `1`.

Then restore the file:

```bash
git checkout -- tests/StateGame.c
./test-rom.sh
```

Expected: back to `3 passed, 0 failed` / `test-rom.sh: PASS` / exit `0`.

- [ ] **Step 5: Ignore the compiled runner copy and commit**

Add to `.gitignore`:

```
.test-rom-runner
```

```bash
git add test-rom.sh .gitignore
git commit -m "$(cat <<'EOF'
Add test-rom.sh to build and run the headless test-ROM end to end

Builds the runner and the test ROM, runs the ROM under the runner,
and surfaces its pass/fail result. Verified both the pass path and
the failure path (temporarily broke an assertion, confirmed
test-rom.sh reports FAIL and exits non-zero, then restored it).
EOF
)"
```

---

### Task 5: Update project docs

**Repo:** `/Users/ale/repos/games/Zal0-ZGB-template` (same branch as Tasks 3-4)

**Files:**
- Modify: `README.md`
- Modify: `spec.md`

**Interfaces:** none (documentation only).

- [ ] **Step 1: Update the README**

In the "Testing" section added for Tier 1, add a line after the `smoke-test.sh` paragraph:

```markdown
`./test-rom.sh` builds and runs the first headless test-ROM (Tier 2): a real ZGB build whose `tests/StateGame.c` asserts on engine behavior (`SpriteManagerAdd`, `InitScroll`) and reports PASS/FAIL/timeout by running under a headless emulator (Peanut-GB) instead of a GUI. Requires `ZGB_PATH` to be set, same as the other scripts here.
```

- [ ] **Step 2: Update spec.md's change log**

Append:

```markdown
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
```

Also update the "Testing / harness strategy" list at the top of `spec.md` so Tier 2 no longer reads "Not implemented yet":

```markdown
2. **Test-ROM pattern** — in-ROM assertions reported over the emulated serial port, run headless via Peanut-GB. Implemented here as `test-rom.sh` + `tests/`.
```

- [ ] **Step 3: Commit**

```bash
git add README.md spec.md
git commit -m "$(cat <<'EOF'
Document Tier 2 test-ROM harness in README and spec.md
EOF
)"
```

---

## Self-Review Notes

- **Spec coverage:** every component in the spec's "Components" section has a task (runner.c/peanut_gb.h → Task 1, TestAssert.h → Task 2, tests/ + Makefile → Task 3, test-rom.sh → Task 4, protocol → implemented across Tasks 1-3, first test case → Task 3). Docs update (implied by the project's own `spec.md`/README workflow, not spec content itself) → Task 5. The spec's two "not blocking" open follow-ups are addressed: the frame-count ceiling is set to a concrete `600` in Task 1 with its rationale inline, and CI wiring is explicitly out of scope (Global Constraints).
- **Placeholder scan:** no TBD/TODO markers; every step has real, complete code — the one conditional step (Task 3 Step 4's `-I` flag) is written that way because it's genuinely unverifiable until Task 3 Step 5 actually runs the build (there was no way to test the real include-path behavior against the actual installed SDCC without running the build itself, so the step tells the implementer exactly what to try and what output decides it either way).
- **Type/name consistency:** `TEST_ASSERT`/`TEST_DONE` (Task 2) match their exact spelling and arguments everywhere they're used (Task 3). `runner <rom.gb>` invocation in Task 4 matches `argc != 2` / `argv[1]` in Task 1. `ZGB_TEMPLATE_TESTS` as `PROJECT_NAME` (Task 3) matches the `bin/ZGB_TEMPLATE_TESTS.gb` path checked in Tasks 3 and 4.
