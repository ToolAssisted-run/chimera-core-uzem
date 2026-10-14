#!/bin/sh
# Builds the test program (tests/testprog/testprog.c) on the Uzebox kernel
# of the submodule, with the AVR compiler (avr-gcc and avr-libc: on Debian
# and Ubuntu the packages gcc-avr, binutils-avr and avr-libc). The flags are
# those of the kernel's own demos (demos/*/default/Makefile). The kernel is
# compiled from the submodule as it is; nothing is written into it.
#
# usage: build-testprog.sh <out folder>
# writes testprog.hex (every control read) and testprog-nopad.hex (no
# control read: a lag frame every frame), and the .uze files of them
# (tests/make-uze.py): testprog.uze, and testprog-mouse.uze, whose header
# asks for the mouse.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
kernel="$root/extern/uzebox/kernel"
out="$1"
mkdir -p "$out"
command -v avr-gcc > /dev/null || { echo "avr-gcc is not on the PATH (packages gcc-avr, binutils-avr, avr-libc)" >&2; exit 1; }

cflags="-mmcu=atmega644 -Wall -std=gnu99 -DF_CPU=28636360UL -Os -fsigned-char -ffunction-sections -fno-toplevel-reorder -I$kernel"

build() { # <name> <kernel options>
	name="$1"; opts="$2"
	obj="$out/obj-$name"
	mkdir -p "$obj"
	for s in uzeboxVideoEngineCore uzeboxSoundEngineCore; do
		avr-gcc $cflags $opts -x assembler-with-cpp -c "$kernel/$s.s" -o "$obj/$s.o"
	done
	for c in uzeboxCore uzeboxSoundEngine uzeboxVideoEngine keyboard; do
		avr-gcc $cflags $opts -c "$kernel/$c.c" -o "$obj/$c.o"
	done
	avr-gcc $cflags $opts -c "$here/testprog/testprog.c" -o "$obj/testprog.o"
	avr-gcc -mmcu=atmega644 -Wl,-gc-sections "$obj"/*.o -o "$obj/$name.elf"
	avr-objcopy -O ihex -R .eeprom "$obj/$name.elf" "$out/$name.hex"
}

common="-DVIDEO_MODE=1 -DINTRO_LOGO=0 -DTRUE_RANDOM_GEN=1"
build testprog "$common -DSNES_MOUSE=1"
build testprog-nopad "$common -DCONTROLLERS_VSYNC_READ=0 -DNO_CONTROLS"
python3 "$here/make-uze.py" "$out/testprog.hex" "$out/testprog.uze" "Chimera test program"
python3 "$here/make-uze.py" "$out/testprog.hex" "$out/testprog-mouse.uze" "Chimera test program, mouse" --mouse
echo "built: $(cd "$out" && ls *.hex *.uze | tr '\n' ' ')"
