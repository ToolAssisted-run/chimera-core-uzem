# chimera-core-uzem

A core for [Chimera](https://github.com/ToolAssisted-run/chimera), the
frontend for tool-assisted speedruns, for the **[Uzebox](https://uzebox.org)**,
the open-source game console. It is built on uzem, the Uzebox's own
emulator, from the [Uzebox repository](https://github.com/Uzebox/uzebox), and
produces one file, `uzem.chimeraCore`, that goes in Chimera's `cores` folder.

## Status

New, and not published yet.

- Every game and demo in the Uzebox repository runs, built from its source.
  For one game of each kind of video, the core's pictures and sound were
  compared with upstream uzem's own, frame by frame: they are the same.
- Tried: those games and demos and the core's own test program, in the
  sandbox and natively, and in Chimera's headless runner and window on
  Linux. No game from outside the Uzebox repository has been tried.
- Not there: the SD card (games that load data from one), the SPI RAM and
  the Uzenet network adapter, which uzem has no emulation of either. The
  picture is not turned for games made for a vertical arcade screen.

## What you bring

A game: a `.uze` file, or a `.hex` program as the Uzebox's compiler writes
it. Nothing else is needed.

## Buttons and settings

- **Gamepads**: P1 and P2, SNES pads: Up, Down, Left, Right, Select, Start,
  Y, B, X, A, L and R. P1 is on the keyboard and the first game controller,
  P2 on the second game controller.
- **The mouse**: a SNES mouse in the first port, in place of P1's gamepad,
  for the games that use one. Mouse Left and Right are its buttons, Mouse
  Move X and Y how far it moves in a frame.
- **The keyboard**: the Uzebox keyboard, a PC keyboard read through the second
  port, for the games that use one.
- **Power**: the console's soft power switch.
- **Settings**: P1 Controller (the gamepad or the mouse; by default what the
  game's file asks for) and Random Seed (the start of the random drift the
  console's random seed is measured from).

Emulator > Export Save Data writes the console's EEPROM (where games keep
scores and saved games) as `eeprom.bin`, and a project can start from one.

RAM Watch and RAM Search read the console's 4 KB of memory; the EEPROM and
the 64 KB of flash the program is in are there too.

## Building and testing

[docs/BUILDING.md](docs/BUILDING.md) has every step. [docs/PLAN.md](docs/PLAN.md)
is the design log: what was decided, why, and what was measured.

## Licence

This repository's own code is MIT, and so is uzem. The rest of the Uzebox
repository, the kernel and the games, is under the GNU GPL 3; none of it is
in the package. See [LICENSE](LICENSE).
