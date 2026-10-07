/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_COLLECTOR_HOST_FIXTURE_NATIVE_ABI_H
#define VINIX_COLLECTOR_HOST_FIXTURE_NATIVE_ABI_H
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <limits.h>
#include <signal.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include "../../../tools/security-audit/collector_v.h"
_Static_assert(sizeof(int) == 4 && sizeof(uid_t) == 4, "original native status and owner words");
_Static_assert(sizeof(uint64_t) == 8 && sizeof(size_t) == 8 && sizeof(ssize_t) == 8 && sizeof(void *) == 8, "original LP64 buffers and records");
_Static_assert(sizeof(struct record) == 120 && _Alignof(struct record) == 8, "original audit record");
_Static_assert(sizeof(struct snapshot) == 15424 && _Alignof(struct snapshot) == 8 && offsetof(struct snapshot, records) == 64, "original snapshot storage");
_Static_assert(sizeof(struct collector) == 30848 && _Alignof(struct collector) == 8 && offsetof(struct collector, pending) == 112 && offsetof(struct collector, observed) == 15480, "original collector storage");
_Static_assert(sizeof(struct output) == 139272 && _Alignof(struct output) == 8 && offsetof(struct output, used) == OUTPUT_BYTES, "original output storage");
_Static_assert(CAPACITY == 128 && OUTPUT_BYTES == 139264, "original bounded arrays");
#if defined(__APPLE__)
_Static_assert(sizeof(mode_t) == 2 && __builtin_types_compatible_p(mode_t, unsigned short), "original Darwin fixed-argument mode type");
#else
_Static_assert(sizeof(mode_t) == 4 && __builtin_types_compatible_p(mode_t, unsigned int), "original musl fixed-argument mode type");
#endif
#endif
