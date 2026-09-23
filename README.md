# ZGB-template
A template for projects using [ZGB](https://github.com/Zal0/ZGB), A little engine for creating games for the original GameBoy

## Testing

`./smoke-test.sh` builds all four `BUILD_TYPE` variants (Release, Debug, ReleaseColor, DebugColor) and checks that each one produces a non-empty ROM in `bin/`. Requires `ZGB_PATH` to be set, same as a normal build. Run it before committing changes that touch the build or engine integration.
