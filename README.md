# ZGB-template
A template for projects using [ZGB](https://github.com/Zal0/ZGB), A little engine for creating games for the original GameBoy

## Testing

`./smoke-test.sh` builds all four `BUILD_TYPE` variants (Release, Debug, ReleaseColor, DebugColor) and checks that each one produces a non-empty ROM in `bin/`. Requires `ZGB_PATH` to be set, same as a normal build. Run it before committing changes that touch the build or engine integration.

`./test-rom.sh` builds and runs the first headless test-ROM (Tier 2): a real ZGB build whose `tests/StateGame.c` asserts on engine behavior (`SpriteManagerAdd`, `InitScroll`) and reports PASS/FAIL/timeout by running under a headless emulator (Peanut-GB) instead of a GUI. Requires `ZGB_PATH` to be set, same as the other scripts here.
