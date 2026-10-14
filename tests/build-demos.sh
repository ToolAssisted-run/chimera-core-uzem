#!/bin/sh
# Builds the games and demos in the Uzebox repository (the submodule) with
# its own Makefiles, on a copy: upstream's tools that turn pictures and
# music into source (packrom, gconvert, mconvert, dconvert) are built for
# this machine first, then each game with the AVR compiler (avr-gcc and
# avr-libc). They are under the GNU GPL 3, as the kernel is; they are test
# programs here, and never part of the package.
#
# usage: build-demos.sh <out folder>
# writes <out>/<game>.uze for each game upstream's top Makefile lists, and
# <out>/DonkeyKong.hex: Donkey Kong's program is larger than a .uze may
# hold (61,440 bytes), and packrom cuts it short.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
out="$(mkdir -p "$1" && cd "$1" && pwd)"
command -v avr-gcc > /dev/null || { echo "avr-gcc is not on the PATH (packages gcc-avr, binutils-avr, avr-libc)" >&2; exit 1; }
src="$out/src"
rm -rf "$src"
mkdir -p "$src"
git -C "$root/extern/uzebox" archive HEAD Makefile kernel demos tools | tar -x -C "$src"
(cd "$src" && make tools TOOLS="packrom gconvert mconvert dconvert" > "$out/tools.log" 2>&1) || {
	echo "upstream's tools did not build: $out/tools.log" >&2; exit 1; }
PATH="$src/bin:$PATH"
export PATH
failed=""
for d in $(sed -n 's/^DEMOS += *//p' "$src/Makefile"); do
	[ -d "$src/demos/$d/default" ] || continue
	if (cd "$src/demos/$d/default" && make > "$out/$d.log" 2>&1); then
		for u in "$src/demos/$d/default"/*.uze; do [ -f "$u" ] && cp "$u" "$out/"; done
	else
		failed="$failed $d"
	fi
done
cp "$src/demos/DonkeyKong/default/DonkeyKong.hex" "$out/" 2> /dev/null || true
[ -z "$failed" ] || { echo "did not build:$failed (logs in $out)" >&2; exit 1; }
echo "built: $(ls "$out"/*.uze | wc -l) games"
