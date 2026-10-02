/* Observe a real X11 APK window and send ordinary keyboard events to it. */
#include <X11/Xlib.h>
#include <X11/XKBlib.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>
#include <X11/extensions/XTest.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <linux/kd.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t running = 1;
static void stop(int sig) { (void)sig; running = 0; }
static void pause_ms(long ms) {
    struct timespec delay = {ms / 1000, ms % 1000 * 1000000};
    while (nanosleep(&delay, &delay) && errno == EINTR && running) {}
}
static int ignore_error(Display *display, XErrorEvent *event) {
    (void)display; (void)event; return 0;
}

static char *window_name(Display *display, Window window) {
    Atom property = XInternAtom(display, "_NET_WM_NAME", True);
    Atom utf8 = XInternAtom(display, "UTF8_STRING", True);
    if (property != None && utf8 != None) {
        Atom actual_type;
        int format;
        unsigned long length, remaining;
        unsigned char *value = NULL;
        if (XGetWindowProperty(display, window, property, 0, 1024, False, utf8,
                               &actual_type, &format, &length, &remaining, &value) == Success &&
            actual_type == utf8 && format == 8 && length && value) {
            return (char *)value;
        }
        if (value) XFree(value);
    }
    char *name = NULL;
    XFetchName(display, window, &name);
    return name;
}

static Window find_window(Display *display, Window parent, const char *title, int depth) {
    Window root, ancestor, *children = NULL, found = None;
    unsigned count = 0;
    if (depth > 8 || !XQueryTree(display, parent, &root, &ancestor, &children, &count)) return None;
    for (unsigned i = 0; i < count && found == None; i++) {
        XWindowAttributes attrs;
        char *name = window_name(display, children[i]);
        if (XGetWindowAttributes(display, children[i], &attrs) && attrs.map_state == IsViewable &&
            attrs.width >= 100 && attrs.height >= 100 && (!*title || (name && strstr(name, title)))) {
            printf("ANDROID-WINDOW id=%lu title=%s width=%d height=%d\n",
                   children[i], name ? name : "", attrs.width, attrs.height);
            found = children[i];
        }
        if (name) XFree(name);
        if (found == None) found = find_window(display, children[i], title, depth + 1);
    }
    if (children) XFree(children);
    return found;
}

static int painted(Display *display, Window window) {
    XWindowAttributes attrs;
    if (!XGetWindowAttributes(display, window, &attrs)) return 1;
    XImage *image = XGetImage(display, window, 0, 0, (unsigned)attrs.width,
                             (unsigned)attrs.height, AllPlanes, ZPixmap);
    if (!image) return 1;
    unsigned long colours[256];
    unsigned unique = 0;
    uint64_t hash = UINT64_C(1469598103934665603);
    for (int y = 0; y < attrs.height; y += 3) {
        for (int x = 0; x < attrs.width; x += 3) {
            unsigned long pixel = XGetPixel(image, x, y);
            hash = (hash ^ pixel) * UINT64_C(1099511628211);
            unsigned i;
            for (i = 0; i < unique && colours[i] != pixel; i++) {}
            if (i == unique && unique < 256) colours[unique++] = pixel;
        }
    }
    XDestroyImage(image);
    printf("ANDROID-PIXELS colours=%u hash=%llu\n", unique, (unsigned long long)hash);
    return unique > 16 ? 0 : 1;
}

static int type_text(Display *display, Window window, const char *text, int click_x, int click_y) {
    XSetInputFocus(display, window, RevertToParent, CurrentTime);
    XSync(display, False);
    Window child;
    int root_x, root_y;
    if (!XTranslateCoordinates(display, window, DefaultRootWindow(display),
                               click_x, click_y, &root_x, &root_y, &child)) return 1;
    XTestFakeMotionEvent(display, DefaultScreen(display), root_x, root_y, CurrentTime);
    XTestFakeButtonEvent(display, 1, True, CurrentTime);
    XFlush(display);
    pause_ms(100);
    XTestFakeButtonEvent(display, 1, False, CurrentTime);
    XFlush(display);
    pause_ms(3000);
    for (const unsigned char *p = (const unsigned char *)text; *p; p++) {
        KeySym sym = *p == '\n' ? XK_Return : *p;
        KeyCode code = XKeysymToKeycode(display, sym);
        if (!code) return 1;
        int shifted = XkbKeycodeToKeysym(display, code, 0, 0) != sym && sym != XK_Return;
        KeyCode shift = XKeysymToKeycode(display, XK_Shift_L);
        if (shifted) XTestFakeKeyEvent(display, shift, True, CurrentTime);
        XTestFakeKeyEvent(display, code, True, CurrentTime);
        XFlush(display);
        pause_ms(100);
        XTestFakeKeyEvent(display, code, False, CurrentTime);
        if (shifted) XTestFakeKeyEvent(display, shift, False, CurrentTime);
        XFlush(display);
        pause_ms(100);
    }
    return 0;
}

/* Bring-up mode presents the actual Xvfb root on fbdev before the desktop
 * integration is available. The normal test uses vinix-desktop instead. */
static int present(Display *display) {
    int fd = open("/dev/fb0", O_RDWR), console = open("/dev/console", O_RDWR);
    struct fb_var_screeninfo var;
    struct fb_fix_screeninfo fix;
    if (fd < 0 || ioctl(fd, FBIOGET_VSCREENINFO, &var) ||
        ioctl(fd, FBIOGET_FSCREENINFO, &fix) || var.bits_per_pixel != 32) return 1;
    size_t size = (size_t)fix.line_length * var.yres;
    uint8_t *pixels = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (pixels == MAP_FAILED) return 1;
    if (console >= 0) (void)ioctl(console, KDSETMODE, KD_GRAPHICS);
    signal(SIGTERM, stop); signal(SIGINT, stop);
    Window root = DefaultRootWindow(display);
    unsigned width = (unsigned)DisplayWidth(display, DefaultScreen(display));
    unsigned height = (unsigned)DisplayHeight(display, DefaultScreen(display));
    if (width > var.xres) width = var.xres;
    if (height > var.yres) height = var.yres;
    unsigned x0 = (var.xres - width) / 2, y0 = (var.yres - height) / 2;
    memset(pixels, 0x28, size);
    while (running) {
        XImage *image = XGetImage(display, root, 0, 0, width, height, AllPlanes, ZPixmap);
        if (!image) break;
        for (unsigned y = 0; y < height; y++) {
            uint32_t *row = (uint32_t *)(pixels + (y + y0) * fix.line_length);
            for (unsigned x = 0; x < width; x++) {
                unsigned long pixel = XGetPixel(image, (int)x, (int)y);
                row[x + x0] = ((pixel >> 16 & 255) << var.red.offset) |
                              ((pixel >> 8 & 255) << var.green.offset) |
                              ((pixel & 255) << var.blue.offset);
            }
        }
        XDestroyImage(image);
        pause_ms(250);
    }
    if (console >= 0) { (void)ioctl(console, KDSETMODE, KD_TEXT); close(console); }
    munmap(pixels, size); close(fd);
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 3 || argc > 7) {
        fprintf(stderr, "usage: %s DISPLAY inspect|type|present [TITLE] [TEXT] [CLICK_X CLICK_Y]\n", argv[0]);
        return 2;
    }
    Display *display = XOpenDisplay(argv[1]);
    if (!display) return 1;
    XSetErrorHandler(ignore_error);
    int result = 1;
    if (!strcmp(argv[2], "present")) result = present(display);
    else {
        Window window = find_window(display, DefaultRootWindow(display), argc >= 4 ? argv[3] : "", 0);
        if (window != None) {
            if (!strcmp(argv[2], "inspect")) result = painted(display, window);
            else if (!strcmp(argv[2], "type") && (argc == 5 || argc == 7))
                result = type_text(display, window, argv[4],
                                   argc == 7 ? atoi(argv[5]) : 240, argc == 7 ? atoi(argv[6]) : 120);
        }
    }
    XCloseDisplay(display);
    return result;
}
