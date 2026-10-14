/* testprog.c - the core's test program, for the Uzebox, on its own kernel.
 *
 * Every frame it reads the controls the way games do (the kernel's
 * ReadJoypad and ReadJoypadExt, the keyboard through the kernel's own
 * driver, the power switch) and writes what it read into a block of its
 * memory that begins with "UZTEST01", where the test script finds it. It
 * draws a picture that moves, sounds a note while P1 A is held, counts in
 * the EEPROM, and keeps the random seed the kernel measured with the
 * watchdog at power-on.
 *
 * Built by tests/build-testprog.sh. With -DNO_CONTROLS it reads no control
 * at all (the kernel is told not to read them either): every frame of it
 * is a lag frame.
 *
 * SPDX-License-Identifier: MIT
 */
#include <stdbool.h>
#include <string.h>
#include <avr/io.h>
#include <avr/pgmspace.h>
#include <uzebox.h>
#ifndef NO_CONTROLS
#include <keyboard.h>
#endif

/* the results; offsets are the test script's (waterbox/run-gate.sh) */
struct Results
{
	char magic[8];        /* +0  "UZTEST01" */
	u32 frames;           /* +8  frames counted by the program */
	u16 pad1, pad2;       /* +12 +14  ReadJoypad(0), ReadJoypad(1): a bit set is a button down */
	u16 ext1;             /* +16 ReadJoypadExt(0): the mouse's movement */
	u8 power;             /* +18 IsPowerSwitchPressed() */
	u8 eepromSeen;        /* +19 the EEPROM byte at 16 when the program read it */
	u16 seed;             /* +20 GetTrueRandomSeed() */
	u8 rawCount;          /* +22 bytes the keyboard sent */
	u8 keyCount;          /* +23 keys the kernel's driver decoded */
	u8 raw[16];           /* +24 the first 16 bytes the keyboard sent */
	u8 keys[8];           /* +40 the first 8 keys the kernel decoded */
	u8 modifiers;         /* +48 the kernel's shift, ctrl and alt flags */
	u8 pad1Max;           /* +49 the most bits of pad1 ever set at once */
	u16 pad1Seen;         /* +50 every bit pad1 has had */
};
volatile struct Results results;

/* four tiles of one colour each, 6x8 pixels (colours are BBGGGRRR):
 * black, red, green, blue */
#define R8(c) c, c, c, c, c, c, c, c
#define TILE(c) R8(c), R8(c), R8(c), R8(c), R8(c), R8(c)
static const char tiles[] PROGMEM = { TILE(0x00), TILE(0x07), TILE(0x38), TILE(0xC0) };

static const char beep[] PROGMEM = {
	0, PC_WAVE, 3,
	0, PATCH_END,
};
static const struct PatchStruct patches[] PROGMEM = {
	{ 0, NULL, beep, 0, 0 },
};

#ifndef NO_CONTROLS
static u8 bits(u16 v)
{
	u8 n = 0;
	for (; v; v >>= 1)
		n += v & 1;
	return n;
}
#endif

int main(void)
{
	SetTileTable(tiles);
	ClearVram();
	InitMusicPlayer(patches);

	memcpy((void *)results.magic, "UZTEST01", 8);
	results.seed = GetTrueRandomSeed();

	bool playing = false;
	for (;;)
	{
		WaitVsync(1);
		u32 f = ++results.frames;

		/* a bar that runs down the screen, so that the picture moves */
		for (u8 x = 0; x < SCREEN_TILES_H; x++)
		{
			SetTile(x, (f - 1) % SCREEN_TILES_V, 0);
			SetTile(x, f % SCREEN_TILES_V, 1);
		}

#ifndef NO_CONTROLS
		results.pad1 = ReadJoypad(0);
		results.pad2 = ReadJoypad(1);
		results.ext1 = ReadJoypadExt(0);
		results.power = IsPowerSwitchPressed();
		results.pad1Seen |= results.pad1;
		if (bits(results.pad1) > results.pad1Max)
			results.pad1Max = bits(results.pad1);

		/* the pads' buttons as tiles in the top row */
		for (u8 b = 0; b < 16; b++)
		{
			SetTile(b, 0, (results.pad1 >> b) & 1 ? 2 : 0);
			SetTile(b + 20, 0, (results.pad2 >> b) & 1 ? 3 : 0);
		}

		/* a note while P1 A is held */
		if ((results.pad1 & BTN_A) && !playing)
		{
			TriggerNote(0, 0, 60, 255);
			playing = true;
		}
		else if (!(results.pad1 & BTN_A) && playing)
		{
			TriggerNote(0, 0, 60, 0);
			playing = false;
		}

		/* the keyboard: one byte a frame, as the kernel's KeyboardPoll reads */
		{
			extern u8 _ReadKey(u8 command);
			extern void _Decode(u8 sc);
			extern u8 bufferedKey;
			extern u8 modifiers;
			u8 sc = _ReadKey(0x01);
			if (sc)
			{
				if (results.rawCount < sizeof results.raw)
					results.raw[results.rawCount] = sc;
				results.rawCount++;
				_Decode(sc);
				if (bufferedKey)
				{
					if (results.keyCount < sizeof results.keys)
						results.keys[results.keyCount] = bufferedKey;
					results.keyCount++;
					bufferedKey = 0;
				}
				results.modifiers = modifiers;
			}
		}
#endif

		/* the EEPROM: the byte at 16 counts the runs that reached frame 100 */
		if (f == 100)
		{
			u8 v = ReadEeprom(16);
			results.eepromSeen = v;
			WriteEeprom(16, v + 1);
		}
	}
}
