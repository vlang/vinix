// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Feed Vinix's native pointer and console keyboard into an Xorg server. The
// server deliberately has no Linux evdev/udev input stack; using XTest here
// keeps that policy while still giving large X11 clients such as Firefox a
// normal core pointer and keyboard.

#include <X11/Xlib.h>
#include <X11/keysym.h>
#include <X11/extensions/XTest.h>

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

struct vinix_pointer_packet {
    int32_t x;
    int32_t y;
    int32_t max_x;
    int32_t max_y;
    uint32_t buttons;
    uint32_t pressed;
    uint32_t released;
    int32_t scroll;
};

static volatile sig_atomic_t running = 1;
static struct termios saved_termios;
static int restore_termios;
static int keyboard_fd = -1;

static void stop_running(int signal_number) {
    (void)signal_number;
    running = 0;
}

static int report_x_error(Display *display, XErrorEvent *event) {
    char message[128];

    XGetErrorText(display, event->error_code, message, sizeof(message));
    fprintf(stderr, "vinix-xinput: X11 error: %s (request %u.%u)\n",
            message, event->request_code, event->minor_code);
    return 0;
}

static int make_keyboard_raw(void) {
    struct termios raw;

    // POSIX shells attach /dev/null to an asynchronous command's stdin when
    // job control is disabled. Open the shared Vinix console explicitly.
    keyboard_fd = open("/dev/console", O_RDONLY | O_NONBLOCK);
    if (keyboard_fd < 0)
        return 0;
    if (tcgetattr(keyboard_fd, &saved_termios) == 0) {
        raw = saved_termios;
        raw.c_iflag &= (tcflag_t)~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
        raw.c_oflag &= (tcflag_t)~OPOST;
        raw.c_cflag |= CS8;
        raw.c_lflag &= (tcflag_t)~(ECHO | ICANON | IEXTEN | ISIG);
        raw.c_cc[VMIN] = 0;
        raw.c_cc[VTIME] = 0;
        if (tcsetattr(keyboard_fd, TCSANOW, &raw) == 0)
            restore_termios = 1;
    }
    return restore_termios;
}

static void restore_keyboard(void) {
    if (restore_termios)
        (void)tcsetattr(keyboard_fd, TCSANOW, &saved_termios);
    if (keyboard_fd >= 0)
        (void)close(keyboard_fd);
    keyboard_fd = -1;
}

static void fake_key(Display *display, KeySym symbol, Bool pressed) {
    KeyCode code = XKeysymToKeycode(display, symbol);
    if (code != 0)
        XTestFakeKeyEvent(display, code, pressed, CurrentTime);
}

static void tap_key(Display *display, KeySym symbol, int shift, int control) {
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

// Xorg's default keymap is US. Printable ASCII keysyms use their byte value,
// but shifted punctuation has to be sent using the physical base key while
// Shift is held.
static void type_ascii(Display *display, unsigned char byte) {
    static const char shifted[] = "!@#$%^&*()_+{}|:\"~<>?";
    static const char bases[] = "1234567890-=[]\\;'\x60,./";
    const char *position;

    if (byte >= 1 && byte <= 26) {
        tap_key(display, (KeySym)('a' + byte - 1), 0, 1);
        return;
    }
    switch (byte) {
    case '\n':
    case '\r':
        tap_key(display, XK_Return, 0, 0);
        return;
    case '\t':
        tap_key(display, XK_Tab, 0, 0);
        return;
    case '\b':
    case 0x7f:
        tap_key(display, XK_BackSpace, 0, 0);
        return;
    default:
        break;
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

static unsigned char escape_bytes[16];
static size_t escape_length;
static unsigned int escape_idle_polls;

static void clear_escape(void) {
    escape_length = 0;
    escape_idle_polls = 0;
}

static void flush_escape_as_keys(Display *display) {
    size_t index;

    tap_key(display, XK_Escape, 0, 0);
    for (index = 1; index < escape_length; index++)
        type_ascii(display, escape_bytes[index]);
    clear_escape();
}

// Return 1 when a complete escape sequence was consumed, 0 when more bytes
// are needed, and -1 when the buffered bytes are not a sequence we know.
static int finish_escape(Display *display) {
    KeySym symbol = NoSymbol;

    if (escape_length < 2)
        return 0;
    if (escape_bytes[1] != '[' && escape_bytes[1] != 'O')
        return -1;
    if (escape_length < 3)
        return 0;

    if (escape_bytes[1] == 'O') {
        switch (escape_bytes[2]) {
        case 'A': symbol = XK_Up; break;
        case 'B': symbol = XK_Down; break;
        case 'C': symbol = XK_Right; break;
        case 'D': symbol = XK_Left; break;
        case 'H': symbol = XK_Home; break;
        case 'F': symbol = XK_End; break;
        case 'P': symbol = XK_F1; break;
        case 'Q': symbol = XK_F2; break;
        case 'R': symbol = XK_F3; break;
        case 'S': symbol = XK_F4; break;
        default: return -1;
        }
        tap_key(display, symbol, 0, 0);
        clear_escape();
        return 1;
    }

    switch (escape_bytes[2]) {
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
        clear_escape();
        return 1;
    }

    if (escape_bytes[2] < '0' || escape_bytes[2] > '9')
        return -1;
    if (escape_bytes[escape_length - 1] != '~')
        return escape_length < sizeof(escape_bytes) ? 0 : -1;

    if (escape_length == 4) {
        switch (escape_bytes[2]) {
        case '1': symbol = XK_Home; break;
        case '2': symbol = XK_Insert; break;
        case '3': symbol = XK_Delete; break;
        case '4': symbol = XK_End; break;
        case '5': symbol = XK_Page_Up; break;
        case '6': symbol = XK_Page_Down; break;
        case '7': symbol = XK_Home; break;
        case '8': symbol = XK_End; break;
        default: break;
        }
    }
    if (symbol == NoSymbol)
        return -1;
    tap_key(display, symbol, 0, 0);
    clear_escape();
    return 1;
}

static void keyboard_byte(Display *display, unsigned char byte) {
    int result;

    if (escape_length == 0) {
        if (byte == 0x1b) {
            escape_bytes[0] = byte;
            escape_length = 1;
            escape_idle_polls = 0;
        } else {
            type_ascii(display, byte);
        }
        return;
    }

    if (escape_length == sizeof(escape_bytes)) {
        flush_escape_as_keys(display);
        keyboard_byte(display, byte);
        return;
    }
    escape_bytes[escape_length++] = byte;
    escape_idle_polls = 0;
    result = finish_escape(display);
    if (result < 0)
        flush_escape_as_keys(display);
}

static int pump_keyboard(Display *display) {
    unsigned char bytes[64];
    ssize_t count;
    size_t index;
    int sent = 0;

    for (;;) {
        count = read(keyboard_fd, bytes, sizeof(bytes));
        if (count <= 0)
            break;
        sent = 1;
        for (index = 0; index < (size_t)count; index++)
            keyboard_byte(display, bytes[index]);
        if ((size_t)count < sizeof(bytes))
            break;
    }

    // A lone Escape is a valid key. Give multi-byte terminal sequences two
    // polling intervals to arrive before treating their prefix literally.
    if (!sent && escape_length != 0 && ++escape_idle_polls >= 2) {
        flush_escape_as_keys(display);
        sent = 1;
    }
    return sent;
}

static void fake_button(Display *display, unsigned int button, int pressed) {
    if (button == 1 && pressed) {
        Window root = DefaultRootWindow(display);
        Window root_return;
        Window child_return;
        int root_x;
        int root_y;
        int window_x;
        int window_y;
        unsigned int mask;

        // There is intentionally no X window manager around Firefox. Give
        // the clicked top-level client keyboard focus, which is the one small
        // piece of normal WM policy the browser still relies on.
        if (XQueryPointer(display, root, &root_return, &child_return, &root_x,
                          &root_y, &window_x, &window_y, &mask) &&
            child_return != None)
            XSetInputFocus(display, child_return, RevertToPointerRoot,
                           CurrentTime);
    }
    XTestFakeButtonEvent(display, button, pressed ? True : False, CurrentTime);
}

static int pump_pointer(Display *display, int pointer_fd, uint32_t *sent_buttons,
                        int *last_x, int *last_y) {
    static const unsigned int x_buttons[] = { 1, 3, 2 };
    struct vinix_pointer_packet packet;
    ssize_t count;
    int screen;
    int width;
    int height;
    int x;
    int y;
    int sent = 0;
    unsigned int index;

    count = read(pointer_fd, &packet, sizeof(packet));
    if (count != (ssize_t)sizeof(packet) || packet.max_x <= 0 || packet.max_y <= 0)
        return 0;

    screen = DefaultScreen(display);
    width = DisplayWidth(display, screen);
    height = DisplayHeight(display, screen);
    x = (int)((int64_t)packet.x * (width - 1) / packet.max_x);
    y = (int)((int64_t)packet.y * (height - 1) / packet.max_y);
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x >= width) x = width - 1;
    if (y >= height) y = height - 1;
    if (x != *last_x || y != *last_y) {
        // Vinix reports absolute display coordinates. Warp the root pointer
        // directly instead of routing them through XTEST's synthetic motion
        // device; the warp still emits the MotionNotify clients expect.
        XWarpPointer(display, None, RootWindow(display, screen),
                     0, 0, 0, 0, x, y);
        *last_x = x;
        *last_y = y;
        sent = 1;
    }

    for (index = 0; index < 3; index++) {
        uint32_t bit = (uint32_t)1 << index;
        int final_pressed = (packet.buttons & bit) != 0;
        int was_pressed = (*sent_buttons & bit) != 0;
        int saw_press = (packet.pressed & bit) != 0;
        int saw_release = (packet.released & bit) != 0;

        if (saw_press && saw_release) {
            if (final_pressed) {
                if (was_pressed)
                    fake_button(display, x_buttons[index], 0);
                fake_button(display, x_buttons[index], 1);
            } else {
                if (!was_pressed)
                    fake_button(display, x_buttons[index], 1);
                fake_button(display, x_buttons[index], 0);
            }
            sent = 1;
        } else if (final_pressed != was_pressed) {
            fake_button(display, x_buttons[index], final_pressed);
            sent = 1;
        }

        if (final_pressed)
            *sent_buttons |= bit;
        else
            *sent_buttons &= ~bit;
    }

    if (packet.scroll != 0) {
        unsigned int wheel_button = packet.scroll > 0 ? 4 : 5;
        int steps = packet.scroll > 0 ? packet.scroll : -packet.scroll;
        if (steps > 32)
            steps = 32;
        while (steps-- > 0) {
            fake_button(display, wheel_button, 1);
            fake_button(display, wheel_button, 0);
        }
        sent = 1;
    }
    return sent;
}

static Display *open_display(void) {
    struct timespec delay = { 0, 10000000 };
    Display *display;
    int attempts;

    for (attempts = 0; attempts < 200 && running; attempts++) {
        display = XOpenDisplay(NULL);
        if (display != NULL)
            return display;
        nanosleep(&delay, NULL);
    }
    return NULL;
}

int main(void) {
    struct sigaction action;
    struct timespec delay = { 0, 10000000 };
    Display *display;
    int pointer_fd;
    int event_base;
    int error_base;
    int major;
    int minor;
    int keyboard_available;
    uint32_t sent_buttons = 0;
    int last_x = -1;
    int last_y = -1;

    memset(&action, 0, sizeof(action));
    action.sa_handler = stop_running;
    sigemptyset(&action.sa_mask);
    sigaction(SIGHUP, &action, NULL);
    sigaction(SIGINT, &action, NULL);
    sigaction(SIGTERM, &action, NULL);

    display = open_display();
    if (display == NULL) {
        fprintf(stderr, "vinix-xinput: cannot open X display\n");
        return 1;
    }
    XSetErrorHandler(report_x_error);
    if (!XTestQueryExtension(display, &event_base, &error_base, &major, &minor)) {
        fprintf(stderr, "vinix-xinput: XTEST extension is unavailable\n");
        XCloseDisplay(display);
        return 1;
    }

    pointer_fd = open("/dev/pointer", O_RDONLY | O_NONBLOCK);
    if (pointer_fd < 0)
        fprintf(stderr, "vinix-xinput: /dev/pointer is unavailable: %s\n", strerror(errno));
    keyboard_available = make_keyboard_raw();
    if (!keyboard_available)
        fprintf(stderr, "vinix-xinput: console keyboard is unavailable\n");
    fprintf(stderr, "vinix-xinput: pointer and keyboard bridge ready\n");

    while (running) {
        int sent = keyboard_available ? pump_keyboard(display) : 0;
        if (pointer_fd >= 0)
            sent |= pump_pointer(display, pointer_fd, &sent_buttons, &last_x, &last_y);
        if (sent)
            // Do not wait synchronously for Xorg here. Keyboard processing can
            // involve XKB and a large client such as Firefox; blocking this
            // bridge on the round trip would also stop pointer delivery.
            XFlush(display);
        nanosleep(&delay, NULL);
    }

    restore_keyboard();
    if (pointer_fd >= 0)
        close(pointer_fd);
    XCloseDisplay(display);
    fprintf(stderr, "vinix-xinput: stopped\n");
    return 0;
}
