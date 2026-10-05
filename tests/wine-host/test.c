/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Independent protocol/Xlib fixture linked to the production V bridge. */
#include "wine-host-v-abi.h"
#include <assert.h>
#include <stdbool.h>
struct event_record { uint32_t magic, kind; int32_t x, y; uint32_t length; };
#ifdef VINIX_WINE_HOST_REFERENCE
#define main reference_bridge_main
#include VINIX_WINE_HOST_REFERENCE
#undef main
static void winehost__send_keys(Display *d, unsigned char *p, size_t n) { send_keys(d,p,n); }
static void winehost__paste_clipboard(Display *d, unsigned char *p, size_t n) { paste_clipboard(d,p,n); }
static void winehost__clipboard_selection_request(Display *d, XSelectionRequestEvent *r) { clipboard_selection_request(d,r); }
static bool winehost__process_event(Display *d, struct event_record *r, unsigned char *p) { return process_event(d,(const struct wine_host_event *)r,p); }
static int32_t winehost__display_number(char *s) { return display_number(s); }
#define winehost__utf8_remaining utf8_remaining
#else
void winehost__send_keys(Display *, unsigned char *, size_t);
void winehost__paste_clipboard(Display *, unsigned char *, size_t);
void winehost__clipboard_selection_request(Display *, XSelectionRequestEvent *);
bool winehost__process_event(Display *, struct event_record *, unsigned char *);
int32_t winehost__display_number(char *);
extern int32_t winehost__utf8_remaining;
#endif
struct key_event { unsigned int code; int down; };
static struct key_event keys[4096];
static unsigned int key_count, mapping_count, sync_count;
static KeySym remapped[256];
static unsigned char property_bytes[65536];
static size_t property_size;
static Atom property_type;
static int property_format;
static XEvent sent_event;
static int warp_x, warp_y;
int XGetInputFocus(Display *d, Window *window, int *revert) { (void)d; *window = None; *revert = RevertToNone; return 1; }
int XQueryTree(Display *d, Window window, Window *root, Window *parent, Window **children, unsigned int *count) { (void)d;(void)window; *root = 1; *parent = None; *children = NULL; *count = 0; return 1; }
int XGetWindowAttributes(Display *d, Window window, XWindowAttributes *attributes) { (void)d;(void)window;(void)attributes; return 0; }
int XGetWMProtocols(Display *d, Window window, Atom **protocols, int *count) { (void)d;(void)window; *protocols = NULL; *count = 0; return 0; }
int XQueryPointer(Display *d, Window window, Window *root, Window *child, int *rx, int *ry, int *wx, int *wy, unsigned int *mask) { (void)d;(void)window; *root = 1; *child = None; *rx = *ry = *wx = *wy = 0; *mask = 0; return 1; }
int XSetInputFocus(Display *d, Window window, int revert, Time time) { (void)d;(void)window;(void)revert;(void)time; return 1; }
int XTestFakeButtonEvent(Display *d, unsigned int button, Bool down, unsigned long delay) { (void)d;(void)button;(void)down;(void)delay; return 1; }
KeyCode XKeysymToKeycode(Display *d, KeySym symbol) { (void)d; return (KeyCode)(symbol == XK_Control_L ? 10 : symbol == XK_Shift_L ? 11 : symbol & 255); }
int XTestFakeKeyEvent(Display *d, unsigned int code, Bool down, unsigned long time) { (void)d;(void)time; assert(key_count < 4096); keys[key_count++] = (struct key_event){code, down}; return 1; }
int XFlush(Display *d) { (void)d; return 0; }
int XSync(Display *d, Bool discard) { (void)d;(void)discard; sync_count++; return 0; }
int XDisplayKeycodes(Display *d, int *min, int *max) { (void)d; *min = 100; *max = 103; return 1; }
#if NeedWidePrototypes
typedef unsigned int fixture_keycode;
#else
typedef KeyCode fixture_keycode;
#endif
KeySym *XGetKeyboardMapping(Display *d, fixture_keycode min, int count, int *per) { (void)d;(void)min; *per = 2; return calloc((size_t)count * 2, sizeof(KeySym)); }
XModifierKeymap *XGetModifierMapping(Display *d) { (void)d; return NULL; }
int XFreeModifiermap(XModifierKeymap *p) { free(p); return 0; }
int XFree(void *p) { free(p); return 0; }
int XChangeKeyboardMapping(Display *d, int code, int per, KeySym *columns, int count) { (void)d; assert(per == 2 && count == 1 && columns[0] == columns[1]); remapped[code] = columns[0]; mapping_count++; return 1; }
Window XCreateSimpleWindow(Display *d, Window root, int x, int y, unsigned width, unsigned height, unsigned border, unsigned long bp, unsigned long bg) { (void)d;(void)root;(void)x;(void)y;(void)width;(void)height;(void)border;(void)bp;(void)bg; return 42; }
Atom XInternAtom(Display *d, const char *name, Bool only) { (void)d;(void)only; return !strcmp(name,"CLIPBOARD") ? 50 : !strcmp(name,"UTF8_STRING") ? 51 : !strcmp(name,"TARGETS") ? 52 : 53; }
int XSetSelectionOwner(Display *d, Atom selection, Window window, Time time) { (void)d;(void)time; assert(selection == 50 && window == 42); return 1; }
int XChangeProperty(Display *d, Window window, Atom property, Atom type, int format, int mode, const unsigned char *bytes, int count) { (void)d;(void)window;(void)property; assert(mode == PropModeReplace && count >= 0); property_type = type; property_format = format; property_size = (size_t)count * (format == 32 ? sizeof(Atom) : 1); assert(property_size <= sizeof(property_bytes)); memcpy(property_bytes, bytes, property_size); return 1; }
int XSendEvent(Display *d, Window window, Bool prop, long mask, XEvent *event) { (void)d;(void)window;(void)prop;(void)mask; sent_event = *event; return 1; }
int XWarpPointer(Display *d, Window src, Window dest, int x, int y, unsigned width, unsigned height, int dx, int dy) { (void)d;(void)src;(void)dest;(void)x;(void)y;(void)width;(void)height; warp_x = dx; warp_y = dy; return 1; }
static void reset_keys(void) { key_count = 0; }
static void ascii_and_escape(Display *display) {
    static unsigned char text[] = {'\n','\t','\b',1,'A','!','x',0x1b,'[','A',0x1b,'[','3','~'};
    winehost__send_keys(display, text, sizeof(text));
    assert(key_count == 24);
    assert(keys[0].code == (XK_Return & 255) && keys[2].code == (XK_Tab & 255) && keys[4].code == (XK_BackSpace & 255));
    assert(keys[6].code == 10 && keys[7].code == 'a' && keys[10].code == 11 && keys[11].code == 'a');
    assert(keys[14].code == 11 && keys[15].code == '1');
    assert(keys[20].code == (XK_Up & 255) && keys[22].code == (XK_Delete & 255));
}
static void unicode(Display *display) {
    reset_keys();
    unsigned char first[] = {0xe2,0x82}, second[] = {0xac,0xe2,0x82,0xac};
    winehost__send_keys(display, first, sizeof(first)); assert(key_count == 0 && winehost__utf8_remaining == 1);
    winehost__send_keys(display, second, sizeof(second));
    assert(key_count == 4 && mapping_count == 1 && sync_count == 2 && remapped[keys[0].code] == 0x010020ac);
    assert(keys[0].code == keys[2].code);
    reset_keys(); unsigned char invalid[] = {0xe2,'x',0xc0,0xaf,0xed,0xa0,0x80,0xf4,0x90,0x80,0x80};
    winehost__send_keys(display, invalid, sizeof(invalid)); assert(key_count == 2 && keys[0].code == 'x' && winehost__utf8_remaining == 0);
}
static void selection(Display *display) {
    reset_keys();
    unsigned char text[] = {'a','\n',0xc3,0xa9,0xe2,0x82,0xac};
    winehost__paste_clipboard(display, text, sizeof(text)); assert(key_count == 4 && keys[0].code == 10 && keys[1].code == 'v');
    XSelectionRequestEvent request = {0}; request.owner = 42; request.requestor = 70; request.selection = 50; request.target = 51; request.property = 80; request.time = 123;
    winehost__clipboard_selection_request(display, &request);
    assert(property_type == 51 && property_format == 8 && property_size == sizeof(text) && !memcmp(property_bytes,text,sizeof(text)));
    assert(sent_event.xselection.type == SelectionNotify && sent_event.xselection.property == 80 && sent_event.xselection.time == 123);
    request.target = XA_STRING; request.property = None;
    winehost__clipboard_selection_request(display, &request);
    static unsigned char latin[] = {'a','\n',0xe9,'?'};
    assert(property_type == XA_STRING && property_size == sizeof(latin) && !memcmp(property_bytes,latin,sizeof(latin)) && sent_event.xselection.property == XA_STRING);
    request.target = 52; winehost__clipboard_selection_request(display, &request); assert(property_format == 32 && property_size == 4 * sizeof(Atom));
    request.owner = 99; winehost__clipboard_selection_request(display, &request); assert(sent_event.xselection.property == None);
}
int main(void) {
    _XPrivDisplay storage = calloc(1,sizeof(*storage)); Screen screen = {0}; screen.root = 1; storage->screens = &screen; storage->default_screen = 0; Display *display = (Display *)storage;
    assert(winehost__display_number(":99") == 99 && winehost__display_number("::65535") == 65535 && winehost__display_number(":65536") == -1 && winehost__display_number(":1x") == -1 && winehost__display_number(":") == -1);
    ascii_and_escape(display); unicode(display); selection(display);
    struct event_record motion = {0x56574831,1,120,90,0}; assert(winehost__process_event(display,&motion,NULL) && warp_x == 120 && warp_y == 90);
    motion.kind = 99; assert(!winehost__process_event(display,&motion,NULL));
    free(storage); puts("Wine host: PASS (control/ASCII/escape input, split/invalid UTF-8, borrowed key reuse, UTF-8/Latin-1/target selections and pointer protocol)"); return 0;
}
