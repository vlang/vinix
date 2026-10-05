// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
// SPDX-License-Identifier: GPL-2.0-or-later
/* Native headers, macros and callback signatures; bridge policy is V. */
#include <X11/Xlib.h>
#include <X11/extensions/XTest.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <termios.h>
#include <time.h>
#include "xinput_abi.h"
_Static_assert(sizeof(sig_atomic_t) == sizeof(int32_t), "V signal state width");
_Static_assert(__atomic_always_lock_free(sizeof(int32_t), 0), "signal handler atomics are lock free");
static struct termios saved_termios;
static int restore_termios;
static void stop_running(int n) { vxi_stop(n); }
static int report_x_error(Display *d, XErrorEvent *e) {
    return vxi_report_error(d, e->error_code, e->request_code, e->minor_code);
}
void vxi_handlers(void) {
    struct sigaction action = {0};
    action.sa_handler = stop_running;
    sigemptyset(&action.sa_mask);
    sigaction(SIGHUP, &action, NULL);
    sigaction(SIGINT, &action, NULL);
    sigaction(SIGTERM, &action, NULL);
}
void *vxi_open_display(void) { return XOpenDisplay(NULL); }
void vxi_close_display(void *d) { XCloseDisplay(d); }
int vxi_xtest_available(void *d) {
    int event, error, major, minor;
    XSetErrorHandler(report_x_error);
    return XTestQueryExtension(d, &event, &error, &major, &minor);
}
int vxi_open_device(const char *path) { return open(path, O_RDONLY | O_NONBLOCK); }
int vxi_raw_keyboard(int fd) {
    struct termios raw;
    if (fd < 0) return 0;
    if (tcgetattr(fd, &saved_termios) == 0) {
        raw = saved_termios;
        raw.c_iflag &= (tcflag_t)~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
        raw.c_oflag &= (tcflag_t)~OPOST;
        raw.c_cflag |= CS8;
        raw.c_lflag &= (tcflag_t)~(ECHO | ICANON | IEXTEN | ISIG);
        raw.c_cc[VMIN] = 0;
        raw.c_cc[VTIME] = 0;
        if (tcsetattr(fd, TCSANOW, &raw) == 0) restore_termios = 1;
    }
    return restore_termios;
}
void vxi_restore_keyboard(int fd) {
    if (restore_termios) (void)tcsetattr(fd, TCSANOW, &saved_termios);
}
void vxi_delay(void) { struct timespec delay = {0, 10000000}; nanosleep(&delay, NULL); }
const char *vxi_error(void) { return strerror(errno); }
void vxi_error_text(void *d, int code, char *out, int cap) { XGetErrorText(d, code, out, cap); }
void vxi_key(void *d, uint64_t key, int down) {
    KeyCode code = XKeysymToKeycode(d, key);
    if (code) XTestFakeKeyEvent(d, code, down, CurrentTime);
}
void vxi_button(void *d, unsigned int b, int down) { XTestFakeButtonEvent(d, b, down, CurrentTime); }
uint64_t vxi_pointer_child(void *d) {
    Window root, child; int rx, ry, wx, wy; unsigned int mask;
    if (XQueryPointer(d, DefaultRootWindow((Display *)d), &root, &child, &rx, &ry, &wx, &wy, &mask)) return child;
    return None;
}
void vxi_focus(void *d, uint64_t child) { XSetInputFocus(d, child, RevertToPointerRoot, CurrentTime); }
void vxi_dimensions(void *d, int *w, int *h) { int screen = DefaultScreen((Display *)d); *w = DisplayWidth((Display *)d, screen); *h = DisplayHeight((Display *)d, screen); }
void vxi_warp(void *d, int x, int y) { XWarpPointer(d, None, DefaultRootWindow((Display *)d), 0, 0, 0, 0, x, y); }
void vxi_flush(void *d) { XFlush(d); }
int main(void) { return vxi_main(); }
