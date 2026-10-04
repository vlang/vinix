// SPDX-License-Identifier: GPL-2.0-or-later
// Text selections belong to this private X display until the app copies again.
#include <X11/Xatom.h>

static Window clipboard_window;
static Atom clipboard_selection, clipboard_utf8, clipboard_targets, clipboard_text;
static unsigned char clipboard_data[WINE_HOST_MAX_KEYS];
static size_t clipboard_length;

static void paste_clipboard(Display *display, const unsigned char *text, size_t length) {
    if (clipboard_window == None) {
        clipboard_window = XCreateSimpleWindow(display, DefaultRootWindow(display),
                                               0, 0, 1, 1, 0, 0, 0);
        clipboard_selection = XInternAtom(display, "CLIPBOARD", False);
        clipboard_utf8 = XInternAtom(display, "UTF8_STRING", False);
        clipboard_targets = XInternAtom(display, "TARGETS", False);
        clipboard_text = XInternAtom(display, "TEXT", False);
    }
    memcpy(clipboard_data, text, length);
    clipboard_length = length;
    XSetSelectionOwner(display, clipboard_selection, clipboard_window, CurrentTime);
    /* This is a real paste gesture: a newline stays inside an entry or
     * document rather than becoming a synthetic Enter key. */
    KeyCode control = XKeysymToKeycode(display, XK_Control_L);
    KeyCode v = XKeysymToKeycode(display, XK_v);
    XTestFakeKeyEvent(display, control, True, CurrentTime);
    XTestFakeKeyEvent(display, v, True, CurrentTime);
    XTestFakeKeyEvent(display, v, False, CurrentTime);
    XTestFakeKeyEvent(display, control, False, CurrentTime);
}

static void clipboard_selection_request(Display *display, XSelectionRequestEvent *request) {
    XEvent reply;
    Atom property = request->property == None ? request->target : request->property;
    memset(&reply, 0, sizeof(reply));
    reply.xselection.type = SelectionNotify;
    reply.xselection.display = display;
    reply.xselection.requestor = request->requestor;
    reply.xselection.selection = request->selection;
    reply.xselection.target = request->target;
    reply.xselection.time = request->time;
    reply.xselection.property = None;
    if (request->selection == clipboard_selection && request->owner == clipboard_window) {
        if (request->target == clipboard_targets) {
            Atom targets[] = {clipboard_targets, clipboard_utf8, clipboard_text, XA_STRING};
            XChangeProperty(display, request->requestor, property, XA_ATOM, 32,
                            PropModeReplace, (unsigned char *)targets, 4);
            reply.xselection.property = property;
        } else if (request->target == clipboard_utf8 || request->target == clipboard_text) {
            XChangeProperty(display, request->requestor, property, clipboard_utf8, 8,
                            PropModeReplace, clipboard_data, (int)clipboard_length);
            reply.xselection.property = property;
        } else if (request->target == XA_STRING) {
            unsigned char latin1[WINE_HOST_MAX_KEYS];
            size_t used = 0;
            for (size_t at = 0; at < clipboard_length; ++at) {
                unsigned char ch = clipboard_data[at];
                if (ch < 0x80) {
                    latin1[used++] = ch;
                } else if ((ch == 0xc2 || ch == 0xc3) && at + 1 < clipboard_length) {
                    latin1[used++] = (unsigned char)((ch & 3) << 6) |
                                     (clipboard_data[++at] & 0x3f);
                } else if ((ch & 0xc0) != 0x80) {
                    latin1[used++] = '?';
                }
            }
            XChangeProperty(display, request->requestor, property, XA_STRING, 8,
                            PropModeReplace, latin1, (int)used);
            reply.xselection.property = property;
        }
    }
    XSendEvent(display, request->requestor, False, 0, &reply);
    XFlush(display);
}
