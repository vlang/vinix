/* SPDX-License-Identifier: GPL-2.0-or-later */
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

static int mock_open(const char *, int);
static ssize_t mock_read(int, void *, size_t);
static ssize_t mock_write(int, const void *, size_t);
static int mock_close(int);
static int mock_fstat(int, struct stat *);
#define VD_BL_OPEN mock_open
#define VD_BL_READ mock_read
#define VD_BL_WRITE mock_write
#define VD_BL_CLOSE mock_close
#define VD_BL_FSTAT mock_fstat
#include "backlight_client.h"
#include "apple_dcp_backlight.h"

static const char valid[] =
    "requested_nits=100\nactual_nits=99\nmin_nits=2\nmax_nits=400\npending=0\nonline=1\n";
static const char unknown[] =
    "online=1\npending=1\nmin_nits=2\nmax_nits=400\nactual_nits=unknown\nrequested_nits=unknown\n";
static const char *reply;
static size_t reply_length;
static int open_error, rw_error, read_error, write_error, stat_error;
static int interrupted_reads, interrupted_writes, short_write, is_regular;
static int opens, closes, reads, writes, live;
static char written_text[32];

static void reset(void)
{
    assert(live == 0);
    reply = valid;
    reply_length = strlen(reply);
    open_error = rw_error = read_error = write_error = stat_error = 0;
    interrupted_reads = interrupted_writes = short_write = is_regular = 0;
    opens = closes = reads = writes = 0;
    written_text[0] = 0;
}
static void set_reply(const char *s)
{
    reply = s;
    reply_length = strlen(s);
}
static int mock_open(const char *path, int flags)
{
    ++opens;
    assert(strcmp(path, VD_BL_PATH) == 0);
    assert(!(flags & (O_CREAT | O_TRUNC | O_APPEND)));
    assert(flags & O_NONBLOCK);
    assert(flags & O_CLOEXEC);
    if (open_error || ((flags & O_ACCMODE) == O_RDWR && rw_error)) {
        errno = open_error ? open_error : rw_error;
        return -1;
    }
    assert(live == 0);
    ++live;
    return 42;
}
static ssize_t mock_read(int fd, void *buffer, size_t capacity)
{
    assert(fd == 42 && live == 1);
    ++reads;
    if (interrupted_reads > 0) {
        --interrupted_reads;
        errno = EINTR;
        return -1;
    }
    if (read_error) {
        errno = read_error;
        return -1;
    }
    size_t n = reply_length < capacity ? reply_length : capacity;
    memcpy(buffer, reply, n);
    return (ssize_t)n;
}
static ssize_t mock_write(int fd, const void *buffer, size_t length)
{
    assert(fd == 42 && live == 1);
    ++writes;
    if (interrupted_writes > 0) {
        --interrupted_writes;
        errno = EINTR;
        return -1;
    }
    if (write_error) {
        errno = write_error;
        return -1;
    }
    assert(length < sizeof(written_text));
    memcpy(written_text, buffer, length);
    written_text[length] = 0;
    return (ssize_t)(short_write ? length - 1 : length);
}
static int mock_close(int fd)
{
    assert(fd == 42 && live == 1);
    --live;
    ++closes;
    return 0;
}
static int mock_fstat(int fd, struct stat *out)
{
    assert(fd == 42 && live == 1);
    if (stat_error) {
        errno = stat_error;
        return -1;
    }
    memset(out, 0, sizeof(*out));
    /* POSIX file type encodings, avoiding nonstandard S_IF* visibility. */
    out->st_mode = (mode_t)(is_regular ? 0100000 : 0020000);
    return 0;
}
static void reject(const char *s)
{
    VdBlState out;
    memset(&out, 0x5a, sizeof(out));
    VdBlState before = out;
    assert(vd_bl_parse(s, strlen(s), &out) == VD_BL_INVALID);
    assert(memcmp(&out, &before, sizeof(out)) == 0);
}
static void test_parser(void)
{
    VdBlState state;
    assert(vd_bl_parse(valid, strlen(valid), &state) == VD_BL_OK);
    assert(state.requested_nits == 100 && state.actual_nits == 99);
    assert(state.min_nits == 2 && state.max_nits == 400);
    assert(state.online == 1 && state.pending == 0 && state.writable == 0);
    assert(vd_bl_parse(unknown, strlen(unknown), &state) == VD_BL_OK);
    assert(state.requested_nits == -1 && state.actual_nits == -1);
    assert(vd_bl_percent(&state) == -1);
    const char *outside = "requested_nits=unknown\nactual_nits=900\nmin_nits=2\nmax_nits=400\npending=0\nonline=1\n";
    assert(vd_bl_parse(outside, strlen(outside), &state) == VD_BL_OK);
    assert(state.actual_nits == 900 && vd_bl_percent(&state) == 100);
    for (size_t n = 0; n < strlen(valid); ++n)
        assert(vd_bl_parse(valid, n, &state) == VD_BL_INVALID);
    reject("requested_nits=100\nactual_nits=99\nmin_nits=2\nmax_nits=400\npending=0\n");
    reject("requested_nits=100\nactual_nits=99\nmin_nits=2\nmax_nits=400\npending=0\nonline=1\nonline=1\n");
    reject("requested_nits=100\nactual_nits=99\nmin_nits=2\nmax_nits=400\npending=0\nonline=1\nextra=1\n");
    const char *bad[] = {"-1", "+1", " 2", "2 ", "", "2147483648", "unknown", "0", "401"};
    char buffer[256];
    for (size_t i = 0; i < sizeof(bad) / sizeof(bad[0]); ++i) {
        if (strcmp(bad[i], "unknown") == 0) continue;
        snprintf(buffer, sizeof(buffer), "requested_nits=%s\nactual_nits=99\nmin_nits=2\nmax_nits=400\npending=0\nonline=1\n", bad[i]);
        reject(buffer);
    }
    reject("requested_nits=100\nactual_nits=99\nmin_nits=2\nmax_nits=400\npending=2\nonline=1\n");
    reject("requested_nits=100\nactual_nits=99\nmin_nits=400\nmax_nits=2\npending=0\nonline=1\n");
    memcpy(buffer, valid, strlen(valid));
    buffer[3] = 0;
    assert(vd_bl_parse(buffer, strlen(valid), &state) == VD_BL_INVALID);
    assert(vd_bl_parse(NULL, 1, &state) == VD_BL_INVALID);
    assert(vd_bl_parse(valid, strlen(valid), NULL) == VD_BL_INVALID);
    puts("PASS strict snapshot parsing");
}
static void test_percent(void)
{
    VdBlState s = {-1, -1, 2, 400, 0, 1, 1};
    assert(vd_bl_percent_to_nits(&s, 0) == 2);
    assert(vd_bl_percent_to_nits(&s, 50) == 201);
    assert(vd_bl_percent_to_nits(&s, 100) == 400);
    assert(vd_bl_percent_to_nits(&s, -1) == -1);
    assert(vd_bl_percent_to_nits(&s, 101) == -1);
    for (int max = 2; max <= 509; ++max) {
        s.max_nits = max;
        int previous = 0;
        for (int percent = 0; percent <= 100; ++percent) {
            int nits = vd_bl_percent_to_nits(&s, percent);
            assert(nits >= 2 && nits <= max && nits >= previous);
            previous = nits;
            s.requested_nits = nits;
            assert(vd_bl_percent(&s) >= 0 && vd_bl_percent(&s) <= 100);
        }
    }
    s.max_nits = INT_MAX;
    s.requested_nits = vd_bl_percent_to_nits(&s, 50);
    assert(s.requested_nits > 1000000000 && vd_bl_percent(&s) == 50);
    assert(vd_bl_percent_to_nits(&s, 100) == INT_MAX);
    s = (VdBlState){100, 300, 2, 400, 1, 1, 1};
    assert(vd_bl_percent(&s) == 25); /* requested wins over old actual */
    s.requested_nits = -1;
    assert(vd_bl_percent(&s) == 75);
    s.actual_nits = 0;
    assert(vd_bl_percent(&s) == 0);
    puts("PASS percentage bounds, rounding and overflow");
}
static void test_read_only_actions(void)
{
    reset();
    VdBlState s;
    assert(vd_bl_read_state(&s) == VD_BL_OK);
    assert(opens == 1 && closes == 1 && reads == 1 && writes == 0);
    assert(s.writable && s.actual_nits == 99);
    reset(); rw_error = EACCES;
    assert(vd_bl_read_state(&s) == VD_BL_OK);
    assert(!s.writable && opens == 2 && closes == 1 && writes == 0);
    assert(vd_bl_set_percent(50) == VD_BL_PERMISSION && writes == 0 && live == 0);
    puts("PASS readback never writes and permission fallback");
}
static void test_failures(void)
{
    VdBlState s;
    int errors[] = {ENOENT, ENODEV, ENXIO, EACCES, EPERM, EIO};
    for (size_t i = 0; i < sizeof(errors) / sizeof(errors[0]); ++i) {
        reset(); open_error = errors[i];
        assert(vd_bl_read_state(&s) == vd_bl_errno_result(errors[i]));
        assert(vd_bl_set_percent(50) == vd_bl_errno_result(errors[i]));
        assert(writes == 0 && live == 0);
    }
    reset(); is_regular = 1;
    assert(vd_bl_set_percent(50) == VD_BL_INVALID && writes == 0 && reads == 0 && live == 0);
    reset(); stat_error = EIO;
    assert(vd_bl_read_state(&s) == VD_BL_IO && live == 0);
    reset(); read_error = EIO;
    assert(vd_bl_read_state(&s) == VD_BL_IO && live == 0);
    reset(); reply_length = 12;
    assert(vd_bl_set_percent(50) == VD_BL_INVALID && writes == 0 && reads == 1 && live == 0);
    reset(); set_reply("requested_nits=100\nactual_nits=99\nmin_nits=2\nmax_nits=400\npending=0\nonline=0\n");
    assert(vd_bl_set_percent(50) == VD_BL_OFFLINE && writes == 0 && live == 0);
    puts("PASS missing/offline/malformed/regular-file and I/O failures");
}
static void test_writes(void)
{
    reset();
    assert(vd_bl_set_percent(50) == VD_BL_OK);
    assert(strcmp(written_text, "201\n") == 0 && writes == 1 && live == 0);
    VdBlState s;
    assert(vd_bl_read_state(&s) == VD_BL_OK);
    assert(s.requested_nits == 100 && s.actual_nits == 99); /* no optimistic cache */
    reset();
    set_reply("requested_nits=100\nactual_nits=99\nmin_nits=10\nmax_nits=200\npending=1\nonline=1\n");
    assert(vd_bl_set_percent(50) == VD_BL_OK);
    assert(strcmp(written_text, "105\n") == 0); /* fresh, not cached bounds */
    reset(); short_write = 1;
    assert(vd_bl_set_percent(50) == VD_BL_IO && writes == 1 && live == 0);
    reset(); write_error = EIO;
    assert(vd_bl_set_percent(50) == VD_BL_IO && writes == 1 && live == 0);
    reset();
    assert(vd_bl_set_percent(-1) == VD_BL_INVALID && opens == 0);
    assert(vd_bl_set_percent(101) == VD_BL_INVALID && opens == 0);
    puts("PASS whole-command writes, fresh bounds, and no fabricated readback");
}
static void test_interrupts(void)
{
    VdBlState s;
    reset(); interrupted_reads = 2;
    assert(vd_bl_read_state(&s) == VD_BL_OK && reads == 3 && live == 0);
    reset(); interrupted_reads = 20;
    assert(vd_bl_read_state(&s) == VD_BL_IO && reads == VD_BL_RETRIES && live == 0);
    reset(); interrupted_writes = 2;
    assert(vd_bl_set_percent(50) == VD_BL_OK && writes == 3 && live == 0);
    reset(); interrupted_writes = 20;
    assert(vd_bl_set_percent(50) == VD_BL_IO && writes == VD_BL_RETRIES && live == 0);
    puts("PASS bounded EINTR handling");
}
static void test_driver_abi(void)
{
    void *storage = calloc(1, vinix_dcp_bl_state_size());
    assert(storage);
    struct vinix_dcp_bl *bl = storage;
    char text[VINIX_DCP_BL_TEXT_CAPACITY];
    VdBlState s;
    assert(vinix_dcp_bl_init(bl, VINIX_DCP_BL_LAYOUT_13_3, 400, 1000, 99000, 1) == 0);
    assert(vinix_dcp_bl_set_online(bl, 1) == 0);
    int n = vinix_dcp_bl_format(bl, text, sizeof(text));
    assert(n > 0 && vd_bl_parse(text, (size_t)n, &s) == VD_BL_OK);
    assert(s.actual_nits == 99 && s.requested_nits == -1);
    reset(); reply = text; reply_length = (size_t)n;
    assert(vd_bl_set_percent(75) == VD_BL_OK);
    assert(vinix_dcp_bl_write(bl, written_text, strlen(written_text)) == 0);
    n = vinix_dcp_bl_format(bl, text, sizeof(text));
    assert(n > 0 && vd_bl_parse(text, (size_t)n, &s) == VD_BL_OK);
    assert(s.pending == 1 && s.requested_nits == 301 && s.actual_nits == 99);
    assert(vinix_dcp_bl_set_online(bl, 0) == 0);
    n = vinix_dcp_bl_format(bl, text, sizeof(text));
    assert(n > 0 && vd_bl_parse(text, (size_t)n, &s) == VD_BL_OK);
    assert(s.online == 0 && s.actual_nits == -1);
    free(storage);
    puts("PASS round-trip with the actual kernel backlight core");
}
int main(void)
{
    test_parser(); test_percent(); test_read_only_actions(); test_failures();
    test_writes(); test_interrupts(); test_driver_abi();
    assert(live == 0);
    puts("All 7 desktop backlight client test groups passed.");
    return 0;
}
