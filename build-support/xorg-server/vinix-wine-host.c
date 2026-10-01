// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
//
// Host one Wine application on an off-screen Xvfb display. vinix-desktop maps
// Xvfb's XWD framebuffer into a normal compositor window and sends compact
// input records here; XTEST turns them back into ordinary X11 events.

#include <X11/Xlib.h>
#include <X11/keysym.h>
#include <X11/extensions/XTest.h>
#include <X11/extensions/Xdamage.h>

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define WINE_HOST_EVENT_MAGIC UINT32_C(0x56574831) /* VWH1 */
#define WINE_HOST_MAX_KEYS 4096
#define OBS_SCREEN_LINK "/run/vinix-obs-screen"
#define OBS_CAPTURE_GEOMETRY "1280x900x24"

enum wine_host_event_kind {
    WINE_HOST_MOTION = 1,
    WINE_HOST_BUTTON_DOWN,
    WINE_HOST_BUTTON_UP,
    WINE_HOST_KEYS,
    WINE_HOST_MIDDLE_DOWN,
    WINE_HOST_MIDDLE_UP,
    WINE_HOST_RIGHT_DOWN,
    WINE_HOST_RIGHT_UP,
    WINE_HOST_WHEEL_UP,
    WINE_HOST_WHEEL_DOWN,
};

struct wine_host_event {
    uint32_t magic;
    uint32_t kind;
    int32_t x;
    int32_t y;
    uint32_t length;
};

_Static_assert(sizeof(struct wine_host_event) == 20,
               "Wine host event ABI changed");

static volatile sig_atomic_t running = 1;
static int hold_game_keys = 0;
#define GAME_KEY_HOLD_MS 500
#define MAX_HELD_GAME_KEYS 16

struct held_game_key {
    KeyCode code;
    uint64_t release_at_ms;
};

static struct held_game_key held_game_keys[MAX_HELD_GAME_KEYS];

static void stop_running(int signal_number) {
    (void)signal_number;
    running = 0;
}

static int ignore_x_error(Display *display, XErrorEvent *event) {
    (void)display;
    (void)event;
    return 0;
}

static void sleep_10ms(void) {
    const struct timespec delay = { 0, 10000000 };
    nanosleep(&delay, NULL);
}

static uint64_t monotonic_millis(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0)
        return 0;
    return (uint64_t)now.tv_sec * 1000 + (uint64_t)now.tv_nsec / 1000000;
}

/* The desktop names each hosted display after the process that asked for it,
 * and a process id is released the moment that process exits — while the host
 * it started is still stopping its X server. Relaunching an application then
 * lands on a display number whose old server is alive, or whose lock file it
 * left behind names a process id that has since been reused, and Xvfb refuses
 * to start: "Server is already active for display N".
 *
 * So the number the desktop asks for is a starting point, not a promise. Take
 * the first display from there that nothing is serving and nothing holds, and
 * clear whatever a killed server left behind on it. */
static int display_number(const char *display_name) {
    const char *digit = display_name;
    int number = 0;

    while (*digit == ':')
        ++digit;
    if (*digit == '\0')
        return -1;
    for (; *digit != '\0'; ++digit) {
        if (*digit < '0' || *digit > '9')
            return -1;
        number = number * 10 + (*digit - '0');
        if (number > 65535)
            return -1;
    }
    return number;
}

/* Remove what a killed X server left on a display. Xvfb cleans these up when
 * it is asked to stop, but not when it has to be killed. */
static void remove_display_files(int number) {
    char path[64];

    if (number < 0)
        return;
    snprintf(path, sizeof(path), "/tmp/.X11-unix/X%d", number);
    unlink(path);
    snprintf(path, sizeof(path), "/tmp/.X%d-lock", number);
    unlink(path);
}

/* The framebuffer and damage counter are temporary files. Without removing
 * them, a closed application leaves its private tmpfs directory behind and
 * repeated game launches retain one framebuffer per run. */
static void remove_surface_files(const char *directory) {
    char path[PATH_MAX];
    const char *names[] = { "Xvfb_screen0", "Xvfb_screen1", "damage" };
    for (size_t index = 0; index < sizeof(names) / sizeof(names[0]); ++index) {
        if (snprintf(path, sizeof(path), "%s/%s", directory, names[index]) <
            (int)sizeof(path))
            unlink(path);
    }
}

/* True when nothing answers on this display. A lock file whose server is gone
 * is removed on the way: its recorded process id is no help, because the id
 * has usually been handed to something unrelated by the time anyone looks. */
static int claim_display_number(int number) {
    char socket_path[64];
    struct sockaddr_un address;
    int probe;

    snprintf(socket_path, sizeof(socket_path), "/tmp/.X11-unix/X%d", number);
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    snprintf(address.sun_path, sizeof(address.sun_path), "%s", socket_path);

    probe = socket(AF_UNIX, SOCK_STREAM, 0);
    if (probe >= 0) {
        int connected = connect(probe, (struct sockaddr *)&address,
                                sizeof(address)) == 0;
        close(probe);
        if (connected)
            return 0; /* Somebody is serving this display. */
    }
    remove_display_files(number);
    return 1;
}

/* Fill `storage` with the display to use and return it, or NULL if every
 * candidate is busy. */
static const char *claim_display(const char *requested, char *storage,
                                 size_t size) {
    int base = display_number(requested);

    if (base < 0)
        return requested;
    for (int offset = 0; offset < 64; ++offset) {
        int number = base + offset;
        if (number > 65535)
            break;
        if (claim_display_number(number)) {
            snprintf(storage, size, ":%d", number);
            return storage;
        }
    }
    return NULL;
}

static pid_t spawn_xvfb(const char *display_name, const char *directory,
                        const char *geometry, int game_input, int obs_capture, int shm_present) {
    pid_t pid = fork();
    const char *xvfb;
    if (pid != 0)
        return pid;

    setenv("LD_LIBRARY_PATH", "/usr/lib:/usr/lib/xorg/modules", 1);
    setenv("LIBGL_ALWAYS_SOFTWARE", "1", 1);
    setenv("LIBGL_DRIVERS_PATH", "/usr/lib/xorg/modules/dri", 1);
    setenv("GALLIUM_DRIVER", "softpipe", 1);
    xvfb = !game_input && access("/usr/bin/Xvfb-glx", X_OK) == 0
               ? "/usr/bin/Xvfb-glx" : "/usr/bin/Xvfb";
    /* Preserve the proven ordinary X11 transport for existing hosted apps.
     * OBS needs MIT-SHM for Display Capture, so only its private server
     * advertises the extension. Vinix implements the SysV backing now. */
    if (obs_capture) {
        /* Screen 0 holds the Qt controls. Screen 1 is fed by the native
         * compositor and is the source OBS records. XSHM needs MIT-SHM;
         * Vinix's SysV shared-memory syscalls provide it. RandR reports only
         * the first Xvfb root here, so disable it to let OBS enumerate both
         * X11 screens as Display 0 and Display 1. */
        execl(xvfb, "Xvfb", display_name, "-screen", "0", geometry,
              "-screen", "1", OBS_CAPTURE_GEOMETRY, "-fbdir", directory,
              "-nolisten", "tcp", "-noreset", "-ac", "+extension", "GLX",
              "+iglx", "-extension", "RANDR", (char *)NULL);
    } else if (shm_present) {
        /* Venus renders on the host GPU and presents through MIT-SHM. */
        execl(xvfb, "Xvfb", display_name, "-screen", "0", geometry,
              "-fbdir", directory, "-nolisten", "tcp", "-noreset", "-ac",
              (char *)NULL);
    } else if (game_input) {
        execl(xvfb, "Xvfb", display_name, "-screen", "0", geometry,
              "-fbdir", directory, "-nolisten", "tcp", "-noreset", "-ac",
              "-extension", "MIT-SHM", (char *)NULL);
    } else {
        execl(xvfb, "Xvfb", display_name, "-screen", "0", geometry,
              "-fbdir", directory, "-nolisten", "tcp", "-noreset", "-ac",
              "-extension", "MIT-SHM", "+extension", "GLX", "+iglx",
              (char *)NULL);
    }
    _exit(127);
}

static int publish_obs_screen(const char *directory) {
    char path[PATH_MAX];
    if (snprintf(path, sizeof(path), "%s/Xvfb_screen1", directory) >=
        (int)sizeof(path))
        return -1;
    if (access(path, F_OK) != 0)
        return -1;
    /* An orphaned link from a crashed host may remain. A live host's link
     * still has its target, so leave that session alone. */
    if (access(OBS_SCREEN_LINK, F_OK) != 0)
        unlink(OBS_SCREEN_LINK);
    if (symlink(path, OBS_SCREEN_LINK) != 0)
        return -1;
    return 0;
}

static void unpublish_obs_screen(const char *directory) {
    char expected[PATH_MAX];
    char current[PATH_MAX];
    ssize_t length;
    if (snprintf(expected, sizeof(expected), "%s/Xvfb_screen1", directory) >=
        (int)sizeof(expected))
        return;
    length = readlink(OBS_SCREEN_LINK, current, sizeof(current) - 1);
    if (length < 0)
        return;
    current[length] = '\0';
    if (strcmp(current, expected) == 0)
        unlink(OBS_SCREEN_LINK);
}

static Display *open_display(const char *display_name, pid_t xvfb_pid) {
    int attempt;

    for (attempt = 0; attempt < 300 && running; ++attempt) {
        int status;
        Display *display = XOpenDisplay(display_name);
        if (display != NULL)
            return display;
        if (waitpid(xvfb_pid, &status, WNOHANG) == xvfb_pid)
            return NULL;
        sleep_10ms();
    }
    return NULL;
}

static pid_t spawn_wine(const char *display_name, const char *command) {
    pid_t pid = fork();
    if (pid != 0)
        return pid;

    setenv("DISPLAY", display_name, 1);
    setenv("LIBGL_ALWAYS_SOFTWARE", "1", 1);
    unsetenv("LIBGL_ALWAYS_INDIRECT");
    setenv("GALLIUM_DRIVER", "llvmpipe", 1);
    setenv("WINEDEBUG", "-all", 0);
    execl(command, command, (char *)NULL);
    _exit(127);
}

static void fake_key(Display *display, KeySym symbol, Bool pressed) {
    KeyCode code = XKeysymToKeycode(display, symbol);
    if (code != 0)
        XTestFakeKeyEvent(display, code, pressed, CurrentTime);
}

static void hold_game_key(Display *display, KeySym symbol) {
    KeyCode code = XKeysymToKeycode(display, symbol);
    int index;
    int free_slot = -1;
    uint64_t deadline = monotonic_millis() + GAME_KEY_HOLD_MS;

    if (code == 0)
        return;
    for (index = 0; index < MAX_HELD_GAME_KEYS; ++index) {
        if (held_game_keys[index].code == code) {
            held_game_keys[index].release_at_ms = deadline;
            return;
        }
        if (free_slot < 0 && held_game_keys[index].code == 0)
            free_slot = index;
    }
    if (free_slot < 0)
        return;
    held_game_keys[free_slot].code = code;
    held_game_keys[free_slot].release_at_ms = deadline;
    XTestFakeKeyEvent(display, code, True, CurrentTime);
    XFlush(display);
}

static void release_expired_game_keys(Display *display) {
    uint64_t now = monotonic_millis();
    int index;
    int released = 0;

    for (index = 0; index < MAX_HELD_GAME_KEYS; ++index) {
        if (held_game_keys[index].code == 0 ||
            now < held_game_keys[index].release_at_ms)
            continue;
        XTestFakeKeyEvent(display, held_game_keys[index].code, False,
                          CurrentTime);
        held_game_keys[index].code = 0;
        released = 1;
    }
    if (released)
        XFlush(display);
}

static void tap_key(Display *display, KeySym symbol, int shift, int control) {
    if (hold_game_keys && !shift && !control) {
        hold_game_key(display, symbol);
        return;
    }
    if (control)
        fake_key(display, XK_Control_L, True);
    if (shift)
        fake_key(display, XK_Shift_L, True);
    fake_key(display, symbol, True);
    fake_key(display, symbol, False);
    if (shift)
        fake_key(display, XK_Shift_L, False);
    if (control)
        fake_key(display, XK_Control_L, False);
}

static void type_ascii(Display *display, unsigned char byte) {
    static const char shifted[] = "!@#$%^&*()_+{}|:\"~<>?";
    static const char bases[] = "1234567890-=[]\\;'\x60,./";
    const char *position;

    /* Return, Tab and Backspace are control characters too, so they go before
     * the Ctrl chords, which would otherwise take them. Enter became Ctrl+J or
     * Ctrl+M and Backspace Ctrl+H: a Windows edit control reads those as the
     * same keys, but GTK does not, and Enter never reached Firefox. */
    if (byte == '\n' || byte == '\r') {
        tap_key(display, XK_Return, 0, 0);
        return;
    }
    if (byte == '\t') {
        tap_key(display, XK_Tab, 0, 0);
        return;
    }
    if (byte == '\b' || byte == 0x7f) {
        tap_key(display, XK_BackSpace, 0, 0);
        return;
    }
    if (byte >= 1 && byte <= 26) {
        tap_key(display, (KeySym)('a' + byte - 1), 0, 1);
        return;
    }
    if (byte >= 'A' && byte <= 'Z') {
        tap_key(display, (KeySym)(byte - 'A' + 'a'), 1, 0);
        return;
    }
    position = strchr(shifted, byte);
    if (position != NULL) {
        tap_key(display, (KeySym)bases[position - shifted], 1, 0);
        return;
    }
    if (byte >= 0x20 && byte <= 0x7e)
        tap_key(display, (KeySym)byte, 0, 0);
}

/* Characters beyond ASCII arrive as UTF-8, and the keymap Xvfb starts with is
 * plain US: an é, a й or a € usually has no key at all. Do what xdotool does
 * and borrow a keycode nothing uses, bind the character's keysym to it with
 * XChangeKeyboardMapping and tap that. The server tells every client about the
 * change with a MappingNotify, and because the binding and the fake key are
 * requests on this one connection, it applies the binding and queues that
 * notification to each client before it synthesizes the key.
 *
 * What ordering cannot promise is when the application reads the new map:
 * Xlib and GTK fetch it again lazily and get whatever the server holds by
 * then. Rebinding a keycode while the application still has an unread key
 * event on it would make that event type the newer character. So bindings
 * stay in a set of borrowed keycodes that repeated characters reuse without
 * remapping, and the keycode given up for a new character is the one tapped
 * longest ago, never one tapped within UNICODE_KEY_SETTLE_MS: long enough for
 * an application on an emulated core to reach a queued key, short enough that
 * only a burst of new characters, never typing, has to wait for it.
 *
 * The borrowed bindings are not undone: this Xvfb is private to one
 * application and goes away with it. */
#define UNICODE_KEY_SLOTS 32
#define UNICODE_KEY_SETTLE_MS 500

/* A burst taps many keys within one millisecond, so the order they were tapped
 * in is kept as a count; the clock only times the settle. */
struct unicode_key {
    KeyCode code;
    KeySym symbol; /* NoSymbol until the keycode is first borrowed. */
    uint64_t tap_number; /* 0 until first tapped. */
    uint64_t tapped_at_ms;
};

static int keyboard_scanned = 0;
/* Unshifted and shifted keysym of every key in group 1 of the map Xvfb
 * started with, before anything was borrowed. */
static KeySym original_keysyms[256][2];
static struct unicode_key unicode_keys[UNICODE_KEY_SLOTS];
static int unicode_key_count = 0;
static uint64_t unicode_key_taps = 0;

/* The compositor sends whole characters today, but nothing in the record
 * format promises it, so a sequence split between two records is finished by
 * the next one rather than lost. */
static uint32_t utf8_code_point = 0;
static int utf8_length = 0;    /* Bytes in the sequence being read. */
static int utf8_remaining = 0; /* Continuation bytes still to come. */

static int keycode_is_modifier(const XModifierKeymap *modifiers, int code) {
    int index;

    if (modifiers == NULL)
        return 0;
    for (index = 0; index < 8 * modifiers->max_keypermod; ++index) {
        if (modifiers->modifiermap[index] == code)
            return 1;
    }
    return 0;
}

/* Read the keymap once, at the first character that needs it, so that it is
 * the one the application started with. A spare keycode has nothing bound in
 * any column: <ALT>, <META> and friends leave the first column empty but carry
 * a modifier keysym further along, and are left alone along with anything
 * else in the modifier map. */
static void scan_keyboard_map(Display *display) {
    XModifierKeymap *modifiers;
    KeySym *map;
    int min_code = 0;
    int max_code = 0;
    int per_code = 0;
    int code;

    if (keyboard_scanned)
        return;
    keyboard_scanned = 1;
    XDisplayKeycodes(display, &min_code, &max_code);
    if (min_code < 0 || max_code > 255 || min_code > max_code)
        return;
    map = XGetKeyboardMapping(display, (KeyCode)min_code,
                              max_code - min_code + 1, &per_code);
    if (map == NULL)
        return;
    if (per_code <= 0) {
        XFree(map);
        return;
    }
    modifiers = XGetModifierMapping(display);
    for (code = min_code; code <= max_code; ++code) {
        const KeySym *row = map + (size_t)(code - min_code) * (size_t)per_code;
        int bound = 0;
        int column;

        for (column = 0; column < per_code; ++column) {
            if (row[column] != NoSymbol)
                bound = 1;
        }
        original_keysyms[code][0] = row[0];
        original_keysyms[code][1] = per_code > 1 ? row[1] : NoSymbol;
        if (!bound && unicode_key_count < UNICODE_KEY_SLOTS &&
            !keycode_is_modifier(modifiers, code)) {
            unicode_keys[unicode_key_count].code = (KeyCode)code;
            unicode_keys[unicode_key_count].symbol = NoSymbol;
            unicode_keys[unicode_key_count].tap_number = 0;
            unicode_keys[unicode_key_count].tapped_at_ms = 0;
            ++unicode_key_count;
        }
    }
    if (modifiers != NULL)
        XFreeModifiermap(modifiers);
    XFree(map);
}

/* Find the character on an ordinary key: unshifted anywhere first, then
 * shifted, as XKeysymToKeycode searches. Characters on the third level or in
 * another group would need AltGr or a group switch; borrowing a keycode is
 * simpler than reproducing either. */
static int find_original_key(KeySym symbol, KeyCode *code, int *shift) {
    int column;
    int index;

    for (column = 0; column < 2; ++column) {
        for (index = 0; index < 256; ++index) {
            if (original_keysyms[index][column] == symbol) {
                *code = (KeyCode)index;
                *shift = column;
                return 1;
            }
        }
    }
    return 0;
}

/* Wait out the settle time of a borrowed keycode without starving held game
 * keys, which are due for release on their own clock. */
static void wait_until(Display *display, uint64_t deadline_ms) {
    while (monotonic_millis() < deadline_ms) {
        if (hold_game_keys)
            release_expired_game_keys(display);
        sleep_10ms();
    }
}

static struct unicode_key *borrow_key(Display *display, KeySym symbol) {
    struct unicode_key *oldest = NULL;
    KeySym columns[2];
    int index;

    for (index = 0; index < unicode_key_count; ++index) {
        struct unicode_key *key = &unicode_keys[index];
        if (key->symbol == symbol)
            return key;
        if (oldest == NULL || key->tap_number < oldest->tap_number)
            oldest = key;
    }
    if (oldest == NULL)
        return NULL;
    if (oldest->symbol != NoSymbol)
        wait_until(display, oldest->tapped_at_ms + UNICODE_KEY_SETTLE_MS);
    /* Bind the keysym in both columns. Given only one, the server fills in
     * the case pair itself and makes the key alphabetic, so a borrowed É
     * would become [é, É] and type é when tapped unshifted. */
    columns[0] = symbol;
    columns[1] = symbol;
    XChangeKeyboardMapping(display, oldest->code, 2, columns, 1);
    oldest->symbol = symbol;
    return oldest;
}

static void tap_keycode(Display *display, KeyCode code, int shift) {
    if (shift)
        fake_key(display, XK_Shift_L, True);
    XTestFakeKeyEvent(display, code, True, CurrentTime);
    XTestFakeKeyEvent(display, code, False, CurrentTime);
    if (shift)
        fake_key(display, XK_Shift_L, False);
}

/* Non-ASCII characters are always tapped, also for games: they are text, and
 * holding a borrowed keycode would pin its binding for the length of the
 * hold. */
static void type_code_point(Display *display, uint32_t code_point) {
    struct unicode_key *key;
    KeySym symbol;
    KeyCode code;
    int shift;

    /* C1 controls have no keysym and nothing to type. */
    if (code_point < 0xa0)
        return;
    /* Latin-1 keysyms equal their code points; everything else uses the
     * Unicode keysym range, as XStringToKeysym("U0439") does. */
    symbol = code_point <= 0xff ? (KeySym)code_point
                                : (KeySym)(UINT32_C(0x01000000) | code_point);
    scan_keyboard_map(display);
    if (find_original_key(symbol, &code, &shift)) {
        tap_keycode(display, code, shift);
        return;
    }
    key = borrow_key(display, symbol);
    if (key == NULL)
        return;
    tap_keycode(display, key->code, 0);
    /* Start the settle time once the server has delivered the key, not when
     * Xlib buffered it: until XSync returns it may not have left this
     * process. */
    XSync(display, False);
    key->tap_number = ++unicode_key_taps;
    key->tapped_at_ms = monotonic_millis();
}

/* Feed one byte of 0x80 and up, or any byte while a sequence is open. Return
 * 0 when the byte broke off an unfinished sequence and has to be read again on
 * its own; the broken sequence is dropped. Stray continuation bytes, overlong
 * forms, surrogates and anything past U+10FFFF are ignored. */
static int take_utf8_byte(Display *display, unsigned char byte) {
    uint32_t code_point;

    if (utf8_remaining == 0) {
        if (byte >= 0xc2 && byte <= 0xdf) {
            utf8_length = 2;
            utf8_code_point = byte & 0x1f;
        } else if (byte >= 0xe0 && byte <= 0xef) {
            utf8_length = 3;
            utf8_code_point = byte & 0x0f;
        } else if (byte >= 0xf0 && byte <= 0xf4) {
            utf8_length = 4;
            utf8_code_point = byte & 0x07;
        } else {
            return 1;
        }
        utf8_remaining = utf8_length - 1;
        return 1;
    }
    if ((byte & 0xc0) != 0x80) {
        utf8_remaining = 0;
        return 0;
    }
    utf8_code_point = (utf8_code_point << 6) | (byte & 0x3f);
    if (--utf8_remaining != 0)
        return 1;
    code_point = utf8_code_point;
    if ((utf8_length == 3 && code_point < 0x800) ||
        (utf8_length == 4 && (code_point < 0x10000 || code_point > 0x10ffff)) ||
        (code_point >= 0xd800 && code_point <= 0xdfff))
        return 1;
    type_code_point(display, code_point);
    return 1;
}

static void send_keys(Display *display, const unsigned char *keys,
                      size_t length) {
    size_t index = 0;

    while (index < length) {
        /* Bytes from 0x80 up only ever belong to UTF-8, and a sequence the
         * previous record left open claims what follows it. */
        if (keys[index] >= 0x80 || utf8_remaining != 0) {
            if (take_utf8_byte(display, keys[index]))
                ++index;
            continue;
        }
        if (keys[index] == 0x1b && index + 2 < length &&
            keys[index + 1] == '[') {
            KeySym symbol = NoSymbol;
            switch (keys[index + 2]) {
            case 'A': symbol = XK_Up; break;
            case 'B': symbol = XK_Down; break;
            case 'C': symbol = XK_Right; break;
            case 'D': symbol = XK_Left; break;
            case 'H': symbol = XK_Home; break;
            case 'F': symbol = XK_End; break;
            default: break;
            }
            if (symbol != NoSymbol) {
                tap_key(display, symbol, 0, 0);
                index += 3;
                continue;
            }
            if (keys[index + 2] == '3' && index + 3 < length &&
                keys[index + 3] == '~') {
                tap_key(display, XK_Delete, 0, 0);
                index += 4;
                continue;
            }
        }
        if (keys[index] == 0x1b)
            tap_key(display, XK_Escape, 0, 0);
        else
            type_ascii(display, keys[index]);
        ++index;
    }
}

static void focus_pointer_window(Display *display) {
    Window root = DefaultRootWindow(display);
    Window root_return;
    Window child_return;
    int root_x;
    int root_y;
    int window_x;
    int window_y;
    unsigned int mask;

    if (XQueryPointer(display, root, &root_return, &child_return, &root_x,
                      &root_y, &window_x, &window_y, &mask) &&
        child_return != None)
        XSetInputFocus(display, child_return, RevertToPointerRoot, CurrentTime);
}

static Window topmost_substantial_child(Display *display, Window parent) {
    Window root_return;
    Window parent_return;
    Window *children = NULL;
    unsigned int count = 0;
    unsigned int index;
    Window result = None;

    if (!XQueryTree(display, parent, &root_return, &parent_return, &children,
                    &count))
        return None;
    for (index = count; index > 0; --index) {
        XWindowAttributes attributes;
        Window candidate = children[index - 1];
        if (XGetWindowAttributes(display, candidate, &attributes) &&
            attributes.map_state == IsViewable &&
            attributes.class == InputOutput && attributes.width >= 32 &&
            attributes.height >= 32 &&
            attributes.width <= DisplayWidth(display, DefaultScreen(display)) * 2 &&
            attributes.height <= DisplayHeight(display, DefaultScreen(display)) * 2) {
            result = candidate;
            break;
        }
    }
    if (children != NULL)
        XFree(children);
    return result;
}

static Window topmost_input_window(Display *display, Window parent) {
    Window candidate = topmost_substantial_child(display, parent);
    Window descendant;

    if (candidate == None)
        return None;
    descendant = topmost_input_window(display, candidate);
    return descendant == None ? candidate : descendant;
}

/* The topmost viewable application window directly under the root. Popups,
 * menus and tooltips are override-redirect and never take the focus: GTK and
 * Qt send them keys through a grab of their own. */
static Window topmost_toplevel(Display *display) {
    Window root = DefaultRootWindow(display);
    Window root_return;
    Window parent_return;
    Window *children = NULL;
    unsigned int count = 0;
    unsigned int index;
    Window result = None;

    if (!XQueryTree(display, root, &root_return, &parent_return, &children,
                    &count))
        return None;
    for (index = count; index > 0; --index) {
        XWindowAttributes attributes;
        Window candidate = children[index - 1];
        if (XGetWindowAttributes(display, candidate, &attributes) &&
            attributes.map_state == IsViewable &&
            attributes.class == InputOutput &&
            !attributes.override_redirect && attributes.width >= 32 &&
            attributes.height >= 32) {
            result = candidate;
            break;
        }
    }
    if (children != NULL)
        XFree(children);
    return result;
}

static int takes_focus_itself(Display *display, Window window) {
    Atom take_focus = XInternAtom(display, "WM_TAKE_FOCUS", False);
    Atom *protocols = NULL;
    int count = 0;
    int index;
    int found = 0;

    if (!XGetWMProtocols(display, window, &protocols, &count))
        return 0;
    for (index = 0; index < count; ++index)
        if (protocols[index] == take_focus)
            found = 1;
    XFree(protocols);
    return found;
}

static int focus_is_within(Display *display, Window top) {
    Window focus;
    int revert;

    XGetInputFocus(display, &focus, &revert);
    while (focus != None && focus != PointerRoot) {
        Window root_return;
        Window parent;
        Window *children = NULL;
        unsigned int count = 0;

        if (focus == top)
            return 1;
        if (!XQueryTree(display, focus, &root_return, &parent, &children,
                        &count))
            return 0;
        if (children != NULL)
            XFree(children);
        if (parent == root_return)
            return 0;
        focus = parent;
    }
    return 0;
}

/* What a window manager does for a toplevel that takes WM_TAKE_FOCUS, as GTK
 * and Qt toplevels do: focus the toplevel and let it pass the focus on. GTK
 * moves it to a hidden 1x1 child of its own; given a window inside the
 * toplevel instead, as the descent below would pick, Firefox saw no focus and
 * dropped every key. */
static void focus_toplevel(Display *display, Window top) {
    XEvent event;

    XSetInputFocus(display, top, RevertToPointerRoot, CurrentTime);
    memset(&event, 0, sizeof(event));
    event.xclient.type = ClientMessage;
    event.xclient.window = top;
    event.xclient.message_type = XInternAtom(display, "WM_PROTOCOLS", False);
    event.xclient.format = 32;
    event.xclient.data.l[0] = (long)XInternAtom(display, "WM_TAKE_FOCUS", False);
    event.xclient.data.l[1] = CurrentTime;
    XSendEvent(display, top, False, NoEventMask, &event);
}

static void focus_top_window(Display *display) {
    Window root = DefaultRootWindow(display);
    Window target;

    if (!hold_game_keys) {
        Window top = topmost_toplevel(display);
        if (top != None && takes_focus_itself(display, top)) {
            /* A click already focused it, or it moved the focus inside
             * itself: leave that alone. */
            if (!focus_is_within(display, top))
                focus_toplevel(display, top);
            return;
        }
    }

    /* Xvfb has no window manager to assign keyboard focus. Wine nests its
     * application windows and dialogs below Explorer's virtual-desktop root
     * child. Tiny IME, device and decoration windows can sit above them; they
     * must not receive focus. Descend through substantial input/output
     * children until the real application control or modal dialog is reached.
     */
    /* SDL's game window is the direct root child. Descending into its
     * helper children sends synthetic keys away from the game event loop. */
    target = hold_game_keys ? topmost_substantial_child(display, root)
                            : topmost_input_window(display, root);
    if (target != None)
        XSetInputFocus(display, target, RevertToPointerRoot, CurrentTime);
}

/* Xvfb deliberately has no window manager. Most hosted applications request
 * the root dimensions themselves, but a stale Minecraft launch description
 * can make GLFW fall back to 854x480 and leave the rest of the captured root
 * visible as a white border. For applications explicitly hosted with
 * --fill, take over the one window-manager job they need and keep their
 * top-level window fitted to the complete private display. */
static void fill_top_window(Display *display) {
    Window root = DefaultRootWindow(display);
    Window target = topmost_substantial_child(display, root);
    XWindowAttributes attributes;
    int width = DisplayWidth(display, DefaultScreen(display));
    int height = DisplayHeight(display, DefaultScreen(display));

    if (target == None ||
        !XGetWindowAttributes(display, target, &attributes))
        return;
    if (attributes.x == 0 && attributes.y == 0 &&
        attributes.width == width && attributes.height == height)
        return;
    XMoveResizeWindow(display, target, 0, 0, (unsigned int)width,
                      (unsigned int)height);
    XRaiseWindow(display, target);
    XFlush(display);
}

static int process_event(Display *display, const struct wine_host_event *event,
                         const unsigned char *payload) {
    switch (event->kind) {
    case WINE_HOST_MOTION:
        XWarpPointer(display, None, DefaultRootWindow(display), 0, 0, 0, 0,
                     event->x, event->y);
        break;
    case WINE_HOST_BUTTON_DOWN:
        focus_pointer_window(display);
        XTestFakeButtonEvent(display, 1, True, CurrentTime);
        break;
    case WINE_HOST_BUTTON_UP:
        XTestFakeButtonEvent(display, 1, False, CurrentTime);
        break;
    case WINE_HOST_MIDDLE_DOWN:
        XTestFakeButtonEvent(display, 2, True, CurrentTime);
        break;
    case WINE_HOST_MIDDLE_UP:
        XTestFakeButtonEvent(display, 2, False, CurrentTime);
        break;
    case WINE_HOST_RIGHT_DOWN:
        XTestFakeButtonEvent(display, 3, True, CurrentTime);
        break;
    case WINE_HOST_RIGHT_UP:
        XTestFakeButtonEvent(display, 3, False, CurrentTime);
        break;
    case WINE_HOST_WHEEL_UP:
    case WINE_HOST_WHEEL_DOWN:
        XTestFakeButtonEvent(display, event->kind == WINE_HOST_WHEEL_UP ? 4 : 5,
                             True, CurrentTime);
        XTestFakeButtonEvent(display, event->kind == WINE_HOST_WHEEL_UP ? 4 : 5,
                             False, CurrentTime);
        break;
    case WINE_HOST_KEYS:
        focus_top_window(display);
        send_keys(display, payload, event->length);
        break;
    default:
        return 0;
    }
    XFlush(display);
    return 1;
}

/* The compositor cannot see when Xvfb touched its shared framebuffer: the
 * application draws straight into the mapping, so neither its size nor its
 * timestamps move. Left to guess, vinix-desktop rescales the whole surface
 * twenty times a second whether or not anything changed, and on an emulated
 * core that starves the very browser it is displaying.
 *
 * So report drawing as it happens. A counter file next to the framebuffer
 * carries the damage sequence; the desktop blits only when it advances. */
/* The counter is shared the same way the framebuffer is — through the file's
 * pages — so that publishing costs a store and reading it costs a load. The
 * desktop polls this twenty times a second while the machine is busy paging a
 * browser in; a read() there would queue behind that. */
static volatile uint32_t *map_damage_counter(const char *directory) {
    char path[PATH_MAX];
    void *mapping;
    int fd;

    if (snprintf(path, sizeof(path), "%s/damage", directory) >= (int)sizeof(path))
        return NULL;
    fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0600);
    if (fd < 0)
        return NULL;
    if (ftruncate(fd, (off_t)sizeof(uint32_t)) != 0) {
        close(fd);
        return NULL;
    }
    mapping = mmap(NULL, sizeof(uint32_t), PROT_READ | PROT_WRITE, MAP_SHARED,
                   fd, 0);
    close(fd);
    if (mapping == MAP_FAILED)
        return NULL;
    return mapping;
}

/* Xvfb has no compositing, so every window draws into the root's own pixmap
 * and damage on the root covers the whole session. Report only that the
 * screen changed: the desktop rescales the entire surface anyway. */
static Damage watch_root_damage(Display *display, int *event_base) {
    int error_base;
    int major;
    int minor;

    if (!XDamageQueryExtension(display, event_base, &error_base))
        return None;
    if (!XDamageQueryVersion(display, &major, &minor))
        return None;
    return XDamageCreate(display, DefaultRootWindow(display),
                         XDamageReportNonEmpty);
}

static void stop_child(pid_t pid) {
    int status;
    int attempt;

    if (pid <= 0 || waitpid(pid, &status, WNOHANG) == pid)
        return;
    kill(pid, SIGTERM);
    for (attempt = 0; attempt < 100; ++attempt) {
        if (waitpid(pid, &status, WNOHANG) == pid)
            return;
        sleep_10ms();
    }
    kill(pid, SIGKILL);
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR)
        ;
}

int main(int argc, char **argv) {
    struct sigaction action;
    unsigned char input[8192];
    size_t used = 0;
    const char *display_name;
    char chosen_display[16];
    const char *directory;
    const char *geometry;
    const char *command;
    Display *display;
    pid_t xvfb_pid;
    pid_t wine_pid = -1;
    int stdin_flags;
    int status;
    int xtest_event_base;
    int xtest_error_base;
    int xtest_major;
    int xtest_minor;
    int damage_event_base = 0;
    volatile uint32_t *damage_counter = NULL;
    uint32_t damage_sequence = 0;
    Damage damage;
    int fill_surface = 0;
    int game_input = 0;
    int obs_capture = 0;
    unsigned int fill_tick = 0;

    if (argc != 5 && argc != 6) {
        fprintf(stderr, "usage: %s DISPLAY FBDIR GEOMETRY COMMAND [--fill|--game-input|--obs]\n",
                argv[0]);
        return 2;
    }
    if (argc == 6) {
        if (strcmp(argv[5], "--fill") == 0) {
            fill_surface = 1;
        } else if (strcmp(argv[5], "--game-input") == 0) {
            game_input = 1;
        } else if (strcmp(argv[5], "--obs") == 0) {
            obs_capture = 1;
        } else {
            fprintf(stderr, "vinix-wine-host: unknown option: %s\n", argv[5]);
            return 2;
        }
    }
    display_name = argv[1];
    directory = argv[2];
    geometry = argv[3];
    command = argv[4];
    hold_game_keys = game_input;

    memset(&action, 0, sizeof(action));
    action.sa_handler = stop_running;
    sigemptyset(&action.sa_mask);
    sigaction(SIGHUP, &action, NULL);
    sigaction(SIGINT, &action, NULL);
    sigaction(SIGTERM, &action, NULL);

    if (mkdir(directory, 0700) != 0 && errno != EEXIST) {
        perror("vinix-wine-host: mkdir");
        return 1;
    }
    display_name = claim_display(display_name, chosen_display,
                                 sizeof(chosen_display));
    if (display_name == NULL) {
        fprintf(stderr, "vinix-wine-host: no free display near %s\n", argv[1]);
        rmdir(directory);
        return 1;
    }
    xvfb_pid = spawn_xvfb(display_name, directory, geometry, game_input,
                          obs_capture, strcmp(command, "/usr/bin/run-opengothic") == 0);
    if (xvfb_pid < 0) {
        perror("vinix-wine-host: fork Xvfb");
        rmdir(directory);
        return 1;
    }
    display = open_display(display_name, xvfb_pid);
    if (display == NULL) {
        fprintf(stderr, "vinix-wine-host: Xvfb did not become ready\n");
        stop_child(xvfb_pid);
        remove_surface_files(directory);
        rmdir(directory);
        return 1;
    }
    XSetErrorHandler(ignore_x_error);
    if (obs_capture && publish_obs_screen(directory) != 0) {
        perror("vinix-wine-host: publish OBS capture screen");
        XCloseDisplay(display);
        stop_child(xvfb_pid);
        remove_surface_files(directory);
        rmdir(directory);
        return 1;
    }
    if (!XTestQueryExtension(display, &xtest_event_base, &xtest_error_base,
                             &xtest_major, &xtest_minor)) {
        fprintf(stderr, "vinix-wine-host: XTEST extension is unavailable\n");
        XCloseDisplay(display);
        if (obs_capture)
            unpublish_obs_screen(directory);
        stop_child(xvfb_pid);
        remove_surface_files(directory);
        rmdir(directory);
        return 1;
    }

    // A Windows program that chooses a smaller initial size gets a neutral
    // Vinix-like surface around it, never the opaque black X root window.
    XSetWindowBackground(display, DefaultRootWindow(display), 0xf3f4f6);
    XClearWindow(display, DefaultRootWindow(display));
    XFlush(display);

    damage = watch_root_damage(display, &damage_event_base);
    if (damage != None) {
        damage_counter = map_damage_counter(directory);
        if (damage_counter == NULL) {
            XDamageDestroy(display, damage);
            damage = None;
        } else {
            /* The first frame is the one the desktop is waiting for. */
            *damage_counter = ++damage_sequence;
        }
    }

    wine_pid = spawn_wine(display_name, command);
    if (wine_pid < 0) {
        perror("vinix-wine-host: fork Wine");
        running = 0;
    }

    stdin_flags = fcntl(STDIN_FILENO, F_GETFL);
    if (stdin_flags >= 0)
        fcntl(STDIN_FILENO, F_SETFL, stdin_flags | O_NONBLOCK);

    while (running) {
        ssize_t count = read(STDIN_FILENO, input + used, sizeof(input) - used);
        if (count > 0)
            used += (size_t)count;
        else if (count == 0)
            running = 0;
        else if (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR)
            running = 0;

        while (used >= sizeof(struct wine_host_event)) {
            struct wine_host_event event;
            size_t record_size;
            memcpy(&event, input, sizeof(event));
            if (event.magic != WINE_HOST_EVENT_MAGIC ||
                event.length > WINE_HOST_MAX_KEYS ||
                (event.kind != WINE_HOST_KEYS && event.length != 0)) {
                running = 0;
                break;
            }
            record_size = sizeof(event) + event.length;
            if (used < record_size)
                break;
            process_event(display, &event, input + sizeof(event));
            memmove(input, input + record_size, used - record_size);
            used -= record_size;
        }
        if (used == sizeof(input))
            running = 0;

        /* Check at 10 Hz rather than on every bridge iteration. This catches
         * both the first GLFW mapping and any later client-requested reset,
         * while the no-op steady state is just one small XQueryTree. */
        if (fill_surface && fill_tick++ % 10 == 0)
            fill_top_window(display);

        if (damage != None) {
            int drawn = 0;
            /* XDamageReportNonEmpty stays quiet until the region is taken
             * back, so one subtract per pass is enough however much was
             * drawn in it. */
            while (XPending(display) > 0) {
                XEvent event;
                XNextEvent(display, &event);
                if (event.type == damage_event_base + XDamageNotify)
                    drawn = 1;
            }
            if (drawn) {
                XDamageSubtract(display, damage, None, None);
                XFlush(display);
                *damage_counter = ++damage_sequence;
            }
        }

        if (wine_pid > 0 && waitpid(wine_pid, &status, WNOHANG) == wine_pid) {
            wine_pid = -1;
            running = 0;
        }
        if (hold_game_keys)
            release_expired_game_keys(display);
        sleep_10ms();
    }

    stop_child(wine_pid);
    if (damage_counter != NULL)
        munmap((void *)damage_counter, sizeof(uint32_t));
    XCloseDisplay(display);
    if (obs_capture)
        unpublish_obs_screen(directory);
    stop_child(xvfb_pid);
    /* Xvfb removes these when it is asked to stop, but not when it has to be
     * killed. Leave nothing behind for the next server on this number. */
    remove_display_files(display_number(display_name));
    remove_surface_files(directory);
    rmdir(directory);
    return 0;
}
