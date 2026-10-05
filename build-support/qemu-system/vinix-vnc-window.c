// A fixed-size X11 viewer for the raw RFB stream from QEMU's VNC display.
// Keeping the X window fixed avoids the Xvfb resize path used by larger VNC
// clients. The native Vinix desktop embeds this X11 window through its normal
// hosted-application bridge.
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <arpa/inet.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <unistd.h>

#define VIEW_WIDTH 1024
#define VIEW_HEIGHT 768
#define TILE_WIDTH 128
#define TILE_HEIGHT 64

static int read_all(int fd, void *buffer, size_t size) {
    unsigned char *out = buffer;
    while (size != 0) {
        ssize_t count = recv(fd, out, size, 0);
        if (count <= 0) {
            if (count < 0 && errno == EINTR) continue;
            return -1;
        }
        out += count;
        size -= (size_t)count;
    }
    return 0;
}

static int write_all(int fd, const void *buffer, size_t size) {
    const unsigned char *in = buffer;
    while (size != 0) {
        ssize_t count = send(fd, in, size, 0);
        if (count <= 0) {
            if (count < 0 && errno == EINTR) continue;
            return -1;
        }
        in += count;
        size -= (size_t)count;
    }
    return 0;
}

static unsigned be16(const unsigned char *bytes) {
    return (unsigned)bytes[0] << 8 | bytes[1];
}

static uint32_t be32(const unsigned char *bytes) {
    return (uint32_t)bytes[0] << 24 | (uint32_t)bytes[1] << 16 |
           (uint32_t)bytes[2] << 8 | bytes[3];
}

static void put16(unsigned char *out, unsigned value) {
    out[0] = (unsigned char)(value >> 8);
    out[1] = (unsigned char)value;
}

static void put32(unsigned char *out, uint32_t value) {
    out[0] = (unsigned char)(value >> 24);
    out[1] = (unsigned char)(value >> 16);
    out[2] = (unsigned char)(value >> 8);
    out[3] = (unsigned char)value;
}

static int connect_vnc(void) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address;
    if (fd < 0) return -1;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(5901);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}

static int negotiate(int fd, unsigned *width, unsigned *height) {
    unsigned char version[12], count, types[255], result[4], setup[24];
    uint32_t name_length;
    char name[4096];
    unsigned char pixel_format[20] = {
        0, 0, 0, 0,       // SetPixelFormat and padding
        32, 24, 0, 1,     // bits, depth, little endian, true colour
        0, 255, 0, 255, 0, 255, // channel maxima
        16, 8, 0, 0, 0, 0 // channel shifts and padding
    };
    unsigned char encodings[12] = {
        2, 0, 0, 2,       // SetEncodings: raw and DesktopSize
        0, 0, 0, 0,       // Raw
        255, 255, 255, 33 // DesktopSize (-223)
    };

    if (read_all(fd, version, sizeof(version)) != 0 ||
        memcmp(version, "RFB 003.008\n", sizeof(version)) != 0 ||
        write_all(fd, "RFB 003.008\n", 12) != 0 ||
        read_all(fd, &count, 1) != 0 || count == 0 ||
        read_all(fd, types, count) != 0) return -1;
    int supports_none = 0;
    for (unsigned i = 0; i < count; i++) supports_none |= types[i] == 1;
    if (!supports_none) return -1;
    count = 1;
    if (write_all(fd, &count, 1) != 0 ||
        read_all(fd, result, 4) != 0 || be32(result) != 0) return -1;
    count = 1; // Share the server with any other local viewer.
    if (write_all(fd, &count, 1) != 0 ||
        read_all(fd, setup, sizeof(setup)) != 0) return -1;
    *width = be16(setup);
    *height = be16(setup + 2);
    name_length = be32(setup + 20);
    if (*width == 0 || *height == 0 || *width > VIEW_WIDTH ||
        *height > VIEW_HEIGHT || name_length >= sizeof(name) ||
        read_all(fd, name, name_length) != 0 ||
        write_all(fd, pixel_format, sizeof(pixel_format)) != 0 ||
        write_all(fd, encodings, sizeof(encodings)) != 0) return -1;
    name[name_length] = 0;
    fprintf(stderr, "vinix-vnc-window: connected to %s (%ux%u)\n",
            name, *width, *height);
    return 0;
}

static int request_update(int fd, unsigned width, unsigned height,
                          int incremental) {
    unsigned char request[10] = {3, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    request[1] = (unsigned char)incremental;
    put16(request + 6, width);
    put16(request + 8, height);
    return write_all(fd, request, sizeof(request));
}

static void paint(Display *display, Window window, GC gc, XImage *image,
                  unsigned x, unsigned y, unsigned width, unsigned height) {
    unsigned end_x = x + width, end_y = y + height;
    for (unsigned row = y; row < end_y; row += TILE_HEIGHT) {
        unsigned tile_height = end_y - row < TILE_HEIGHT ? end_y - row : TILE_HEIGHT;
        for (unsigned column = x; column < end_x; column += TILE_WIDTH) {
            unsigned tile_width = end_x - column < TILE_WIDTH ? end_x - column : TILE_WIDTH;
            XPutImage(display, window, gc, image, (int)column, (int)row,
                      (int)column, (int)row, tile_width, tile_height);
        }
    }
    XFlush(display);
}

static int receive_update(int fd, Display *display, Window window, GC gc,
                          XImage *image, unsigned *width, unsigned *height,
                          int *resized) {
    unsigned char type, header[3], rect[12];
    if (read_all(fd, &type, 1) != 0) return -1;
    if (type == 2) return 0; // Bell.
    if (type == 3) { // ServerCutText.
        unsigned char text_header[7], discard[256];
        if (read_all(fd, text_header, sizeof(text_header)) != 0) return -1;
        uint32_t left = be32(text_header + 3);
        if (left > 1024 * 1024) return -1;
        while (left != 0) {
            unsigned chunk = left > sizeof(discard) ? sizeof(discard) : left;
            if (read_all(fd, discard, chunk) != 0) return -1;
            left -= chunk;
        }
        return 0;
    }
    if (type != 0 || read_all(fd, header, sizeof(header)) != 0) return -1;
    unsigned rectangles = be16(header + 1);
    for (unsigned i = 0; i < rectangles; i++) {
        if (read_all(fd, rect, sizeof(rect)) != 0) return -1;
        unsigned x = be16(rect), y = be16(rect + 2);
        unsigned w = be16(rect + 4), h = be16(rect + 6);
        uint32_t encoding = be32(rect + 8);
        if (encoding == UINT32_C(0xffffff21)) {
            if (w == 0 || h == 0 || w > VIEW_WIDTH || h > VIEW_HEIGHT)
                return -1;
            *width = w;
            *height = h;
            *resized = 1;
            fprintf(stderr, "vinix-vnc-window: framebuffer %ux%u\n", w, h);
            continue;
        }
        if (encoding != 0 || w == 0 || h == 0 || x + w > VIEW_WIDTH ||
            y + h > VIEW_HEIGHT || x + w > *width || y + h > *height)
            return -1;
        for (unsigned row = 0; row < h; row++) {
            unsigned char *dest = (unsigned char *)image->data +
                                  ((size_t)(y + row) * VIEW_WIDTH + x) * 4;
            if (read_all(fd, dest, (size_t)w * 4) != 0) return -1;
        }
        paint(display, window, gc, image, x, y, w, h);
    }
    return 0;
}

static int send_key(int fd, KeySym symbol, int down) {
    unsigned char event[8] = {4, 0, 0, 0, 0, 0, 0, 0};
    event[1] = (unsigned char)down;
    put32(event + 4, (uint32_t)symbol);
    return write_all(fd, event, sizeof(event));
}

static int send_pointer(int fd, unsigned mask, int x, int y) {
    unsigned char event[6] = {5, 0, 0, 0, 0, 0};
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x >= VIEW_WIDTH) x = VIEW_WIDTH - 1;
    if (y >= VIEW_HEIGHT) y = VIEW_HEIGHT - 1;
    event[1] = (unsigned char)mask;
    put16(event + 2, (unsigned)x);
    put16(event + 4, (unsigned)y);
    return write_all(fd, event, sizeof(event));
}

static unsigned buttons(unsigned state) {
    return (state & Button1Mask ? 1 : 0) |
           (state & Button2Mask ? 2 : 0) |
           (state & Button3Mask ? 4 : 0);
}

int main(void) {
    Display *display = XOpenDisplay(NULL);
    if (display == NULL) {
        fprintf(stderr, "vinix-vnc-window: cannot open X11 display\n");
        return 1;
    }
    int screen = DefaultScreen(display);
    Window window = XCreateSimpleWindow(display, RootWindow(display, screen),
                                        0, 0, VIEW_WIDTH, VIEW_HEIGHT, 0, 0,
                                        BlackPixel(display, screen));
    XSelectInput(display, window, ExposureMask | KeyPressMask | KeyReleaseMask |
                ButtonPressMask | ButtonReleaseMask | PointerMotionMask);
    XStoreName(display, window, "Vinix in QEMU");
    XMapWindow(display, window);
    GC gc = XCreateGC(display, window, 0, NULL);
    char *pixels = calloc((size_t)VIEW_WIDTH * VIEW_HEIGHT, 4);
    if (pixels == NULL) return 1;
    XImage *image = XCreateImage(display, DefaultVisual(display, screen),
                                 DefaultDepth(display, screen), ZPixmap, 0,
                                 pixels, VIEW_WIDTH, VIEW_HEIGHT, 32,
                                 VIEW_WIDTH * 4);
    if (image == NULL) return 1;
    int fd = -1;
    for (unsigned attempt = 0; attempt < 100; attempt++) {
        fd = connect_vnc();
        if (fd >= 0) break;
        usleep(100000);
    }
    if (fd < 0) {
        perror("vinix-vnc-window: connect");
        return 1;
    }
    unsigned width, height;
    if (negotiate(fd, &width, &height) != 0 ||
        request_update(fd, width, height, 0) != 0) {
        fprintf(stderr, "vinix-vnc-window: RFB handshake failed\n");
        return 1;
    }
    for (;;) {
        while (XPending(display) != 0) {
            XEvent event;
            XNextEvent(display, &event);
            if (event.type == Expose && event.xexpose.count == 0) {
                paint(display, window, gc, image, 0, 0, VIEW_WIDTH, VIEW_HEIGHT);
            } else if (event.type == KeyPress || event.type == KeyRelease) {
                KeySym symbol = XLookupKeysym(&event.xkey, 0);
                if (symbol != NoSymbol &&
                    send_key(fd, symbol, event.type == KeyPress) != 0) goto done;
            } else if (event.type == MotionNotify) {
                if (send_pointer(fd, buttons(event.xmotion.state),
                                 event.xmotion.x, event.xmotion.y) != 0) goto done;
            } else if (event.type == ButtonPress || event.type == ButtonRelease) {
                unsigned mask = buttons(event.xbutton.state);
                unsigned bit = event.xbutton.button == Button1 ? 1 :
                               event.xbutton.button == Button2 ? 2 :
                               event.xbutton.button == Button3 ? 4 : 0;
                mask = event.type == ButtonPress ? mask | bit : mask & ~bit;
                if (send_pointer(fd, mask, event.xbutton.x, event.xbutton.y) != 0)
                    goto done;
            }
        }
        fd_set readable;
        FD_ZERO(&readable);
        FD_SET(fd, &readable);
        FD_SET(ConnectionNumber(display), &readable);
        int max_fd = fd > ConnectionNumber(display) ? fd : ConnectionNumber(display);
        int ready = select(max_fd + 1, &readable, NULL, NULL, NULL);
        if (ready < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (FD_ISSET(fd, &readable)) {
            int resized = 0;
            if (receive_update(fd, display, window, gc, image, &width, &height,
                               &resized) != 0 ||
                request_update(fd, width, height, !resized) != 0) break;
        }
    }
done:
    fprintf(stderr, "vinix-vnc-window: disconnected\n");
    close(fd);
    XDestroyImage(image);
    XFreeGC(display, gc);
    XDestroyWindow(display, window);
    XCloseDisplay(display);
    return 0;
}
