/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_DESKTOP_BATTERY_CLIENT_H
#define VINIX_DESKTOP_BATTERY_CLIENT_H

#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdint.h>
#include <time.h>
#include <unistd.h>

/* Percentages are nonnegative; failures must never look like an empty battery. */
enum {
    VD_BATTERY_UNAVAILABLE = -1,
    VD_BATTERY_PERMISSION = -2,
    VD_BATTERY_INVALID = -3,
    VD_BATTERY_IO = -4
};

#ifndef VD_BATTERY_OPEN
#define VD_BATTERY_OPEN open
#define VD_BATTERY_READ read
#define VD_BATTERY_CLOSE close
#endif

static inline int vd_battery_errno(int error)
{
    if (error == ENOENT || error == ENODEV || error == ENXIO)
        return VD_BATTERY_UNAVAILABLE;
    if (error == EACCES || error == EPERM)
        return VD_BATTERY_PERMISSION;
    return VD_BATTERY_IO;
}

/* The driver emits one to three decimal digits and LF, then EOF. Reject
 * truncated, oversized, signed, whitespace-padded or otherwise malformed data.
 */
static inline int vd_battery_parse(const char *text, size_t length)
{
    if (!text || length < 2 || length > 4 || text[length - 1] != '\n')
        return VD_BATTERY_INVALID;
    int percent = 0;
    for (size_t i = 0; i + 1 < length; ++i) {
        if (text[i] < '0' || text[i] > '9')
            return VD_BATTERY_INVALID;
        percent = percent * 10 + (text[i] - '0');
    }
    return percent <= 100 ? percent : VD_BATTERY_INVALID;
}

static inline int vd_battery_read_percent(void)
{
    int fd = -1;
    for (unsigned retry = 0; retry < 16; ++retry) {
        fd = VD_BATTERY_OPEN("/dev/battery", O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd >= 0 || errno != EINTR)
            break;
    }
    if (fd < 0)
        return vd_battery_errno(errno);

    char text[5]; /* Four valid bytes plus one byte to detect excess input. */
    size_t used = 0;
    int result = VD_BATTERY_IO;
    for (unsigned attempt = 0; attempt < 32; ++attempt) {
        ssize_t count = VD_BATTERY_READ(fd, text + used, sizeof(text) - used);
        if (count < 0) {
            if (errno == EINTR)
                continue;
            result = vd_battery_errno(errno);
            break;
        }
        if (count == 0) {
            result = vd_battery_parse(text, used);
            break;
        }
        used += (size_t)count;
        if (used >= sizeof(text)) {
            result = VD_BATTERY_INVALID;
            break;
        }
    }
    /* Never retry close after EINTR: the descriptor may already be released. */
    if (VD_BATTERY_CLOSE(fd) < 0)
        result = VD_BATTERY_IO;
    return result;
}

typedef struct VdBatteryCache {
    uint64_t polled_ms;
    int initialized;
    int value;
} VdBatteryCache;

/* The desktop is single-threaded. Settings and the taskbar share this cache,
 * so drawing/moving a window never turns into a stream of device opens.
 * now_ms == UINT64_MAX means the monotonic clock failed: discard stale data.
 */
static inline int vd_battery_poll_cache(VdBatteryCache *cache, uint64_t now_ms,
                                       int force, int (*reader)(void))
{
    if (now_ms == UINT64_MAX) {
        cache->initialized = 0;
        cache->value = VD_BATTERY_IO;
        return cache->value;
    }
    if (!force && cache->initialized && now_ms >= cache->polled_ms &&
        now_ms - cache->polled_ms < UINT64_C(5000))
        return cache->value;
    int next = reader();
    if (next > 100 || next < VD_BATTERY_IO)
        next = VD_BATTERY_INVALID;
    cache->value = next;
    cache->polled_ms = now_ms;
    cache->initialized = 1;
    return next;
}

static inline uint64_t vd_battery_now_ms(void)
{
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0 || now.tv_sec < 0)
        return UINT64_MAX;
    return (uint64_t)now.tv_sec * UINT64_C(1000) + (uint64_t)now.tv_nsec / UINT64_C(1000000);
}

static inline int vd_battery_get(int force)
{
    static VdBatteryCache cache = {0, 0, VD_BATTERY_UNAVAILABLE};
    return vd_battery_poll_cache(&cache, vd_battery_now_ms(), force, vd_battery_read_percent);
}

#endif
