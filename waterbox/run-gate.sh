#!/bin/bash
# The core's tests. Each line says what was compared. The script ends with a
# count of tests that passed, failed and were skipped, and with an error if
# any failed. A skipped test is not a pass.
#
#   waterbox/run-gate.sh
#
# CHIMERA_ROOT=<a Chimera checkout> adds the test that runs the package in
# Chimera's own headless runner (waterbox/build-package.sh -r <it> first).
#
# Needs the native build (meson setup build/meson-native ... && ninja) and
# the sandboxed core (waterbox/setup-guest.sh && ninja -C build/meson-guest):
# docs/BUILDING.md. Also the AVR compiler (avr-gcc, avr-libc), which builds
# the test programs, and SDL 2's development files, which build upstream's
# own uzem for the comparison with it; without SDL those tests are skipped.
#
# WHAT RUNS WITH NO FILES OF YOURS: everything. tests/testprog/testprog.c is
# a program of this repository's, built on the Uzebox kernel, that reads
# every control into its memory; the Uzebox repository's own games and
# demos are built from source (tests/build-demos.sh).
#
# The ways a test passes on a broken thing (Chimera's docs/gates.md) that
# these are written against: a machine that did nothing agrees with itself,
# so a run is first checked to have got somewhere; the end of a run hides a
# run that went another way and came back, so runs are compared as a stream
# of digests; and a comparison that cannot fail proves nothing, so each
# "the same" has a run beside it that must come out different.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
native="$root/build/meson-native/run-native"
runwbx="$root/build/meson-native/run-wbx"
core="$root/build/meson-guest/core.wbx"
chimera_root="${CHIMERA_ROOT:-}"

work="$(mktemp -d)"
# GATE_KEEP=1 keeps the work folder (the runs' output and dumps) and says where
if [ -n "${GATE_KEEP:-}" ]; then trap 'echo "work folder kept: $work"' EXIT; else trap 'rm -rf "$work"' EXIT; fi
ok=0; failed=0; skipped=0
report() { # <test> <PASS|FAIL|SKIP> <what>
	printf '%-24s %-6s %s\n' "$1" "$2" "$3"
	case "$2" in PASS) ok=$((ok + 1)) ;; FAIL) failed=$((failed + 1)) ;; *) skipped=$((skipped + 1)) ;; esac
}
# check <test> <what> <condition...>
check() {
	ck_test="$1"; ck_what="$2"; shift 2
	if "$@"; then report "$ck_test" PASS "$ck_what"; else report "$ck_test" FAIL "$ck_what"; fi
}
stream() { grep '^frame' "$1"; }
same() { [ -s "$1" ] && [ -s "$2" ] && cmp -s "$1" "$2"; }
differ() { [ -s "$1" ] && [ -s "$2" ] && ! cmp -s "$1" "$2"; }
# field <file> <name>: the value after a name in the file's last report line
field() { stream "$1" | tail -1 | awk -v f="$2" '{for (i = 1; i <= NF; i++) if ($i == f) { print $(i + 1); exit }}'; }
pictures() { stream "$1" | awk '{print $7}' | sort -u | wc -l; }
sounds() { stream "$1" | awk '{print $10}' | sort -u | wc -l; }
# r <ram dump> <name>: what the test program left in its memory
r() { python3 "$root/tests/results.py" "$1" "$2" 2> /dev/null; }
# folder <name> <settings json> <game> [<save data>]: a work folder as the
# sandbox mounts a project - every file under its name
folder() {
	mkdir -p "$work/$1"
	cp "$3" "$work/$1/$(basename "$3")"
	if [ -n "${4:-}" ]; then
		cp "$4" "$work/$1/$(basename "$4")"
		printf '{"game":["%s"],"savedata":["%s"]}' "$(basename "$3")" "$(basename "$4")" > "$work/$1/slots"
	else
		printf '{"game":["%s"]}' "$(basename "$3")" > "$work/$1/slots"
	fi
	printf '%s' "$2" > "$work/$1/settings"
}
nat() { nt_out="$1"; nt_dir="$2"; shift 2; "$native" "$work/$nt_dir" "$@" > "$work/$nt_out.out" 2> "$work/$nt_out.err"; }
box() { bx_out="$1"; bx_dir="$2"; shift 2; "$runwbx" "$core" "$work/$bx_dir" "$@" > "$work/$bx_out.out" 2> "$work/$bx_out.err"; }
# index <folder> <control>: the control's place in the panel
index() { "$native" "$work/$1" --frames 1 --list-panel 2> /dev/null | grep "'$2'" | head -1 | awk '{print $2}'; }
# repeats <file> <first> <second> <count> <step>: do the report lines from
# frame <second> on repeat those from frame <first> on (run-wbx --rewind)
repeats() {
	awk -v a="$2" -v b="$3" -v n="$4" -v step="$5" '
		/^frame/ { f = $2; $1 = ""; $2 = ""; sub(/ lag [0-9]+$/, ""); line[f] = $0 }
		END {
			for (i = step; i < n; i += step) {
				if (!((a + i) in line) || !((b + i) in line) || line[a + i] != line[b + i]) exit 1
				seen++
			}
			exit seen > 0 ? 0 : 1
		}' "$1"
}

if [ ! -x "$native" ] || [ ! -x "$runwbx" ] || [ ! -f "$core" ]; then
	echo "not built: this needs build/meson-native/run-native and run-wbx, and build/meson-guest/core.wbx (docs/BUILDING.md)" >&2
	exit 1
fi

# ------------------------------------------------- the source and the package
patches="$(ls "$root"/patches/*.patch 2> /dev/null | wc -l)"
check "source:patched" "extern/uzebox is the pinned commit with the $patches patches of patches/" \
	sh -c "sh '$here/apply-patches.sh' > '$work/patches.log' 2>&1 && [ \"\$(git -C '$root' rev-parse HEAD:extern/uzebox)\" = \"\$(git -C '$root/extern/uzebox' rev-parse HEAD)\" ]"

stale=""
for src in "$here"/cinterface.cpp "$root"/meson.build "$root"/patches/*.patch; do
	[ -e "$src" ] || continue
	[ "$core" -nt "$src" ] || stale="$stale $(basename "$src")"
done
check "package:fresh" "core.wbx is not older than its sources${stale:+ (older than:$stale)}" [ -z "$stale" ]

# ------------------------------------------------- the test program
progs="$work/progs"
if ! sh "$root/tests/build-testprog.sh" "$progs" > "$work/testprog.log" 2>&1; then
	report "uze:testprog" FAIL "the test program did not build (is avr-gcc on the PATH?): $(tail -1 "$work/testprog.log")"
	echo; echo "$ok passed, $failed failed, $skipped skipped"; exit 1
fi
folder t '{}' "$progs/testprog.uze"
folder th '{}' "$progs/testprog.hex"
folder q '{}' "$progs/testprog-nopad.hex"
folder m '{}' "$progs/testprog-mouse.uze"

"$native" "$work/t" --frames 1 --list-panel > "$work/panel.out" 2> /dev/null
check "package:controls" "the package declares the core's own $(grep -c '^panel' "$work/panel.out") buttons, in the core's order, and its 2 axes" \
	python3 - "$here/waterbox.config" "$work/panel.out" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
lines = open(sys.argv[2]).read().splitlines()
buttons = [l[l.index("'") + 1:l.rindex("'")] for l in lines if l.startswith("panel ")]
axes = [l for l in lines if l.startswith("axis ")]
i = cfg["input"]
sys.exit(0 if i["buttons"] == buttons and len(buttons) == 126 and len(i["axes"]) == len(axes) == 2 else 1)
PY

if [ -n "$chimera_root" ] && [ -f "$chimera_root/source/ui/qt/key_codes.inc" ]; then
	check "package:key-names" "every host key the package's default bindings name is a key Chimera knows: $(python3 "$root/tests/check-key-names.py" "$chimera_root" "$here/default_keybinds.json" 2>&1)" \
		sh -c "python3 '$root/tests/check-key-names.py' '$chimera_root' '$here/default_keybinds.json' > /dev/null 2>&1"
else
	report "package:key-names" SKIP "needs CHIMERA_ROOT, whose source names the keys Chimera knows"
fi

nat idle t --frames 300 --report 25 --dump-domain RAM "$work/idle.ram"
check "uze:runs" "the test program runs: it counted $(r "$work/idle.ram" frames) frames in 300 (the rest are the kernel starting), with $(pictures "$work/idle.out") different pictures in 12 reports" \
	sh -c "[ '$(r "$work/idle.ram" frames)' -ge 290 ] && [ $(pictures "$work/idle.out") -ge 12 ]"
nat hex th --frames 300 --report 25
stream "$work/idle.out" > "$work/idle.stream"; stream "$work/hex.out" > "$work/hex.stream"
check "uze:hex-and-uze" "the same program as a .hex file and as a .uze file runs the same: the same $(wc -l < "$work/idle.stream") digests" \
	same "$work/idle.stream" "$work/hex.stream"

# each_button <folder> <first control> <count> <field> <out>: each control
# held alone from frame 60 to the end; what the program then read
each_button() {
	: > "$5"
	for ((c = 0; c < $3; c++)); do
		"$native" "$work/$1" --frames 100 --press $(($2 + c)):60:60 --dump-domain RAM "$work/eb.ram" > /dev/null 2>&1
		echo "$c $(r "$work/eb.ram" "$4")" >> "$5"
	done
}
# one_bit <file> <count>: there are <count> lines, and line c has one bit set, the
# bit of control c's place in the order the pad sends its buttons (B, Y, Select,
# Start, Up, Down, Left, Right, A, X, L, R), while the controls are listed Up,
# Down, Left, Right, Select, Start, Y, B, X, A, L, R (chimera#335)
one_bit() { awk -v n="$2" 'BEGIN { split("4 5 6 7 2 3 1 0 9 8 10 11", wire, " ") } { if ($2 != 2 ^ wire[$1 + 1]) bad = 1; c++ } END { exit (bad || c != n) }' "$1"; }
each_button t 0 12 pad1 "$work/p1.txt"
each_button t 12 12 pad2 "$work/p2.txt"
pads=no; one_bit "$work/p1.txt" 12 && one_bit "$work/p2.txt" 12 && pads=yes
check "uze:gamepads" "each of the 24 gamepad buttons (P1 and P2: Up, Down, Left, Right, Select, Start, Y, B, X, A, L, R), held alone, is the kernel's button bit of its place in the order the pad sends them (B, Y, Select, Start, Up, Down, Left, Right, A, X, L, R), and no other" \
	[ "$pads" = yes ]
nat lr t --frames 100 --press 2:60:60 --press 3:60:60 --press 0:60:60 --press 1:60:60 --dump-domain RAM "$work/lr.ram"
check "uze:opposites" "Left with Right and Up with Down held together reach the program as Left and Up alone, as uzem's controller does ($(r "$work/lr.ram" pad1); Up and Left are 16 and 64)" \
	[ "$(r "$work/lr.ram" pad1)" = 80 ]

ml="$(index m "Mouse Left")"
mouse() { # <folder> <dx> <dy> <press...>: "pad1 ext1" the program read
	dir="$1" dx="$2" dy="$3"; shift 3
	"$native" "$work/$dir" --frames 100 --axis 0:"$dx":60:60 --axis 1:"$dy":60:60 "$@" --dump-domain RAM "$work/mo.ram" > /dev/null 2>&1
	printf '%04x %04x' "$(r "$work/mo.ram" pad1)" "$(r "$work/mo.ram" ext1)"
}
mo="$(mouse m 5 -7 --press "$ml":60:60)|$(mouse m -100 3 --press $((ml + 1)):60:60)|$(mouse m 0 0)"
check "uze:mouse" "a .uze game whose header asks for the mouse gets a SNES mouse in the first port: the kernel sees the mouse's mark (bit 15), Mouse Left and Right (bits 9 and 8), and Mouse Move X and Y as the kernel's sign and size (5,-7 and -100,3: $mo)" \
	[ "$mo" = "8200 8705|8100 03e4|8000 0000" ]
folder mg '{"p1Controller":"gamepad"}' "$progs/testprog-mouse.uze"
folder hm '{"p1Controller":"mouse"}' "$progs/testprog.hex"
nat mg mg --frames 100 --press "$(index mg "P1 B")":60:60 --dump-domain RAM "$work/mg.ram"
nat hm hm --frames 100 --dump-domain RAM "$work/hm.ram"
check "uze:p1-controller" "P1 Controller 'gamepad' puts the gamepad back in place of the header's mouse (P1 B reads $(r "$work/mg.ram" pad1)), and 'mouse' puts a mouse on a .hex program, which has no header ($(printf %04x "$(r "$work/hm.ram" pad1)"))" \
	[ "$(r "$work/mg.ram" pad1) $(printf %04x "$(r "$work/hm.ram" pad1)")" = "1 8000" ]

# the keyboard: each key held alone; the bytes the keyboard sent, and what
# the kernel's own driver (kernel/keyboard.c) made of them
# the keys are the last controls, listed as they sit on the keyboard
# (chimera#337): the first is Escape
keyA="$(index t "Key A")"
key1="$(index t "Key Escape")"
nkeys=$(($(grep -c '^panel' "$work/panel.out") - key1))
: > "$work/keys.txt"
for ((k = 0; k < nkeys; k++)); do
	name="$("$native" "$work/t" --frames 1 --list-panel 2> /dev/null | awk -v i=$((key1 + k)) '$1 == "panel" && $2 == i' | sed "s/^[^']*'//; s/'[^']*\$//")"
	"$native" "$work/t" --frames 160 --press $((key1 + k)):60:40 --dump-domain RAM "$work/kb.ram" > /dev/null 2>&1
	printf '%s\t%s\t%s\t%s\n' "$name" "$(r "$work/kb.ram" raw)" "$(r "$work/kb.ram" keys)" "$(r "$work/kb.ram" modifiers)" >> "$work/keys.txt"
done
check "uze:keyboard" "each of the $nkeys keys, held alone, is sent as a PC keyboard sends it (its code, then F0 and its code when it comes up, after E0 for the extended keys), and the kernel's keyboard driver reads it as that key" \
	python3 - "$work/keys.txt" <<'PY'
import sys
# what the kernel's driver (kernel/keyboard.c, keyboard.h) makes of each
# key: a character or a KB_ code, or a modifier flag (shift 1, ctrl 2,
# alt 4); and, for the keys it makes nothing of, their code
chars = {c: ord(c) for c in "abcdefghijklmnopqrstuvwxyz0123456789`-=[]\\;',./"}
named = {"Space": 0x20, "Tab": 0x09, "Return": 0x0D, "Backspace": 0x08, "Escape": 0x1B,
         "Up": 0x1A, "Down": 0x1C, "Left": 0x1D, "Right": 0x1E, "Insert": 0x05, "Delete": 0x06,
         "Home": 0x07, "End": 0x0A, "Page Up": 0x0B,
         "Page Down": 0x1C,  # the kernel reads Page Down as KB_DOWN (keyboard.c)
         "Scroll Lock": 0x03, "Keypad .": ord("."), "Keypad +": ord("+"), "Keypad -": ord("-"),
         "Keypad *": ord("*")}
named.update({f"F{i}": 0x0D + i for i in range(1, 13)})
named.update({f"Keypad {i}": ord(str(i)) for i in range(10)})
mods = {"Left Shift": 1, "Right Shift": 1, "Left Ctrl": 2, "Right Ctrl": 2, "Left Alt": 4, "Right Alt": 4}
codes = {"Caps Lock": "58", "Num Lock": "77", "Keypad /": "e04a", "Keypad Enter": "e05a"}
bad = []
for line in open(sys.argv[1]):
    name, raw, keys, mod = line.rstrip("\n").split("\t")
    key = name[4:]
    ext = raw.startswith("e0")
    press = raw[:4] if ext else raw[:2]
    release = ("e0" if ext else "") + "f0" + press[-2:]
    if raw != press + release:
        bad.append(f"{name}: sent {raw}")
        continue
    if key in mods:
        ok = keys == "" and int(mod) == 0  # the flag is up again once the key is
    elif key in codes:
        ok = press == codes[key] and keys == ""
    else:
        want = chars.get(key.lower() if len(key) == 1 else None, named.get(key))
        ok = want is not None and keys == f"{want:02x}"
    if not ok:
        bad.append(f"{name}: sent {raw}, kernel read {keys or '-'} (modifiers {mod})")
if bad:
    print("\n".join(bad[:12]), file=sys.stderr)
sys.exit(1 if bad else 0)
PY
# a modifier is read while it is held
nat shift t --frames 100 --press "$(index t "Key Left Shift")":60:60 --press "$keyA":70:50 --dump-domain RAM "$work/shift.ram"
check "uze:keyboard-shift" "with Left Shift held the kernel's driver has its shift flag up ($(r "$work/shift.ram" modifiers)) and reads A held with it as 'a' unshifted ($(r "$work/shift.ram" keys))" \
	[ "$(r "$work/shift.ram" modifiers) $(r "$work/shift.ram" keys)" = "1 61" ]

pw="$(index t "Power")"
nat pw t --frames 100 --press "$pw":60:60 --dump-domain RAM "$work/pw.ram"
check "uze:power" "Power held is the kernel's IsPowerSwitchPressed() ($(r "$work/pw.ram" power); not held $(r "$work/idle.ram" power))" \
	[ "$(r "$work/pw.ram" power) $(r "$work/idle.ram" power)" = "1 0" ]

folder s1 '{"randomSeed":12345}' "$progs/testprog.uze"
nat s1 s1 --frames 30 --dump-domain RAM "$work/s1.ram"
nat s0 t --frames 30 --dump-domain RAM "$work/s0.ram"
check "uze:random-seed" "the kernel's random seed from the watchdog is the same in every run with the same Random Seed ($(r "$work/s0.ram" seed) with 0, as at 300 frames: $(r "$work/idle.ram" seed)), and another with another ($(r "$work/s1.ram" seed) with 12345)" \
	sh -c "[ '$(r "$work/s0.ram" seed)' = '$(r "$work/idle.ram" seed)' ] && [ '$(r "$work/s0.ram" seed)' != '$(r "$work/s1.ram" seed)' ]"

nat q q --frames 300 --report 100
check "uze:lag" "the program the kernel reads the controls for has a lag frame only while the kernel starts ($(field "$work/idle.out" lag) in 300); its twin that reads none, 300 ($(field "$work/q.out" lag))" \
	[ "$(field "$work/idle.out" lag)" -le 10 -a "$(field "$work/q.out" lag)" = 300 ]

nat snd t --frames 200 --report 5 --press "$(index t "P1 A")":60:100
check "uze:sound" "262 samples a frame (one a line: $(field "$work/snd.out" aud)); the sound is still with no key held, and changes while P1 A sounds a note ($(stream "$work/snd.out" | awk '$2 > 60 && $2 <= 160 {print $10}' | sort -u | wc -l) different in the 20 reports of it)" \
	sh -c "[ '$(field "$work/snd.out" aud)' = 262 ] && [ $(stream "$work/idle.out" | awk '$2 > 50 {print $10}' | sort -u | wc -l) = 1 ] && [ $(stream "$work/snd.out" | awk '$2 > 60 && $2 <= 160 {print $10}' | sort -u | wc -l) -ge 10 ]"

# the EEPROM: exported after a run, and a project begins from it
mkdir -p "$work/sv"
nat sv t --frames 300 --savedata-out "$work/sv"
ee="$work/sv/eeprom.bin"
eebyte() { od -An -tu1 -j "$2" -N1 "$1" 2> /dev/null | tr -d ' '; }
folder sv2 '{}' "$progs/testprog.uze" "$ee"
mkdir -p "$work/sv2-out"
nat sv2 sv2 --frames 300 --savedata-out "$work/sv2-out" --dump-domain RAM "$work/sv2.ram"
check "uze:save-data" "Export Save Data writes the EEPROM as eeprom.bin ($(wc -c < "$ee" 2> /dev/null) bytes, formatted by the kernel, the program's count $(eebyte "$ee" 16)); a project with it as save data begins from it: the program reads $(r "$work/sv2.ram" eepromSeen) and leaves $(eebyte "$work/sv2-out/eeprom.bin" 16)" \
	sh -c "[ '$(wc -c < "$ee" 2> /dev/null)' = 2048 ] && [ '$(eebyte "$ee" 16)' = 1 ] && [ '$(r "$work/sv2.ram" eepromSeen)' = 1 ] && [ '$(eebyte "$work/sv2-out/eeprom.bin" 16)' = 2 ]"

# ------------------------------------------------- native and sandbox, states
allrun="--frames 300 --report 10 --press $(index t "P1 A"):50:40 --press $(index t "P1 Up"):80:30 --press $(index t "Key D"):100:20 --press $(index t "P1 Start"):200:5 --press $(index t "P2 Y"):220:30"
nat all t $allrun
nat idle10 t --frames 300 --report 10
box all-box t $allrun
box all-rerecord t $allrun --rerecord
box all-session t $allrun --session
for n in all all-box all-rerecord all-session idle10; do stream "$work/$n.out" > "$work/$n.stream"; done
check "uze:sandbox" "native and sandbox print the same $(wc -l < "$work/all.stream") digests of memory, picture and sound, with gamepads and a key used" \
	same "$work/all.stream" "$work/all-box.stream"
check "uze:presses-change-the-run" "the run with presses differs from the idle one" differ "$work/all.stream" "$work/idle10.stream"
check "uze:state-every-frame" "a state saved and loaded every frame changes nothing" same "$work/all-box.stream" "$work/all-rerecord.stream"
check "uze:state-other-box" "a state moved to a new sandbox half way changes nothing" same "$work/all-box.stream" "$work/all-session.stream"
box rewind t --frames 1600 --report 5 --rewind
check "uze:state-rewind" "a state kept at frame 800 and loaded at 1200: the frames after the load repeat those after the save" \
	repeats "$work/rewind.out" 800 1200 400 5
mfold="--frames 300 --report 10 --axis 0:9:40:100 --axis 1:-4:40:100 --press $ml:100:50"
nat mall m $mfold
box mall-box m $mfold
box mall-rerecord m $mfold --rerecord
stream "$work/mall.out" > "$work/mall.stream"; stream "$work/mall-box.out" > "$work/mall-box.stream"; stream "$work/mall-rerecord.out" > "$work/mall-rerecord.stream"
check "uze:sandbox-mouse" "with the mouse moved and clicked, native, sandbox and a state saved and loaded every frame print the same $(wc -l < "$work/mall.stream") digests" \
	sh -c "cmp -s '$work/mall.stream' '$work/mall-box.stream' && cmp -s '$work/mall-box.stream' '$work/mall-rerecord.stream' && [ -s '$work/mall.stream' ]"

# ------------------------------------------------- what is refused or stops
mkdir -p "$work/none"
printf '{"game":[]}' > "$work/none/slots"; printf '{}' > "$work/none/settings"
nat none none --frames 1
check "refused:no-game" "a machine with no game is refused, and says so" grep -q "Init failed.*error.no_file" "$work/none.out" "$work/none.err"
printf 'not a game' > "$work/junk.uze"
folder junk '{}' "$work/junk.uze"
nat junk junk --frames 1
check "refused:not-a-game" "a file that is not a game is refused, and says so" grep -q "Init failed.*error.not_game" "$work/junk.out" "$work/junk.err"
python3 - "$progs/testprog.uze" "$work/big.uze" "$work/uz2.uze" <<'PY'
import sys
d = bytearray(open(sys.argv[1], "rb").read())
big = bytearray(d); big[8:12] = (70000).to_bytes(4, "little")
open(sys.argv[2], "wb").write(big)
v2 = bytearray(d); v2[7] = 1  # the target: the Uzebox 2.0's processor
open(sys.argv[3], "wb").write(v2)
PY
folder big '{}' "$work/big.uze"; nat big big --frames 1
folder uz2 '{}' "$work/uz2.uze"; nat uz2 uz2 --frames 1
check "refused:bad-uze" "a .uze file whose header says its program is larger than the flash, and one for the Uzebox 2.0, are refused, and say so" \
	sh -c "grep -q 'Init failed.*error.not_uze' '$work/big.out' '$work/big.err' && grep -q 'Init failed.*error.not_uze' '$work/uz2.out' '$work/uz2.err'"
printf ':10000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00\n:00000001FF\n' > "$work/bad.hex"
folder bad '{}' "$work/bad.hex"
nat bad bad --frames 60 --report 60
check "stops:invalid" "a program that runs into an instruction the processor does not have stops, says so once ($(grep -c 'machine stopped' "$work/bad.err") times in 60 frames), and the frames go on in silence ($(field "$work/bad.out" aud) samples a frame)" \
	sh -c "[ $(grep -c 'machine stopped' "$work/bad.err") = 1 ] && grep -q '^frame    60' '$work/bad.out' && [ '$(field "$work/bad.out" aud)' = 262 ]"

# ------------------------------------------------- the Uzebox's own games
demos="$work/demos"
if sh "$root/tests/build-demos.sh" "$demos" > "$work/demos.log" 2>&1; then
	rm -f "$demos/DonkeyKong.uze"   # cut short by packrom; its .hex is whole
	for g in "$demos"/*.uze "$demos"/DonkeyKong.hex; do
		n="$(basename "${g%.*}")"
		folder "d-$n" '{}' "$g"
		nat "d-$n" "d-$n" --frames 600 --report 50
		box "d-$n-box" "d-$n" --frames 600 --report 50
		stream "$work/d-$n.out" > "$work/d-$n.stream"; stream "$work/d-$n-box.out" > "$work/d-$n-box.stream"
		stop=""; grep -q "machine stopped" "$work/d-$n.err" && stop=" (it stopped: $(head -1 "$work/d-$n.err"))"
		check "game:$n" "runs 600 frames$stop: $(pictures "$work/d-$n.out") different pictures and $(sounds "$work/d-$n.out") sounds in 12 reports; the sandbox gives the native build's digests" \
			sh -c "[ -z '$stop' ] && [ \$(wc -l < '$work/d-$n.stream') = 12 ] && cmp -s '$work/d-$n.stream' '$work/d-$n-box.stream'"
	done
else
	report "game:*" FAIL "the Uzebox's games did not build: $(tail -1 "$work/demos.log")"
fi

# ------------------------------------------------- upstream's own uzem
# upstream's uzem, built from the same commit without the patch, records its
# pictures and sound (tests/upstream-ffmpeg.sh); the core's must be the same
# (tests/compare-upstream.py). One game for each kind of video, and the
# test program; not the games that read an SD card (BootDemo, VideoDemo),
# which upstream gives one made of the game's folder and this core does not.
# Upstream leaves the power switch's pins low - pressed - from the start
# (nothing sets them until its 0 key comes up), where the core has them
# pulled up as the console does; the core's runs hold Power, to give the
# program upstream's pins. Upstream runs at the console's speed: 8 seconds
# each, all at once.
if sh "$root/tests/build-upstream-uzem.sh" "$work/upstream" > "$work/upstream.log" 2>&1; then
	mkdir -p "$work/fakebin"; cp "$root/tests/upstream-ffmpeg.sh" "$work/fakebin/ffmpeg"; chmod +x "$work/fakebin/ffmpeg"
	ugames="$progs/testprog.uze $demos/BcDash.uze $demos/Megatris.uze $demos/SpriteDemo.uze $demos/SuperMarioDemo.uze $demos/Whack-a-Mole.uze $demos/chess4uzebox.uze $demos/VectorDemo.uze $demos/BitmapDemo.uze $demos/Mode9Demo.uze $demos/MegaSokoban.uze $demos/Mode13ExtendedDemo.uze $demos/DonkeyKong.hex"
	for g in $ugames; do
		n="$(basename "${g%.*}")"
		mkdir -p "$work/up-$n"; cp "$g" "$work/up-$n/"
		(cd "$work/up-$n" && PATH="$work/fakebin:$PATH" SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
			timeout 8 "$work/upstream/uzem" -r -w "$(basename "$g")" > uzem.log 2>&1) &
	done
	wait
	for g in $ugames; do
		n="$(basename "${g%.*}")"
		folder "uc-$n" '{}' "$g"
		mkdir -p "$work/uc-$n/av"
		nat "uc-$n" "uc-$n" --frames 700 --press "$pw":1:700 --av-stream "$work/uc-$n/av"
		res="$(python3 "$root/tests/compare-upstream.py" "$work/up-$n" "$work/uc-$n/av" 2>&1)"; rc=$?
		check "upstream:$n" "$res" [ "$rc" = 0 ]
		rm -rf "$work/up-$n/frames.raw" "$work/uc-$n/av"
	done
else
	report "upstream:*" SKIP "upstream's uzem did not build (it needs SDL 2's development files): $(tail -1 "$work/upstream.log")"
fi

# ------------------------------------------------- Chimera's engine
runner="$chimera_root/build/dll/chimera-run"
package="$chimera_root/build/Cores/uzem.chimeraCore"
if [ -n "$chimera_root" ] && [ -x "$runner" ] && [ -f "$package" ]; then
	mkdir -p "$work/proj"
	cp "$progs/testprog.uze" "$work/proj/"
	python3 "$root/tests/make-project.py" "$package" "$work/proj/test.chimeraProject" 300 \
		"press=P1 A:199:101" "press=P2 Down:149:151" "press=Key Q:99:201" panel="$work/panel.out" -- game="$work/proj/testprog.uze" > /dev/null
	"$runner" --project "$work/proj/test.chimeraProject" "$package" --files "$work/proj" --frames 300 \
		--dump "RAM=$work/engine.ram" > "$work/engine.log" 2>&1
	box eng t --frames 300 --press "$(index t "P1 A")":200:101 --press "$(index t "P2 Down")":150:151 --press "$(index t "Key Q")":100:201 --dump-domain RAM "$work/eng.ram"
	check "engine:uze" "a project of the test program with presses plays in Chimera's headless runner to the sandbox runner's memory ($(wc -c < "$work/eng.ram" 2> /dev/null) bytes; the program read pads $(r "$work/engine.ram" pad1) and $(r "$work/engine.ram" pad2), and the key $(r "$work/engine.ram" keys))" \
		sh -c "cmp -s '$work/engine.ram' '$work/eng.ram' && [ '$(r "$work/engine.ram" pad1) $(r "$work/engine.ram" pad2) $(r "$work/engine.ram" keys)' = '256 32 71' ]"
	# each latch of the controllers is reported to Chimera as it happens, so a
	# Lua script's event.oninputpoll runs there (chimera#344): every frame the
	# program read its pads has at least one, and counting them moves nothing
	"$runner" --project "$work/proj/test.chimeraProject" "$package" --files "$work/proj" --frames 300 --count-input-polls \
		--dump "RAM=$work/polls.ram" --meta "$work/polls.meta" > "$work/polls.log" 2>&1
	polls=$(sed -n 's/^inputPolls=//p' "$work/polls.meta" 2> /dev/null)
	lags=$(sed -n 's/^lagFrames=//p' "$work/polls.meta" 2> /dev/null)
	check "engine:input-polls" "the program's reads of its controls reach Chimera as they happen: ${polls:-none} in 300 frames, ${lags:-?} of them lag frames; the memory is the run's without counting" \
		sh -c "[ '${polls:-none}' != none ] && [ '${polls:-0}' -ge $(( 300 - ${lags:-300} )) ] && [ '${lags:-300}' -lt 300 ] && cmp -s '$work/polls.ram' '$work/engine.ram'"
else
	report "engine:uze" SKIP "needs CHIMERA_ROOT with build/dll/chimera-run and build/Cores/uzem.chimeraCore"
	report "engine:input-polls" SKIP "needs CHIMERA_ROOT with build/dll/chimera-run and build/Cores/uzem.chimeraCore"
fi

echo
echo "$ok passed, $failed failed, $skipped skipped"
[ "$failed" -eq 0 ]
