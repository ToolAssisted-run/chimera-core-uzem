#!/bin/sh
# Stands in for ffmpeg when upstream uzem records a movie (--record): uzem
# pipes its raw pictures and its raw sound to two ffmpeg commands and then
# asks a third to put them together. This keeps the two raw streams in the
# folder it is run in (frames.raw, audio.raw) and does nothing else. The
# tests put it on the PATH as "ffmpeg".
case "$*" in
	*"-f rawvideo"*) exec cat > frames.raw ;;
	*"-f u8"*) exec cat > audio.raw ;;
	*) exit 0 ;;
esac
