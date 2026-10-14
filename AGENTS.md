# AGENTS.md - Uzebox core for Chimera

This repository builds uzem, the Uzebox's own emulator
(https://github.com/Uzebox/uzebox, tools/uzem), as a core for Chimera
(https://github.com/ToolAssisted-run/chimera), a frontend for tool-assisted
speedruns. It produces one file, `uzem.chimeraCore`: uzem compiled to run
inside Chimera's sandbox (miniBox), a small program around it, and the
declarations Chimera reads (buttons, settings, file types).

Read [docs/BUILDING.md](docs/BUILDING.md) before building and
[docs/PLAN.md](docs/PLAN.md) before changing how the core works: it is the
design log, with what was decided, why, and what was measured.

## Layout

- `extern/uzebox` - the Uzebox repository at a commit of its master branch, a
  submodule. Only `tools/uzem` is compiled into the core; the kernel and the
  games are built by the tests. Never edited in place: a change is a
  numbered patch in `patches/`, laid over the submodule by
  `waterbox/apply-patches.sh` and written by `waterbox/make-patches.sh` (its
  list says which file is in which patch; a file is in one patch, whole).
  Every change is inside `#ifdef CHIMERA_CORE` with a comment that says why.
  uzem's files have Windows line ends, which the patch keeps.
- `meson.build` - the build of both flavors.
- `waterbox/cinterface.cpp` - the program around uzem in place of upstream's
  `uzem.cpp`: it loads the game and the EEPROM, sets the controls before each
  frame, runs the machine to the end of a picture, keeps the picture and the
  sound, and is what Chimera's engine calls. It also defines `rand()`.
- `waterbox/waterbox.config`, `file_slots.json`, `default_keybinds.json`,
  `package-licenses.json` - what the package declares. `licenses/` holds
  uzem's licence texts, which its source files carry at their top.
- `waterbox/run-native.c`, `waterbox/run-wbx.c` - the native runner and the
  sandbox runner. They take the same options and print the same lines
  (`waterbox/gate-harness.h` is the part they share).
- `waterbox/*.sh` - `apply-patches.sh`, `make-patches.sh`, `setup-guest.sh`
  (configures the sandbox build), `build-package.sh`, `run-gate.sh` (the
  test script).
- `tests/` - `testprog/testprog.c` and `build-testprog.sh` (the test
  program, on the Uzebox kernel), `make-uze.py` (a .uze from a .hex),
  `results.py` (reads what the test program left in memory),
  `build-demos.sh` (the Uzebox's games), `build-upstream-uzem.sh`,
  `upstream-ffmpeg.sh` and `compare-upstream.py` (the comparison with
  upstream's uzem), `check-key-names.py`, `run-frontend.sh` (the window
  test, with its helpers), `make-project.py` (writes a project),
  `bgra-to-png.py` (a picture the runners leave, to look at).
- `build/` - every build output, ignored by git.

## Build and test

```sh
git submodule update --init
meson setup build/meson-native -Dminibox_dir=<miniBox> && ninja -C build/meson-native
waterbox/setup-guest.sh -m <miniBox> && ninja -C build/meson-guest
waterbox/build-package.sh -r <chimera checkout>
CHIMERA_ROOT=<chimera checkout> bash waterbox/run-gate.sh
TMPDIR=$PWD/build/t bash tests/run-frontend.sh --chimera-root <chimera checkout>
```

The tests need the AVR compiler (avr-gcc, avr-libc) on the PATH, and SDL 2's
development files for the comparison with upstream's uzem. Run both test
scripts before every commit that touches what they cover, and say in the
commit what ran, with the numbers. A new test is broken on purpose once and
seen to fail.

## Rules of the repository

- **uzem's machine, as upstream has it.** The patch takes SDL out (the
  window, the sound device, the host's keyboard and joysticks) and hands the
  picture, the sound, the controls and a stop to `cinterface.cpp`; nothing
  of the emulation is changed. The tests `upstream:*` compare the core's
  pictures and sound with upstream's own uzem, frame by frame. A difference
  there is a bug to find, not to accept.
- **The same numbers in both builds.** `rand()`, which uzem uses for the
  watchdog's drift, is defined in the core as the sandbox's C library has it
  and started from the Random Seed setting, never from a clock.
- **Nothing from outside the machine.** No SD card, no network adapter, no
  files but the project's.
- **The machine's state is its memory.** A savestate is the sandbox's copy
  of the core's memory, uzem's keyboard queue and EEPROM included.
- **The controls are in two places that must agree**: the tables in
  `cinterface.cpp` and the `input` in `waterbox.config`. The test
  `package:controls` compares them; `package:key-names` checks the default
  bindings name keys Chimera knows.
- **Say what was not tried.** A game that was not run has not been shown to
  work.
- **Write in plain language**: commit messages, documents, comments and
  setting descriptions are read by people who have never seen this
  repository. `.md` files are ASCII.
- **Commits**: `type(scope): what changed`; a short body with what changed,
  why, and how it was tested, with the numbers. Stage explicit paths. No
  amending, no force push.

## What is the owner's to decide

Publishing, the roster row in Chimera, moving to another Uzebox commit, and
anything a licence does not plainly allow.
