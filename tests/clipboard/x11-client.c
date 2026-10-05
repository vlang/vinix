// SPDX-License-Identifier: GPL-2.0-or-later
// An X11 text client that requests CLIPBOARD on the real Ctrl+V key gesture.
#include <X11/Xlib.h>
#include <X11/keysym.h>
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    Display *display = XOpenDisplay(NULL);
    if (!display) return 1;
    Window window = XCreateSimpleWindow(display, DefaultRootWindow(display),
                                         0, 0, 640, 480, 0, 0, 0xffffff);
    XStoreName(display, window, "Clipboard integration test");
    XSelectInput(display, window, KeyPressMask);
    XMapWindow(display, window);
    XSetInputFocus(display, window, RevertToParent, CurrentTime);
    XFlush(display);
    Atom clipboard = XInternAtom(display, "CLIPBOARD", False);
    Atom utf8 = XInternAtom(display, "UTF8_STRING", False);
    Atom property = XInternAtom(display, "VINIX_TEST_PASTE", False);
    for (;;) {
        XEvent event;
        XNextEvent(display, &event);
        if (event.type == KeyPress && (event.xkey.state & ControlMask) &&
            XLookupKeysym(&event.xkey, 0) == XK_v) {
            XConvertSelection(display, clipboard, utf8, property, window, CurrentTime);
            XFlush(display);
        }
        if (event.type == SelectionNotify && event.xselection.property == property) {
            Atom type;
            int format;
            unsigned long length, remaining;
            unsigned char *text = NULL;
            if (XGetWindowProperty(display, window, property, 0, 65536, True,
                                   utf8, &type, &format, &length, &remaining, &text) != Success)
                return 2;
            if (type != utf8 || format != 8 || remaining != 0) return 3;
            FILE *output = fopen("/tmp/x11-paste", "wb");
            if (!output) return 4;
            fwrite(text, 1, length, output);
            fclose(output);
            XFree(text);
        }
    }
}
