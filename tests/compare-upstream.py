#!/usr/bin/env python3
"""Compares the core's pictures and sound with upstream uzem's own.

Upstream uzem, built as upstream builds it (with SDL), records a movie with
--record by piping every picture (720x224, 4 bytes a pixel) and every sound
sample (one byte each time the program writes the sound output) to ffmpeg;
tests/upstream-ffmpeg.sh stands in for ffmpeg and keeps both streams as they
are. The core's runner writes the same two streams with --av-stream.

Pictures: the core's frames, from some frame on, must be upstream's frames
in order, every one the same in every pixel (the 4th byte of a pixel is
left out: upstream leaves it 0, the core 255). The core can have a few more
frames at the start: before the program's video starts, the core ends a
frame after a frame and a half of cycles, and upstream draws nothing.

Sound: upstream writes each sample the program writes, and now and then
the same one twice, to keep its movie's sound in step (avr8.cpp, "Keep
audio in sync"); those extra ones are taken back out the way they were put
in. The core takes the level once a line. Its samples, from some sample on,
must be upstream's.

usage: compare-upstream.py UPSTREAM_DIR CORE_DIR
prints one line and exits 0 when both agree over at least the frames
upstream recorded, less the last one (it may be cut short)."""
import hashlib
import sys

W, H = 720, 224
FRAME = W * H * 4
MAX_OFFSET = 20


def frame_hashes(path):
    out = []
    with open(path, "rb") as f:
        while True:
            b = f.read(FRAME)
            if len(b) < FRAME:
                return out
            rgb = bytearray(b)
            del rgb[3::4]
            out.append(hashlib.sha1(rgb).digest())


def upstream_writes(path):
    data = open(path, "rb").read()
    needs = 4.0 * 1.0 / 15734.0 / (1.0 / 15734.0 - 1820.0 / 28636360.0)
    err = 0.0
    out = bytearray()
    i = 0
    while i < len(data):
        out.append(data[i])
        i += 1
        err += 28636360 % 15734
        if err > needs:
            err -= needs
            i += 1  # the extra copy
    return bytes(out)


def core_levels(path):
    data = open(path, "rb").read()
    out = bytearray()
    for i in range(0, len(data) - 3, 4):  # left channel, 16 bits little-endian
        v = int.from_bytes(data[i:i + 2], "little", signed=True)
        out.append((v // 256 + 128) & 0xFF)
    return bytes(out)


def best_offset(core, up, minimum):
    """the offset at which the core's run, from it on, is upstream's for
    the longest stretch; (offset, length matched)"""
    best = (None, 0)
    for k in range(0, min(MAX_OFFSET * 300, len(core))):
        n = 0
        limit = min(len(up), len(core) - k)
        while n < limit and core[k + n] == up[n]:
            n += 1
        if n > best[1]:
            best = (k, n)
        if n >= minimum:
            break
    return best


up_dir, core_dir = sys.argv[1], sys.argv[2]
up_frames = frame_hashes(up_dir + "/frames.raw")
core_frames = frame_hashes(core_dir + "/frames.raw")
need_frames = min(len(up_frames) - 1, len(core_frames) - MAX_OFFSET)
f_off, f_len = best_offset(core_frames, up_frames, need_frames)

up_sound = upstream_writes(up_dir + "/audio.raw")
core_sound = core_levels(core_dir + "/audio.raw")
# upstream's first write is the first the program made; the core's samples
# before it are the level it starts at
need_sound = min(len(up_sound) - 1, len(core_sound) - MAX_OFFSET * 262)
s_off, s_len = best_offset(core_sound, up_sound, need_sound)

ok = need_frames > 0 and f_len >= need_frames and need_sound > 0 and s_len >= need_sound
distinct = len(set(up_frames[:f_len]))
print(f"pictures: {f_len} of {len(up_frames)} upstream frames ({distinct} different) are the core's from its frame {f_off + 1 if f_off is not None else '-'}; "
      f"sound: {s_len} of {len(up_sound)} upstream samples are the core's from its sample {s_off}")
sys.exit(0 if ok else 1)
