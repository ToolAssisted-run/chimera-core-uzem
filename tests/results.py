#!/usr/bin/env python3
"""Prints what the test program (tests/testprog/testprog.c) left in its
block of memory, found by its "UZTEST01", from a dump of the RAM domain:
one name=value a line, numbers in decimal, byte lists in hex.

usage: results.py RAM.bin [NAME]   (with a NAME, its value alone)"""
import struct
import sys

ram = open(sys.argv[1], "rb").read()
# the last: the first is the string the program copies it from
at = ram.rfind(b"UZTEST01")
if at < 0:
    sys.exit("the test program's block is not in this memory")
b = ram[at:at + 52]
v = {}
(v["frames"], v["pad1"], v["pad2"], v["ext1"], v["power"], v["eepromSeen"], v["seed"],
 v["rawCount"], v["keyCount"]) = struct.unpack_from("<IHHHBBHBB", b, 8)
v["raw"] = b[24:24 + min(v["rawCount"], 16)].hex()
v["keys"] = b[40:40 + min(v["keyCount"], 8)].hex()
v["modifiers"], v["pad1Max"], v["pad1Seen"] = struct.unpack_from("<BBH", b, 48)
v["at"] = at
if len(sys.argv) > 2:
    print(v[sys.argv[2]])
else:
    for k, x in v.items():
        print(f"{k}={x}")
