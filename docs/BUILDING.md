# Building

This core is built on Linux. The result, `core.wbx`, is one file that runs in
Chimera on Linux and on Windows.

## What is needed

- GCC 13 or newer (C and C++), meson, ninja, make, git, python3.
- A checkout of Chimera with miniBox built, with its C++ guest toolchain
  (Chimera's `AGENTS.md`, "Build"). Below, `<miniBox>` is its
  `extern/chimera-common-minibox` folder.
- For the tests: the AVR compiler (on Debian and Ubuntu the packages
  `gcc-avr`, `binutils-avr` and `avr-libc`) and, for the comparison with
  upstream's uzem, SDL 2's development files (`libsdl2-dev`).

## uzem's source

The Uzebox repository is a submodule, `extern/uzebox`, at a commit of its
master branch:

```sh
git submodule update --init
```

The core compiles uzem's `avr8.cpp`, `uzerom.cpp` and `SDEmulator.cpp` from
`tools/uzem`, with upstream's defines but without SDL and without the
debugger (`NOGDB`, which upstream's Makefile also offers). A change to uzem
is kept as a numbered patch in `patches/`. `waterbox/apply-patches.sh` lays
the patches over the submodule (the build runs it; it does nothing to a tree
that has them). To make a patch, edit the files in `extern/uzebox`, build and
test, add the file to the list in `waterbox/make-patches.sh` if it is new,
and run that script. uzem's files end their lines the Windows way; keep them
so, or the patch becomes the whole file.

## The two flavors

- `native`: for the host. `run-native` is the reference the tests compare
  the sandbox with.
- `guest`: for miniBox's sandbox. This is `core.wbx`, and `run-wbx` runs it.

```sh
meson setup build/meson-native -Dminibox_dir=<miniBox> && ninja -C build/meson-native
waterbox/setup-guest.sh -m <miniBox> && ninja -C build/meson-guest
```

Both runners take a work folder that holds what the sandbox would see: the
game under its name, a file `slots` (`{"game":["game.uze"]}`, with
`"savedata":["eeprom.bin"]` for a saved EEPROM) and a file `settings` (`{}`
or, say, `{"p1Controller":"mouse"}`). `waterbox/gate-harness.h` lists the
options they share (`--frames`, `--report`, `--press`, `--axis`,
`--vid-out`, `--av-stream`, `--dump-domain`, `--savedata-out`,
`--list-panel`). `tests/bgra-to-png.py` turns a `--vid-out` picture into a
PNG.

## The package

```sh
waterbox/build-package.sh -r <chimera checkout>
```

builds the sandbox core and writes `build/Cores/uzem.chimeraCore` in that
checkout. `tests/make-project.py` writes a project for a game, which
Chimera's `chimera-run --project` then plays.

## The tests

```sh
CHIMERA_ROOT=<chimera checkout> bash waterbox/run-gate.sh
TMPDIR=$PWD/build/t bash tests/run-frontend.sh --chimera-root <chimera checkout>
```

The first runs every test and says, for each, what was compared. It needs no
file of anyone's: it builds a test program of this repository's
(`tests/testprog/testprog.c`, on the Uzebox kernel), which reads every
control into its memory, and the Uzebox repository's own games
(`tests/build-demos.sh`). It also builds upstream's own uzem
(`tests/build-upstream-uzem.sh`), lets it record a movie of some of those
games with a stand-in for ffmpeg that keeps the raw pictures and sound
(`tests/upstream-ffmpeg.sh`), and compares them with the core's
(`tests/compare-upstream.py`). The second runs the package in Chimera's
window, run headless (no display is needed); it needs Chimera built with its
window (`tools/ci-chimera.sh`).

Chimera's own checks of a package:

```sh
CHIMERA_CORES_DIR=<folder with the package> <chimera>/build/meson-linux/source/ui/test-packages
```

run in the Chimera checkout.
