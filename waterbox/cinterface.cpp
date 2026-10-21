// cinterface.cpp - Uzebox as a Chimera core: the functions Chimera calls.
//
// The machine is upstream's emulator, uzem (tools/uzem in the Uzebox
// repository): its AVR processor and the Uzebox's video, sound, controller
// and EEPROM hardware (avr8.cpp), and its loader of .uze and .hex games
// (uzerom.cpp). Upstream's own program around it opens a window with SDL;
// this file takes its place inside the sandbox. It loads the game and the
// EEPROM, gives the machine the controls before each frame, runs it to the
// end of a picture, and keeps the picture and the sound (patch 0001 hands
// both over instead of giving them to SDL).
//
// SPDX-License-Identifier: MIT
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include <emulibc.h>
#include <waterbox_settings.h>
#include <waterbox_slots.h>

#include "avr8.h"
#include "uzerom.h"

// ---- what went wrong, for Chimera to show ----------------------------------
static char g_loadError[512];

// ---- the machine -------------------------------------------------------------
// One Uzebox: an ATmega644 at 28.63636 MHz. A picture is 262 lines of 1820
// cycles (476,840 cycles, 60.05 a second), of which 224 are drawn.
static avr8 g_uzebox;
static RomHeader g_header;
static char g_gameName[256];
static bool g_halted;          // the processor met an instruction it does not know
static uint64_t g_frameCount;

enum : unsigned
{
	kCyclesPerLine = 1820,
	kCyclesPerFrame = kCyclesPerLine * 262,
	// a frame ends at its 224th line; a program that draws no picture (as
	// before the kernel starts its video) gets a frame and a half of
	// cycles, enough for one picture's jitter to never cut a frame short
	kFrameCycleLimit = kCyclesPerFrame * 3 / 2,
};

// ---- the picture -------------------------------------------------------------
// uzem's picture: 720 pixels by 224 lines, every second cycle of a line from
// a fixed point after the line's sync (its VIDEO_LEFT_EDGE), as upstream
// shows it. The colour of a pixel is the byte the program writes to PORTC:
// 3 bits red, 3 green, 2 blue.
enum { kWidth = VIDEO_DISP_WIDTH, kHeight = 224 };
ECL_INVISIBLE static uint32_t g_picture[kWidth * kHeight];
uint32_t *chimera_video;
static bool g_frameDone;

void chimera_frame_end(avr8 *machine)
{
	(void)machine;
	g_frameDone = true;
}

void chimera_halt(int errcode)
{
	if (!g_halted)
		fprintf(stderr, "the machine stopped (code %d): see the line above\n", errcode);
	g_halted = true;
}

// ---- the sound -----------------------------------------------------------------
// The Uzebox's sound is one 8-bit level, which the kernel's mixer writes to
// the PWM output (OCR2A) once a line. The core takes the level once every
// 1820 cycles - a line - so a frame has as many samples as lines were run:
// 15,734 samples a second, the chip's own rate, whatever the program does.
// upstream's SDL output does the same, from a queue the writes fill.
enum { kMaxSamples = kFrameCycleLimit / kCyclesPerLine + 2 };
ECL_INVISIBLE static int16_t g_audio[kMaxSamples * 2];
static int g_audioFrames;
static uint8_t g_soundLevel = 128;
static unsigned g_soundCycles;

void chimera_sound_level(uint8_t value) { g_soundLevel = value; }

static void take_samples(unsigned cycles)
{
	g_soundCycles += cycles;
	while (g_soundCycles >= kCyclesPerLine)
	{
		g_soundCycles -= kCyclesPerLine;
		if (g_audioFrames < kMaxSamples)
		{
			const int16_t v = (int16_t)((g_soundLevel - 128) * 256);
			g_audio[g_audioFrames * 2] = v;
			g_audio[g_audioFrames * 2 + 1] = v;
			g_audioFrames++;
		}
	}
}

// ---- the controls ------------------------------------------------------------
// Two SNES gamepads. Their buttons are listed grouped, as Chimera's SNES core
// lists them: the pad's arrows, Select and Start, the four buttons on its face
// and the two on its shoulders (chimera#335). The pad sends them in an order
// of its own, B, Y, Select, Start, Up, Down, Left, Right, A, X, L, R, and
// kPadWire is each listed button's place in that order. A SNES mouse can take
// the first gamepad's place (the P1 Controller setting; by default when the game's
// header asks for one). The Uzebox keyboard is read through the second
// controller port once the program starts talking to it. The power button
// is the console's soft power switch.
enum { kPadButtons = 12, kPads = 2 };
static const char *const kPadNames[kPadButtons] = {
	"Up", "Down", "Left", "Right", "Select", "Start", "Y", "B", "X", "A", "L", "R",
};
static const int kPadWire[kPadButtons] = { 4, 5, 6, 7, 2, 3, 1, 0, 9, 8, 10, 11 };

// The keyboard's keys and the PS/2 codes (scan code set 2) the keyboard
// sends for them: a key's code when it goes down, F0 and its code when it
// comes up. Keys marked extended are sent after an E0. The list is the
// keys of a PC keyboard with codes of one byte, and the extended ones that
// carry no fake shift (Print Screen and Pause are left out).
struct Key
{
	const char *name;
	uint8_t code;
	bool extended;
};
static const Key kKeys[] = {
	{ "A", 0x1C, false }, { "B", 0x32, false }, { "C", 0x21, false }, { "D", 0x23, false },
	{ "E", 0x24, false }, { "F", 0x2B, false }, { "G", 0x34, false }, { "H", 0x33, false },
	{ "I", 0x43, false }, { "J", 0x3B, false }, { "K", 0x42, false }, { "L", 0x4B, false },
	{ "M", 0x3A, false }, { "N", 0x31, false }, { "O", 0x44, false }, { "P", 0x4D, false },
	{ "Q", 0x15, false }, { "R", 0x2D, false }, { "S", 0x1B, false }, { "T", 0x2C, false },
	{ "U", 0x3C, false }, { "V", 0x2A, false }, { "W", 0x1D, false }, { "X", 0x22, false },
	{ "Y", 0x35, false }, { "Z", 0x1A, false },
	{ "0", 0x45, false }, { "1", 0x16, false }, { "2", 0x1E, false }, { "3", 0x26, false },
	{ "4", 0x25, false }, { "5", 0x2E, false }, { "6", 0x36, false }, { "7", 0x3D, false },
	{ "8", 0x3E, false }, { "9", 0x46, false },
	{ "`", 0x0E, false }, { "-", 0x4E, false }, { "=", 0x55, false }, { "[", 0x54, false },
	{ "]", 0x5B, false }, { "\\", 0x5D, false }, { ";", 0x4C, false }, { "'", 0x52, false },
	{ ",", 0x41, false }, { ".", 0x49, false }, { "/", 0x4A, false },
	{ "Space", 0x29, false }, { "Tab", 0x0D, false }, { "Return", 0x5A, false },
	{ "Backspace", 0x66, false }, { "Escape", 0x76, false }, { "Caps Lock", 0x58, false },
	{ "Left Shift", 0x12, false }, { "Right Shift", 0x59, false },
	{ "Left Ctrl", 0x14, false }, { "Right Ctrl", 0x14, true },
	{ "Left Alt", 0x11, false }, { "Right Alt", 0x11, true },
	{ "F1", 0x05, false }, { "F2", 0x06, false }, { "F3", 0x04, false }, { "F4", 0x0C, false },
	{ "F5", 0x03, false }, { "F6", 0x0B, false }, { "F7", 0x83, false }, { "F8", 0x0A, false },
	{ "F9", 0x01, false }, { "F10", 0x09, false }, { "F11", 0x78, false }, { "F12", 0x07, false },
	{ "Up", 0x75, true }, { "Down", 0x72, true }, { "Left", 0x6B, true }, { "Right", 0x74, true },
	{ "Insert", 0x70, true }, { "Delete", 0x71, true }, { "Home", 0x6C, true }, { "End", 0x69, true },
	{ "Page Up", 0x7D, true }, { "Page Down", 0x7A, true },
	{ "Num Lock", 0x77, false }, { "Scroll Lock", 0x7E, false },
	{ "Keypad 0", 0x70, false }, { "Keypad 1", 0x69, false }, { "Keypad 2", 0x72, false },
	{ "Keypad 3", 0x7A, false }, { "Keypad 4", 0x6B, false }, { "Keypad 5", 0x73, false },
	{ "Keypad 6", 0x74, false }, { "Keypad 7", 0x6C, false }, { "Keypad 8", 0x75, false },
	{ "Keypad 9", 0x7D, false }, { "Keypad .", 0x71, false }, { "Keypad +", 0x79, false },
	{ "Keypad -", 0x7B, false }, { "Keypad *", 0x7C, false }, { "Keypad /", 0x4A, true },
	{ "Keypad Enter", 0x5A, true },
};
enum : int
{
	kKeyCount = (int)(sizeof kKeys / sizeof kKeys[0]),
	kMouseLeft = kPads * kPadButtons,
	kMouseRight,
	kPower,
	kFirstKey,
	kButtonCount = kFirstKey + kKeyCount,
};
static char g_buttonNames[kButtonCount][24];
static bool g_held[kButtonCount];
static bool g_keyWasHeld[kKeyCount];

// The SNES mouse sends how far it moved since it was last read, -127 to
// 127 counts across and down. uzem reads the computer's mouse once a frame
// and gives the same movement to every read in the frame; Mouse Move X and
// Y are that movement.
enum { kMoveX, kMoveY, kAxes };
static const char *const kAxisNames[kAxes] = { "Mouse Move X", "Mouse Move Y" };
static int g_axis[kAxes];
static bool g_mouse;           // the SNES mouse is in the first port

int chimera_input_reads;
static bool g_inputRead;

static int clampi(int v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : v; }

// uzem's spelling of a movement, as its own SNES mouse sends it (avr8.cpp,
// encode_delta): a sign bit (set for positive), then the size's bits from
// the top, inverted, because the pad's lines are low when a bit is set.
static uint32_t snes_mouse_delta(int d)
{
	uint32_t r = d < 0 ? 0u : 1u;
	d = d < 0 ? -d : d;
	if (d > 127)
		d = 127;
	for (int bit = 6; bit >= 0; bit--)
		if (!(d & (1 << bit)))
			r |= 1u << (7 - bit);
	return r;
}

static void set_controls(void)
{
	// the lines are low when a button is pressed
	for (int p = 0; p < kPads; p++)
	{
		uint32_t pressed = 0;
		for (int b = 0; b < kPadButtons; b++)
			if (g_held[p * kPadButtons + b])
				pressed |= 1u << kPadWire[b];
		g_uzebox.buttons[p] = ~pressed;
	}
	if (g_mouse)
	{
		// the mouse's report, as uzem builds it: its movement in the top
		// bytes, its buttons at bits 8 and 9, bit 15 low (that is how the
		// kernel tells a mouse from a gamepad)
		uint32_t m = (snes_mouse_delta(clampi(g_axis[kMoveX], -127, 127)) << 24)
			| (snes_mouse_delta(clampi(g_axis[kMoveY], -127, 127)) << 16) | 0x7FFFu;
		if (g_held[kMouseLeft])
			m &= ~(1u << 9);
		if (g_held[kMouseRight])
			m &= ~(1u << 8);
		g_uzebox.buttons[0] = m;
	}

	// the soft power switch pulls PD2 and PD3 low while it is held; they are
	// pulled up otherwise (the kernel's IsPowerSwitchPressed reads them)
	if (g_held[kPower])
		g_uzebox.PIND &= (uint8_t)~0x0Cu;
	else
		g_uzebox.PIND |= 0x0Cu;

	// the keyboard sends what changed since the last frame; until the
	// program starts the keyboard it is not listening, as in uzem
	for (int k = 0; k < kKeyCount; k++)
	{
		const bool held = g_held[kFirstKey + k];
		if (held == g_keyWasHeld[k])
			continue;
		g_keyWasHeld[k] = held;
		if (!g_uzebox.uzeKbEnabled)
			continue;
		if (kKeys[k].extended)
			g_uzebox.uzeKbScanCodeQueue.push(0xE0);
		if (!held)
			g_uzebox.uzeKbScanCodeQueue.push(0xF0);
		g_uzebox.uzeKbScanCodeQueue.push(kKeys[k].code);
	}
}

// ---- the watchdog's jitter ---------------------------------------------------
// The kernel times the watchdog timer at power-on to seed games' random
// numbers, and uzem adds a random jitter to that timer from the C library's
// rand(), seeded from the computer's clock. The core seeds it from the
// Random Seed setting instead, and defines rand() here as musl has it, so
// that the sandbox and the native build draw the same numbers.
static uint64_t g_randSeed;
extern "C" void srand(unsigned s) { g_randSeed = s - 1; }
extern "C" int rand(void)
{
	g_randSeed = 6364136223846793005ULL * g_randSeed + 1;
	return (int)(g_randSeed >> 33);
}

// ---- files -------------------------------------------------------------------
static void *read_file(const char *name, long *size)
{
	FILE *f = fopen(name, "rb");
	if (!f)
		return nullptr;
	fseek(f, 0, SEEK_END);
	long n = ftell(f);
	fseek(f, 0, SEEK_SET);
	void *data = n > 0 ? malloc((size_t)n) : nullptr;
	if (data && fread(data, 1, (size_t)n, f) != (size_t)n)
	{
		free(data);
		data = nullptr;
	}
	fclose(f);
	*size = n;
	return data;
}

// A program in Intel's hex format: lines of ':', a count, an address, a
// type and the bytes, in hex digits. Data lines (type 0) are put in the
// flash; the end line (type 1) ends it; other types are passed over, as
// uzem does. Read here rather than with uzem's loadHex, which takes only
// capital letters for the digits but 'a', and does not look at where a line
// would write.
static int hex_digit(char c)
{
	if (c >= '0' && c <= '9')
		return c - '0';
	if (c >= 'A' && c <= 'F')
		return c - 'A' + 10;
	if (c >= 'a' && c <= 'f')
		return c - 'a' + 10;
	return -1;
}

static int hex_byte(const char *s, const char *end)
{
	if (end - s < 2)
		return -1;
	const int hi = hex_digit(s[0]), lo = hex_digit(s[1]);
	return hi < 0 || lo < 0 ? -1 : hi << 4 | lo;
}

static const char *load_hex(const char *text, long size, unsigned char *flash)
{
	const char *p = text, *end = text + size;
	bool any = false;
	while (p < end)
	{
		const char *eol = (const char *)memchr(p, '\n', (size_t)(end - p));
		const char *lineEnd = eol ? eol : end;
		while (lineEnd > p && (lineEnd[-1] == '\r' || lineEnd[-1] == ' '))
			lineEnd--;
		if (lineEnd > p)
		{
			if (*p != ':')
				return "a line does not start with ':'";
			const int count = hex_byte(p + 1, lineEnd), hi = hex_byte(p + 3, lineEnd),
				lo = hex_byte(p + 5, lineEnd), type = hex_byte(p + 7, lineEnd);
			if (count < 0 || hi < 0 || lo < 0 || type < 0 || lineEnd - p < 11 + 2 * count)
				return "a line is not hex digits, or is too short";
			if (type == 1)
				return any ? nullptr : "it holds no program";
			if (type == 0)
			{
				const unsigned addr = (unsigned)(hi << 8 | lo);
				if (addr + (unsigned)count > progSize)
					return "a line writes past the 64 KB of flash";
				for (int i = 0; i < count; i++)
				{
					const int b = hex_byte(p + 9 + 2 * i, lineEnd);
					if (b < 0)
						return "a line is not hex digits";
					flash[addr + i] = (unsigned char)b;
				}
				any = true;
			}
		}
		p = eol ? eol + 1 : end;
	}
	return any ? nullptr : "it holds no program";
}

static int setting_str(const char *name, char *out, int size)
{
	return wbx_setting_str(name, out, size);
}

static bool eeprom_is_blank(void)
{
	for (unsigned i = 0; i < eepromSize; i++)
		if (g_uzebox.eeprom[i] != 0xFF)
			return false;
	return true;
}

// ---- Chimera's calls -----------------------------------------------------------
extern "C" {

ECL_EXPORT const char *GetLoadError(void) { return g_loadError; }
ECL_EXPORT const char *SuggestSettings(void) { return "{\"values\":{},\"note\":\"\",\"firmware\":[]}"; }
ECL_EXPORT const char *DescribeDips(void) { return ""; }

ECL_EXPORT int Init(void)
{
	g_loadError[0] = '\0';
	g_gameName[0] = '\0';
	if (wbx_slot_count("game") > 0)
		wbx_slot_name("game", 0, g_gameName, sizeof g_gameName);
	else
	{
		// a game opened with no project is mounted under its own name
		FILE *f = fopen("rom.name", "rb");
		if (f)
		{
			size_t got = fread(g_gameName, 1, sizeof g_gameName - 1, f);
			g_gameName[got] = '\0';
			fclose(f);
		}
	}
	if (!g_gameName[0])
	{
		snprintf(g_loadError, sizeof g_loadError, "no game was given");
		return 0;
	}
	long size = 0;
	unsigned char *data = (unsigned char *)read_file(g_gameName, &size);
	if (!data)
	{
		snprintf(g_loadError, sizeof g_loadError, "the game %s could not be read", g_gameName);
		return 0;
	}
	// the program: a .uze file is a 512-byte header and the program, and is
	// loaded by uzem's own loader; a .hex file is the program in Intel's hex
	// format
	unsigned char *flash = (unsigned char *)g_uzebox.progmem;
	memset(&g_header, 0, sizeof g_header);
	const bool uze = size >= 512 && !memcmp(data, "UZEBOX", 6);
	const bool hex = size > 0 && data[0] == ':';
	if (uze)
	{
		// uzem reads as many bytes as the header says into the 64 KB of
		// flash, without a look at the number first
		const uint32_t progBytes = data[8] | data[9] << 8 | data[10] << 16 | (uint32_t)data[11] << 24;
		free(data);
		if (progBytes > progSize || !loadUzeImage(g_gameName, &g_header, flash))
		{
			snprintf(g_loadError, sizeof g_loadError, "%s could not be loaded as a .uze game (it may be for the Uzebox 2.0, which uzem does not run)", g_gameName);
			return 0;
		}
	}
	else if (hex)
	{
		const char *error = load_hex((const char *)data, size, flash);
		free(data);
		if (error)
		{
			snprintf(g_loadError, sizeof g_loadError, "%s could not be loaded as a .hex program: %s", g_gameName, error);
			return 0;
		}
	}
	else
	{
		free(data);
		snprintf(g_loadError, sizeof g_loadError, "%s is not an Uzebox game: neither a .uze file nor a .hex program", g_gameName);
		return 0;
	}
	g_uzebox.decodeFlash();

	// what upstream's init_gui sets for the machine (its window and sound
	// device are Chimera's)
	g_uzebox.left_edge_cycle = ~0u;
	g_uzebox.scanline_top = -33 - 5;
	g_uzebox.scanline_count = -999;
	g_uzebox.left_edge = VIDEO_LEFT_EDGE;
	g_uzebox.latched_buttons[0] = g_uzebox.buttons[0] = ~0u;
	g_uzebox.latched_buttons[1] = g_uzebox.buttons[1] = ~0u;
	g_uzebox.mouse_scale = 1;
	for (int i = 0; i < 256; i++)
	{
		const uint32_t r = (((i >> 0) & 7) * 255) / 7;
		const uint32_t g = (((i >> 3) & 7) * 255) / 7;
		const uint32_t b = (((i >> 6) & 3) * 255) / 3;
		g_uzebox.palette[i] = 0xFF000000u | r << 16 | g << 8 | b;
	}
	chimera_video = g_picture;
	memset(g_picture, 0, sizeof g_picture);

	// the first port: the game's header says whether it wants a mouse, as
	// uzem reads it; the setting can say otherwise
	{
		char v[16] = "auto";
		setting_str("p1Controller", v, sizeof v);
		if (!strcmp(v, "mouse"))
			g_mouse = true;
		else if (!strcmp(v, "gamepad"))
			g_mouse = false;
		else
			g_mouse = (g_header.pdefault & PERIPHERAL_MOUSE) != 0;
		g_uzebox.pad_mode = g_mouse ? avr8::SNES_MOUSE : avr8::SNES_PAD;
	}

	{
		char v[24];
		unsigned seed = 0;
		if (setting_str("randomSeed", v, sizeof v) > 0)
			seed = (unsigned)strtoul(v, nullptr, 10);
		srand(seed);
	}

	// the EEPROM: blank (all FF) as uzem starts it with no eeprom.bin, or the
	// project's save data
	memset(g_uzebox.eeprom, 0xFF, eepromSize);
	if (wbx_slot_count("savedata") > 0)
	{
		char name[256];
		if (wbx_slot_name("savedata", 0, name, sizeof name))
		{
			long n = 0;
			void *saved = read_file(name, &n);
			if (saved)
			{
				memcpy(g_uzebox.eeprom, saved, n < (long)eepromSize ? (size_t)n : eepromSize);
				free(saved);
			}
		}
	}
	// uzem never writes the EEPROM to a file: Export Save Data does
	g_uzebox.eepromFile = nullptr;

	for (int p = 0; p < kPads; p++)
		for (int b = 0; b < kPadButtons; b++)
			snprintf(g_buttonNames[p * kPadButtons + b], sizeof g_buttonNames[0], "P%d %s", p + 1, kPadNames[b]);
	snprintf(g_buttonNames[kMouseLeft], sizeof g_buttonNames[0], "Mouse Left");
	snprintf(g_buttonNames[kMouseRight], sizeof g_buttonNames[0], "Mouse Right");
	snprintf(g_buttonNames[kPower], sizeof g_buttonNames[0], "Power");
	for (int k = 0; k < kKeyCount; k++)
		snprintf(g_buttonNames[kFirstKey + k], sizeof g_buttonNames[0], "Key %s", kKeys[k].name);

	g_uzebox.PIND |= 0x0Cu;
	g_frameCount = 0;
	return 1;
}

ECL_EXPORT int GetButtonCount(void) { return kButtonCount; }
ECL_EXPORT const char *GetButtonName(int32_t i) { return i >= 0 && i < kButtonCount ? g_buttonNames[i] : ""; }
ECL_EXPORT int IsButtonActive(int32_t i)
{
	if (i < 0 || i >= kButtonCount)
		return 0;
	// the first gamepad and the mouse share the first port
	if (i < kPadButtons)
		return !g_mouse;
	if (i == kMouseLeft || i == kMouseRight)
		return g_mouse;
	return 1;
}
ECL_EXPORT void SetButton(int32_t i, int32_t state)
{
	if (i >= 0 && i < kButtonCount)
		g_held[i] = state != 0;
}

ECL_EXPORT int GetAxisCount(void) { return kAxes; }
ECL_EXPORT const char *GetAxisName(int32_t i) { return i >= 0 && i < kAxes ? kAxisNames[i] : ""; }
ECL_EXPORT int IsAxisActive(int32_t i) { return i >= 0 && i < kAxes && g_mouse; }
ECL_EXPORT void SetAxis(int32_t i, int32_t value)
{
	if (i >= 0 && i < kAxes)
		g_axis[i] = value;
}

ECL_EXPORT void FrameAdvance(uint64_t packed)
{
	(void)packed;
	g_audioFrames = 0;
	chimera_input_reads = 0;
	set_controls();
	g_frameDone = false;
	unsigned cycles = 0;
	while (!g_frameDone && !g_halted && cycles < kFrameCycleLimit)
	{
		const unsigned c = g_uzebox.exec();
		cycles += c;
		take_samples(c);
	}
	// a stopped machine is still: the rest of the frame is silence
	if (g_halted && cycles < kCyclesPerFrame)
	{
		g_soundLevel = 128;
		take_samples(kCyclesPerFrame - cycles);
	}
	g_frameCount++;
	g_inputRead = chimera_input_reads > 0;
}

ECL_EXPORT int InputWasRead(void) { return g_inputRead; }
ECL_EXPORT void SetRenderingEnabled(int on) { chimera_video = on ? g_picture : nullptr; }

ECL_EXPORT uint32_t *GetVideoBgra(void) { return g_picture; }
ECL_EXPORT int GetVideoWidth(void) { return kWidth; }
ECL_EXPORT int GetVideoHeight(void) { return kHeight; }
// uzem's window shows the 720x224 picture at 630x448
ECL_EXPORT int GetDisplayAspectX(void) { return 630; }
ECL_EXPORT int GetDisplayAspectY(void) { return 448; }
// 28,636,360 cycles a second over 476,840 a frame
ECL_EXPORT int GetVsyncNumerator(void) { return 3579545; }
ECL_EXPORT int GetVsyncDenominator(void) { return 59605; }

ECL_EXPORT int16_t *GetAudio(void) { return g_audio; }
ECL_EXPORT int GetAudioSampleCount(void) { return g_audioFrames; }

// RAM is the processor's 4 KB of SRAM: data address 0x0100 is its first
// byte (a game's symbol at 0x800100 in avr-gcc's map is at 0 here). The
// EEPROM is 2 KB. Flash is the 64 KB the program is in, read only (uzem
// keeps the program decoded beside it).
ECL_EXPORT int GetMemoryDomainCount(void) { return 3; }
ECL_EXPORT const char *GetMemoryDomainName(int i)
{
	static const char *const names[] = { "RAM", "EEPROM", "Flash" };
	return i >= 0 && i < 3 ? names[i] : "";
}
ECL_EXPORT uint8_t *GetMemoryDomainPtr(int i)
{
	switch (i)
	{
	case 0: return g_uzebox.sram;
	case 1: return g_uzebox.eeprom;
	case 2: return (uint8_t *)g_uzebox.progmem;
	default: return nullptr;
	}
}
ECL_EXPORT int64_t GetMemoryDomainSize(int i)
{
	switch (i)
	{
	case 0: return sramSize;
	case 1: return eepromSize;
	case 2: return progSize;
	default: return 0;
	}
}
ECL_EXPORT int GetMemoryDomainWritable(int i) { return i == 0 || i == 1; }

ECL_EXPORT const int64_t *GetBusRanges(int32_t bus) { (void)bus; return nullptr; }
ECL_EXPORT const uint8_t *ReadBus(int32_t bus, int64_t addr, int32_t len) { (void)bus; (void)addr; (void)len; return nullptr; }
ECL_EXPORT void PokeBus(int32_t bus, int32_t addr, int32_t value) { (void)bus; (void)addr; (void)value; }

// Export Save Data: the EEPROM, 2 KB, under uzem's name for it, once a
// game has written anything to it. Every Uzebox game shares the one EEPROM,
// each in blocks of its own, so the file is the console's and not a game's.
ECL_EXPORT int32_t GetSaveDataFileCount(void) { return eeprom_is_blank() ? 0 : 1; }
ECL_EXPORT const char *GetSaveDataFileName(int32_t i) { return i == 0 ? "eeprom.bin" : ""; }
ECL_EXPORT int64_t GetSaveDataFileSize(int32_t i) { return i == 0 ? (int64_t)eepromSize : 0; }
ECL_EXPORT const uint8_t *GetSaveDataFileBuffer(int32_t i) { return i == 0 ? g_uzebox.eeprom : nullptr; }

} // extern "C"
