#!/usr/bin/env python3
"""Writes a .uze file from a .hex program: the 512-byte header uzem reads
(extern/uzebox/tools/uzem/uzerom.h, struct RomHeader) and the program. Done
here so that the tests need no build of upstream's packrom. The header is
512 bytes in the file (uzem reads 512; its struct is 5 bytes longer, in its
unused end). --mouse sets the header's "mouse connected by default", which
uzem and this core read to put a mouse in the first port.

usage: make-uze.py IN.hex OUT.uze NAME [--mouse]"""
import struct
import sys
import zlib

hexfile, out, name = sys.argv[1:4]
mouse = "--mouse" in sys.argv[4:]
flash = bytearray(b"\xff" * 65536)
end = 0
for line in open(hexfile):
    line = line.strip()
    if not line.startswith(":"):
        continue
    raw = bytes.fromhex(line[1:])
    count, addr, kind = raw[0], raw[1] << 8 | raw[2], raw[3]
    if kind == 1:
        break
    if kind == 0:
        flash[addr:addr + count] = raw[4:4 + count]
        end = max(end, addr + count)
program = bytes(flash[:end])

PERIPHERAL_MOUSE = 1
header = struct.pack(
    "<6sBBIH32s32s256sIB64sBB107s",
    b"UZEBOX", 1, 0, len(program), 2026,
    name.encode()[:32], b"Chimera".ljust(32, b"\0"), bytes(256),
    zlib.crc32(program) & 0xFFFFFFFF,
    PERIPHERAL_MOUSE if mouse else 0, b"".ljust(64, b"\0"),
    PERIPHERAL_MOUSE if mouse else 0, 0, bytes(107))
assert len(header) == 512, len(header)
open(out, "wb").write(header + program)
