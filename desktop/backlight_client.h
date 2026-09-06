/* SPDX-License-Identifier: GPL-2.0-or-later
 * Userspace adapter for the apple-panel-bl text ABI. No hardware access.
 * Header-only, like shim.h: stage_app.py carries *.h into the V -> C build.
 */
#ifndef VINIX_DESKTOP_BACKLIGHT_CLIENT_H
#define VINIX_DESKTOP_BACKLIGHT_CLIENT_H

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define VD_BL_PATH "/dev/apple-panel-bl"
#define VD_BL_CAPACITY 256U
#define VD_BL_RETRIES 4

/* A private desktop API, not errno values (which differ between platforms). */
enum vd_bl_result {
    VD_BL_OK = 0,
    VD_BL_UNAVAILABLE = 1,
    VD_BL_PERMISSION = 2,
    VD_BL_OFFLINE = 3,
    VD_BL_INVALID = 4,
    VD_BL_IO = 5
};

typedef struct VdBlState {
    int requested_nits; /* -1 means unknown, never synthesized from a write */
    int actual_nits;    /* -1 means unknown, may be outside the writable range */
    int min_nits;
    int max_nits;
    int pending;
    int online;
    int writable;
} VdBlState;

static inline int vd_bl_decimal(const char *s, size_t n, int *out)
{
    int value = 0;
    if (!n)
        return VD_BL_INVALID;
    for (size_t i = 0; i < n; ++i) {
        int digit = (int)(unsigned char)s[i] - '0';
        if (digit < 0 || digit > 9 || value > (INT_MAX - digit) / 10)
            return VD_BL_INVALID;
        value = value * 10 + digit;
    }
    *out = value;
    return VD_BL_OK;
}

/* Parse one whole snapshot from ONE read: the kernel snapshots per read,
 * not per open. Never concatenate short reads from different snapshots.
 * Fail atomically on duplicates, missing keys, overflow, or malformed input.
 */
static inline int vd_bl_parse(const char *text, size_t length, VdBlState *out)
{
    static const char *const keys[] = {
        "requested_nits", "actual_nits", "min_nits", "max_nits", "pending", "online"
    };
    int values[6] = {0};
    unsigned seen = 0;
    size_t pos = 0;
    if (!text || !out || !length || length >= VD_BL_CAPACITY)
        return VD_BL_INVALID;
    while (pos < length) {
        size_t start = pos;
        while (pos < length && text[pos] != '\n')
            ++pos;
        if (pos == length)
            return VD_BL_INVALID;
        size_t end = pos++;
        size_t eq = start;
        while (eq < end && text[eq] != '=')
            ++eq;
        if (eq == end)
            return VD_BL_INVALID;
        int field = -1;
        for (int i = 0; i < 6; ++i) {
            if (strlen(keys[i]) == eq - start &&
                memcmp(text + start, keys[i], eq - start) == 0) {
                field = i;
                break;
            }
        }
        if (field < 0 || (seen & (1U << (unsigned)field)))
            return VD_BL_INVALID;
        seen |= 1U << (unsigned)field;
        const char *value = text + eq + 1;
        size_t n = end - eq - 1;
        if (field < 2 && n == 7 && memcmp(value, "unknown", 7) == 0)
            values[field] = -1;
        else if (vd_bl_decimal(value, n, &values[field]) != VD_BL_OK)
            return VD_BL_INVALID;
    }
    if (seen != 63 || values[2] < 1 || values[3] < values[2] ||
        values[4] > 1 || values[5] > 1 ||
        (values[0] != -1 && (values[0] < values[2] || values[0] > values[3])))
        return VD_BL_INVALID;
    *out = (VdBlState){values[0], values[1], values[2], values[3], values[4], values[5], 0};
    return VD_BL_OK;
}

static inline int vd_bl_percent_to_nits(const VdBlState *s, int percent)
{
    if (percent < 0 || percent > 100 || s->min_nits < 1 || s->max_nits < s->min_nits)
        return -1;
    /* 0% is the supported minimum, not panel power off. */
    return s->min_nits + (int)((((int64_t)s->max_nits - s->min_nits) * percent + 50) / 100);
}

static inline int vd_bl_percent(const VdBlState *s)
{
    int nits = s->requested_nits >= 0 ? s->requested_nits : s->actual_nits;
    if (nits < 0 || s->min_nits < 1 || s->max_nits < s->min_nits)
        return -1;
    if (nits <= s->min_nits || s->max_nits == s->min_nits)
        return 0;
    if (nits >= s->max_nits)
        return 100;
    int64_t range = (int64_t)s->max_nits - s->min_nits;
    return (int)((((int64_t)nits - s->min_nits) * 100 + range / 2) / range);
}

static inline int vd_bl_errno_result(int error)
{
    if (error == ENOENT || error == ENODEV || error == ENXIO)
        return VD_BL_UNAVAILABLE;
    if (error == EACCES || error == EPERM || error == EROFS)
        return VD_BL_PERMISSION;
    return VD_BL_IO;
}

/* The test harness substitutes only these POSIX calls. Production always
 * uses the fixed character-device path, never a shell or a settings file. */
#ifndef VD_BL_OPEN
#define VD_BL_OPEN open
#define VD_BL_READ read
#define VD_BL_WRITE write
#define VD_BL_CLOSE close
#define VD_BL_FSTAT fstat
#endif

static inline int vd_bl_open_state(VdBlState *out, int *fd_out)
{
    int flags = O_NONBLOCK | O_CLOEXEC;
    int writable = 1;
    int fd = VD_BL_OPEN(VD_BL_PATH, O_RDWR | flags);
    if (fd < 0 && vd_bl_errno_result(errno) == VD_BL_PERMISSION) {
        writable = 0;
        fd = VD_BL_OPEN(VD_BL_PATH, O_RDONLY | flags);
    }
    if (fd < 0)
        return vd_bl_errno_result(errno);
    struct stat st;
    if (VD_BL_FSTAT(fd, &st) < 0) {
        VD_BL_CLOSE(fd);
        return VD_BL_IO;
    }
    if (!S_ISCHR(st.st_mode)) {
        VD_BL_CLOSE(fd);
        return VD_BL_INVALID;
    }
    char text[VD_BL_CAPACITY];
    ssize_t length = -1;
    for (int attempt = 0; attempt < VD_BL_RETRIES; ++attempt) {
        length = VD_BL_READ(fd, text, sizeof(text));
        if (length >= 0 || errno != EINTR)
            break;
    }
    if (length < 0) {
        int result = vd_bl_errno_result(errno);
        VD_BL_CLOSE(fd);
        return result;
    }
    VdBlState next;
    int result = vd_bl_parse(text, (size_t)length, &next);
    if (result != VD_BL_OK) {
        VD_BL_CLOSE(fd);
        return result;
    }
    next.writable = writable;
    *out = next;
    *fd_out = fd;
    return VD_BL_OK;
}

static inline int vd_bl_read_state(VdBlState *out)
{
    int fd;
    int result = vd_bl_open_state(out, &fd);
    if (result == VD_BL_OK)
        VD_BL_CLOSE(fd);
    return result;
}

/* One click -> one whole write, after revalidating current bounds/status.
 * Positive short writes are not retried: a suffix is a new nit command.
 * Success means queued; only readback supplies requested/actual/pending.
 */
static inline int vd_bl_set_percent(int percent)
{
    VdBlState state;
    int fd;
    if (percent < 0 || percent > 100)
        return VD_BL_INVALID;
    int result = vd_bl_open_state(&state, &fd);
    if (result != VD_BL_OK)
        return result;
    if (!state.online || !state.writable) {
        VD_BL_CLOSE(fd);
        return state.online ? VD_BL_PERMISSION : VD_BL_OFFLINE;
    }
    int nits = vd_bl_percent_to_nits(&state, percent);
    char text[16];
    int length = snprintf(text, sizeof(text), "%d\n", nits);
    if (nits < 0 || length <= 0 || (size_t)length >= sizeof(text)) {
        VD_BL_CLOSE(fd);
        return VD_BL_INVALID;
    }
    ssize_t written = -1;
    for (int attempt = 0; attempt < VD_BL_RETRIES; ++attempt) {
        written = VD_BL_WRITE(fd, text, (size_t)length);
        if (written >= 0 || errno != EINTR)
            break;
    }
    result = written < 0 ? vd_bl_errno_result(errno) :
             (written == length ? VD_BL_OK : VD_BL_IO);
    VD_BL_CLOSE(fd);
    return result;
}

static inline uint64_t vd_bl_now_ms(void)
{
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0)
        return 0;
    return (uint64_t)now.tv_sec * 1000U + (uint64_t)now.tv_nsec / 1000000U;
}

#endif
