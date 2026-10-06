#ifndef VINIX_STAT_BUFFER_NATIVE_ABI_H
#define VINIX_STAT_BUFFER_NATIVE_ABI_H
#ifndef _GNU_SOURCE
#define _GNU_SOURCE 1
#endif
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

/* Original native scanf/printf integer types, with no implementation bodies. */
struct stat_guest_snapshot {
    unsigned count;
    unsigned long long size[32], live[32], pages[32], large, uaf;
    long free, slab, cached;
};
struct stat_guest_scan { unsigned long long label, size, live, pages; };
struct stat_guest_long { long value; };
struct stat_guest_delta { long long objects, pages, large; };
_Static_assert(sizeof(struct stat_guest_snapshot) == 816, "original snapshot ABI");
_Static_assert(sizeof(long) == 8 && sizeof(unsigned long long) == 8, "native LP64 scans");
#endif
