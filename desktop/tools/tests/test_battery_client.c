/* SPDX-License-Identifier: GPL-2.0-or-later */
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include "apple_smc.h"

static int mock_open(const char *, int);
static ssize_t mock_read(int, void *, size_t);
static int mock_close(int);
#define VD_BATTERY_OPEN mock_open
#define VD_BATTERY_READ mock_read
#define VD_BATTERY_CLOSE mock_close
#include "battery_client.h"

static struct {
    const char *text;
    size_t length, offset, chunk;
    int open_error, read_error, close_error;
    unsigned open_interrupts, read_interrupts, opens, reads, closes;
} io;

static void reset(const char *text, size_t length)
{
    memset(&io, 0, sizeof(io));
    io.text = text;
    io.length = length;
    io.chunk = 5;
}

static int mock_open(const char *path, int flags)
{
    assert(strcmp(path, "/dev/battery") == 0);
    assert((flags & O_ACCMODE) == O_RDONLY);
    assert((flags & O_NONBLOCK) && (flags & O_CLOEXEC));
    ++io.opens;
    if (io.open_interrupts) {
        --io.open_interrupts;
        errno = EINTR;
        return -1;
    }
    if (io.open_error) {
        errno = io.open_error;
        return -1;
    }
    return 42;
}

static ssize_t mock_read(int fd, void *buffer, size_t length)
{
    assert(fd == 42 && length > 0);
    ++io.reads;
    if (io.read_interrupts) {
        --io.read_interrupts;
        errno = EINTR;
        return -1;
    }
    if (io.read_error) {
        errno = io.read_error;
        return -1;
    }
    size_t count = io.length - io.offset;
    if (count > length) count = length;
    if (count > io.chunk) count = io.chunk;
    if (count) memcpy(buffer, io.text + io.offset, count);
    io.offset += count;
    return (ssize_t)count;
}

static int mock_close(int fd)
{
    assert(fd == 42);
    ++io.closes;
    if (io.close_error) {
        errno = io.close_error;
        return -1;
    }
    return 0;
}

static void test_kernel_format_roundtrip(void)
{
    for (int percent = 0; percent <= 100; ++percent) {
        uint8_t bytes[4];
        int length = vinix_smc_format_capacity(percent, bytes);
        assert(length >= 2 && length <= 4);
        assert(vd_battery_parse((const char *)bytes, (size_t)length) == percent);
        reset((const char *)bytes, (size_t)length);
        assert(vd_battery_read_percent() == percent);
        assert(io.opens == 1 && io.closes == 1);
    }
}

static void test_invalid_text(void)
{
    const char *bad[] = {"", "\n", "0", "100", "101\n", "999\n", "1000\n",
        "-1\n", "+1\n", " 1\n", "1 \n", "1%\n", "1\r\n", "1\n2\n", "1.0\n"};
    for (size_t i = 0; i < sizeof(bad) / sizeof(bad[0]); ++i) {
        assert(vd_battery_parse(bad[i], strlen(bad[i])) == VD_BATTERY_INVALID);
        reset(bad[i], strlen(bad[i]));
        assert(vd_battery_read_percent() == VD_BATTERY_INVALID);
        assert(io.closes == 1);
    }
    const char embedded_nul[] = {'1', 0, '\n'};
    assert(vd_battery_parse(embedded_nul, sizeof(embedded_nul)) == VD_BATTERY_INVALID);
    assert(vd_battery_parse(NULL, 2) == VD_BATTERY_INVALID);
}

static void test_short_reads_and_reopen(void)
{
    reset("100\n", 4); io.chunk = 1;
    assert(vd_battery_read_percent() == 100 && io.reads == 5 && io.closes == 1);
    reset("0\n", 2); io.chunk = 1;
    assert(vd_battery_read_percent() == 0 && io.opens == 1 && io.closes == 1);
}

static void test_open_and_read_errors(void)
{
    const int errors[] = {ENOENT, ENODEV, ENXIO, EACCES, EPERM, EIO, EAGAIN};
    const int expected[] = {VD_BATTERY_UNAVAILABLE, VD_BATTERY_UNAVAILABLE,
        VD_BATTERY_UNAVAILABLE, VD_BATTERY_PERMISSION, VD_BATTERY_PERMISSION,
        VD_BATTERY_IO, VD_BATTERY_IO};
    for (size_t i = 0; i < sizeof(errors) / sizeof(errors[0]); ++i) {
        reset("73\n", 3); io.open_error = errors[i];
        assert(vd_battery_read_percent() == expected[i]);
        assert(io.closes == 0 && io.reads == 0);
        reset("73\n", 3); io.read_error = errors[i];
        assert(vd_battery_read_percent() == expected[i]);
        assert(io.closes == 1);
    }
}

static void test_interrupted_operations_are_bounded(void)
{
    reset("73\n", 3); io.open_interrupts = 2; io.read_interrupts = 3; io.chunk = 1;
    assert(vd_battery_read_percent() == 73 && io.opens == 3 && io.closes == 1);
    reset("73\n", 3); io.open_interrupts = 100;
    assert(vd_battery_read_percent() == VD_BATTERY_IO && io.opens == 16 && io.closes == 0);
    reset("73\n", 3); io.read_interrupts = 100;
    assert(vd_battery_read_percent() == VD_BATTERY_IO && io.reads == 32 && io.closes == 1);
}

static void test_excess_input_and_close_failure(void)
{
    reset("100\ntrailing data", 17);
    assert(vd_battery_read_percent() == VD_BATTERY_INVALID);
    assert(io.offset == 5 && io.closes == 1);
    reset("73\n", 3); io.close_error = EINTR;
    assert(vd_battery_read_percent() == VD_BATTERY_IO && io.closes == 1);
}

static unsigned samples;
static int sample_value;
static int sample(void) { ++samples; return sample_value; }

static void test_shared_cache_and_forced_refresh(void)
{
    VdBatteryCache cache = {0, 0, 0}; samples = 0; sample_value = 73;
    assert(vd_battery_poll_cache(&cache, 0, 0, sample) == 73 && samples == 1);
    sample_value = 72;
    for (uint64_t now = 1; now < 5000; ++now)
        assert(vd_battery_poll_cache(&cache, now, 0, sample) == 73);
    assert(samples == 1);
    assert(vd_battery_poll_cache(&cache, 5000, 0, sample) == 72 && samples == 2);
    sample_value = 71;
    assert(vd_battery_poll_cache(&cache, 5001, 1, sample) == 71 && samples == 3);
    assert(vd_battery_poll_cache(&cache, 5001, 0, sample) == 71 && samples == 3);
}

static void test_cache_discards_failed_sample_and_recovers(void)
{
    VdBatteryCache cache = {0, 0, 0}; samples = 0; sample_value = 73;
    assert(vd_battery_poll_cache(&cache, 100, 0, sample) == 73);
    sample_value = VD_BATTERY_IO;
    assert(vd_battery_poll_cache(&cache, 5100, 0, sample) == VD_BATTERY_IO);
    assert(vd_battery_poll_cache(&cache, 5101, 0, sample) == VD_BATTERY_IO && samples == 2);
    sample_value = 0;
    assert(vd_battery_poll_cache(&cache, 10100, 0, sample) == 0);
    sample_value = 101;
    assert(vd_battery_poll_cache(&cache, 10101, 1, sample) == VD_BATTERY_INVALID);
    sample_value = -100;
    assert(vd_battery_poll_cache(&cache, 10102, 1, sample) == VD_BATTERY_INVALID);
}

static void test_cache_clock_failure_and_rollback(void)
{
    VdBatteryCache cache = {0, 0, 0}; samples = 0; sample_value = 100;
    assert(vd_battery_poll_cache(&cache, 10000, 0, sample) == 100);
    sample_value = 99;
    assert(vd_battery_poll_cache(&cache, 1, 0, sample) == 99 && samples == 2);
    assert(vd_battery_poll_cache(&cache, UINT64_MAX, 0, sample) == VD_BATTERY_IO);
    assert(samples == 2);
    sample_value = 98;
    assert(vd_battery_poll_cache(&cache, 2, 0, sample) == 98 && samples == 3);
}

#define RUN(test) do { test(); ++count; puts("PASS " #test); } while (0)
int main(void)
{
    unsigned count = 0;
    RUN(test_kernel_format_roundtrip);
    RUN(test_invalid_text);
    RUN(test_short_reads_and_reopen);
    RUN(test_open_and_read_errors);
    RUN(test_interrupted_operations_are_bounded);
    RUN(test_excess_input_and_close_failure);
    RUN(test_shared_cache_and_forced_refresh);
    RUN(test_cache_discards_failed_sample_and_recovers);
    RUN(test_cache_clock_failure_and_rollback);
    printf("%u battery client test groups passed\n", count);
    return 0;
}
