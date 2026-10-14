# Design log

What was decided for this core, why, and what was measured. Newest last.

## 2026-10-14: uzem, with its program around it replaced

**Decided.** The core is built from the Uzebox repository's master branch
(Uzebox/uzebox 384ceb3d, 2026-09-29), its emulator uzem (`tools/uzem`).
BizHawk has an Uzebox core made from uzem; it was read for ideas only, and
nothing was taken from it (the owner's instruction for the cores of this
round). Its ideas used here: end a frame where uzem shows its picture, and
read the power switch as the console's pins.

uzem is a processor (`avr8.cpp`) and a loader (`uzerom.cpp`) with a program
around them (`uzem.cpp`) that opens an SDL window. The core compiles the
first two as they are, with one patch (`0001`) that takes SDL out:

- SDL's types are named but not built, so the machine's structure keeps its
  shape;
- each line drawn goes into the core's picture, and the 224th line, where
  uzem shows the picture, tells the core the frame is over;
- a sample written to the sound output goes to the core;
- a latch of the controllers is counted (lag frames);
- an instruction the processor does not have stops the machine instead of
  ending the program;
- the window, the host keyboard and joystick code, and the debugger's idle
  loop are left out.

`waterbox/cinterface.cpp` does what `uzem.cpp` did: load the game, set the
machine up as uzem's `init_gui` does (the palette, where a line starts),
give it the controls and run it.

**A frame** ends at the 224th line, as uzem's picture does: 476,840 cycles,
60.05 frames a second. Before the program's video starts (the first
frames, while the kernel starts) a frame ends after a frame and a half of
cycles.

**The picture** is uzem's: 720x224, every second cycle of a line, shown at
uzem's 630x448. Games made for a vertical arcade screen ask in their header
for the picture to be turned; uzem turns its window, the core does not turn
the picture yet.

**The sound** is the level the kernel writes to the sound output once a
line. The core takes the level every 1820 cycles, so a frame has 262
samples whatever the program does (15,734 a second, the chip's own rate,
which Chimera converts); uzem plays the writes from a queue at that rate.

**Controls.** Two SNES gamepads; a SNES mouse in the first port when the
game's header asks for one (as uzem decides) or the P1 Controller setting
says so; the Uzebox keyboard, 99 keys of a PC keyboard sent as scan codes
of set 2 when a key goes down or up, once the program starts the keyboard
(uzem sends them only then too); and the soft power switch. uzem reads the
host's mouse once a frame and gives the same movement to every read of the
mouse in the frame; Mouse Move X and Y are that movement.

uzem reads the power switch's two pins as low - pressed - until its 0 key
first comes up, so in uzem a game sees the switch held from the start. The
core gives the pins as the console does: pulled up, high, unless Power is
held. Measured: the one game that showed it (SpriteDemo's first picture has
a piece of sprite more) draws upstream's pictures when Power is held.

**The random seed.** The kernel times the watchdog timer at power-on to make
a seed for games, and uzem adds a drift to the timer from `rand()`, which it
seeds from the computer's clock. The core seeds it from the Random Seed
setting and defines `rand()` as the sandbox's C library has it, so that both
builds draw the same numbers. Measured: the seed is 45985 with 0 and 29918
with 12345 (`uze:random-seed`).

**Save data** is the EEPROM, 2 KB, shared by every game (each in a block of
its own, which the kernel keeps). Blank it is all FF, as uzem starts it; the
kernel formats it at power-on. Export Save Data writes it as `eeprom.bin`
once it is not blank, and the save data slot loads such a file (or uzem's
own `eeprom.bin`) before the first frame.

**Files.** A `.uze` file is loaded by uzem's loader once the core has looked
at the header's program size (uzem reads that many bytes into the 64 KB of
flash without looking). A `.hex` program is read by the core: uzem's
`loadHex` takes only capital hex digits but `a`, and does not look at where
a line writes.

**Left out**: the SD card (uzem builds one from the game's folder; no game
here has a folder), the SPI RAM and the Uzenet adapter (uzem has neither),
uzem's movie recording and its controller capture files.

## 2026-10-14: what the tests compare

The tests build everything they run from source, with the AVR compiler: a
test program of this repository's on the Uzebox kernel, which reads every
control the way games do (the kernel's `ReadJoypad`, `ReadJoypadExt` and
keyboard driver) into its memory, and the Uzebox repository's 34 games and
demos. Measured:

- every gamepad button reaches the kernel as its own bit; Left with Right
  and Up with Down come out as Left and Up, as uzem's pad does;
- the mouse's buttons and movement reach the kernel as the kernel reads a
  SNES mouse (5,-7 is 0x8705 to `ReadJoypadExt`);
- each of the 99 keys reaches the kernel's keyboard driver as that key
  (the driver reads Page Down as Down, its own doing);
- the test program has 6 lag frames in 300 (the kernel starting), its twin
  that reads nothing 300;
- the sandbox gives the native build's digests with and without states
  saved and loaded every frame, moved to a new sandbox, and rewound;
- every game runs 600 frames in the sandbox as natively.

**Against upstream's uzem.** Upstream's uzem is built as upstream builds it,
with SDL, from the same commit without the patch, and records a movie
(`--record`) with a stand-in for ffmpeg that keeps the raw pictures and
sound. The core's pictures must be upstream's, frame for frame, and its
sound sample for sample (upstream writes a sample twice now and then to keep
its movie in step; those are taken out). Measured on 13 programs, which use
10 of the kernel's video modes (0, 1, 2, 3, 5, 6, 8, 9, 10 and 13; modes 7
and 41 are used here only by the games that need an SD card), about 490
frames and 127,000 samples each: all the same. Not compared: BootDemo and VideoDemo,
which read an SD card, and Maze, whose seed comes from upstream's clock.

Donkey Kong's program is larger than a `.uze` may hold, and upstream's
packrom cuts it short; its `.hex` is used. Its picture has a red pattern
where black is expected, in upstream's uzem too.

## 2026-10-14: the modifier keys are bound as Chimera reads them

**Found.** Chimera hands a key to the bindings under one name only: the
name DistinctKeyNameOverrides gives it ("Number1", "Enter", "Backtick",
"KeypadAdd"), or else its DistinctKey name (Input.cs). By default it also
reads the left and right Shift, Ctrl and Alt as one key each, "Shift",
"Ctrl" and "Alt" (Config.MergeLAndRModifierKeys). A binding to any other
name never fires, so those controls shipped unbound.

**Decided.** The bindings use those names; where both keys of a modifier
were bound, the left one is on the merged key and the right one ships
unbound. The test `package:key-names` (`tests/check-key-names.py`) reads the
names from Chimera's source and checks every binding.

Measured: Left Shift, Left Ctrl and Left Alt were bound to LeftShift,
LeftCtrl and LeftAlt, which a default setup never sends; they are now on
Shift, Ctrl and Alt, and Right Shift, Right Ctrl and Right Alt ship unbound.
