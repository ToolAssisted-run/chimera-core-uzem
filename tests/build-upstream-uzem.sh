#!/bin/sh
# Builds upstream's own uzem, as upstream builds it (its Makefile, with SDL 2,
# without its debugger), from the submodule's commit as it is - without this
# repository's patch - on a copy. The tests compare the core's pictures and
# sound with its own (tests/compare-upstream.py).
#
# usage: build-upstream-uzem.sh <out folder>   (writes <out>/uzem)
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
out="$(mkdir -p "$1" && cd "$1" && pwd)"
command -v sdl2-config > /dev/null || { echo "SDL 2's development files are not installed (package libsdl2-dev)" >&2; exit 1; }
rm -rf "$out/src"
mkdir -p "$out/src"
git -C "$root/extern/uzebox" archive HEAD tools/uzem | tar -x -C "$out/src"
(cd "$out/src/tools/uzem" && NOGDB=1 make release > "$out/build.log" 2>&1) || {
	echo "upstream uzem did not build: $out/build.log" >&2; exit 1; }
cp "$out/src/tools/uzem/uzem" "$out/uzem"
