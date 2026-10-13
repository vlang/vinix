/* SPDX-License-Identifier: MIT */
#ifndef VINIX_WINDOW_H
#define VINIX_WINDOW_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VINIX_WINDOW_API_VERSION 2u
#define VINIX_WINDOW_MAX_PAYLOAD 4096u
#define VINIX_WINDOW_ERROR_SIZE 256u
#define VINIX_WINDOW_FORMAT_XRGB8888 1u
#define VINIX_WINDOW_KEYBOARD_FLAGS 31u

typedef struct vinix_window vinix_window;

typedef struct vinix_framebuffer {
    uint32_t *pixels;
    uint32_t width;
    uint32_t height;
    uint32_t stride; /* Bytes per row. Pixel value: 0x00RRGGBB. */
    uint32_t format;
} vinix_framebuffer;

enum vinix_window_event_kind {
    VINIX_WINDOW_FRAME_DONE = 4,
    VINIX_WINDOW_MOTION = 5,
    VINIX_WINDOW_BUTTON_DOWN = 6,
    VINIX_WINDOW_BUTTON_UP = 7,
    VINIX_WINDOW_KEYS = 8,
    VINIX_WINDOW_WHEEL = 9,
    VINIX_WINDOW_HORIZONTAL_WHEEL = 10,
    VINIX_WINDOW_CONFIGURE = 11,
    VINIX_WINDOW_FOCUS = 12,
    VINIX_WINDOW_CLOSE = 13
};

typedef struct vinix_window_event {
    uint32_t kind;
    int32_t x;
    int32_t y;
    int32_t value;
    uint32_t length;
    uint8_t payload[VINIX_WINDOW_MAX_PAYLOAD]; /* length bytes, not a C string. */
} vinix_window_event;

typedef struct vinix_window_error {
    char message[VINIX_WINDOW_ERROR_SIZE]; /* NUL terminated, caller owned. */
} vinix_window_error;

uint32_t vinix_window_api_version(void);

/* Blocking creation, with a five-second handshake wait. Returns NULL on error.
 * Strings need only remain valid for this call. error may be NULL on all calls.
 * open uses VINIX_WINDOW_SOCKET or /run/vinix-session.<uid>/windows. */
vinix_window *vinix_window_open(const char *title, int32_t width, int32_t height,
                              vinix_window_error *error);
vinix_window *vinix_window_open_at(const char *socket_path, const char *title,
                                 int32_t width, int32_t height,
                                 vinix_window_error *error);

/* Releases the mapping, socket and handle. NULL is accepted. A non-NULL handle
 * must be closed exactly once; discard it and all pixel pointers afterwards. */
void vinix_window_close(vinix_window *window);

/* Borrowed nonblocking socket for poll/select/epoll. Do not close or read/write
 * it yourself. Use next_event to decode readiness, including partial records. */
int32_t vinix_window_event_fd(vinix_window *window);

/* 0 on success, -1 for a NULL handle/output. Pixels remain valid until the next
 * CONFIGURE with a nonempty payload, or close. Reacquire this struct on resize.
 * Draw only when frame_pending is 0; do not change pixels until FRAME_DONE. */
int32_t vinix_window_get_framebuffer(vinix_window *window, vinix_framebuffer *out);
int32_t vinix_window_frame_pending(vinix_window *window); /* 1/0, -1 for NULL. */
int32_t vinix_window_wants_write(vinix_window *window); /* 1/0, -1 for NULL. */
int32_t vinix_window_present(vinix_window *window, vinix_window_error *error);
int32_t vinix_window_set_title(vinix_window *window, const char *title,
                             vinix_window_error *error);

/* Nonblocking: 1 = event, 0 = incomplete/no event, -1 = error/disconnect.
 * out is unchanged on 0/-1. Drain until 0 after readiness. Reading FRAME_DONE
 * clears frame_pending. A CONFIGURE with a nonempty payload automatically maps
 * the replacement and acknowledges it before returning; reacquire pixels and
 * redraw when frame_pending is 0. KEYS uses Kitty keyboard protocol flags 31.
 * A CLOSE event or EOF/error ends the window lifetime. */
int32_t vinix_window_next_event(vinix_window *window, vinix_window_event *out,
                               vinix_window_error *error);

/* 1 = readable/hangup, 0 = no readable event (timeout/interruption), -1 = error.
 * timeout_ms: -1 forever, 0 probe, otherwise milliseconds. Handles queued writes.
 * With an external poll, include POLLOUT when wants_write is 1, and call wait(0)
 * on that readiness to flush pending output before decoding input. */
int32_t vinix_window_wait(vinix_window *window, int32_t timeout_ms,
                        vinix_window_error *error);

#ifdef __cplusplus
}
#endif
#endif
