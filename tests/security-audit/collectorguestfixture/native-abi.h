/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_COLLECTOR_GUEST_FIXTURE_NATIVE_ABI_H
#define VINIX_COLLECTOR_GUEST_FIXTURE_NATIVE_ABI_H
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
#include <sys/mount.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <sched.h>
#include "../../../tools/security-audit/collector_v.h"
struct filter { uint16_t code; uint8_t jt, jf; uint32_t k; };
struct program { unsigned short length; struct filter *instructions; };
_Static_assert(sizeof(int) == 4 && sizeof(pid_t) == 4 && sizeof(uid_t) == 4, "original native status and owner words");
_Static_assert(sizeof(long) == 8 && sizeof(size_t) == 8 && sizeof(ssize_t) == 8 && sizeof(void *) == 8, "original LP64 syscall and buffer words");
_Static_assert(__builtin_types_compatible_p(int32_t, int) && __builtin_types_compatible_p(pid_t, int), "original process and default int variadic arguments");
_Static_assert(__builtin_types_compatible_p(int64_t, long) && __builtin_types_compatible_p(ssize_t, long), "original long syscall return and native read counts");
_Static_assert(sizeof(struct filter) == 8 && _Alignof(struct filter) == 4 && offsetof(struct filter, code) == 0 && offsetof(struct filter, jt) == 2 && offsetof(struct filter, jf) == 3 && offsetof(struct filter, k) == 4, "original BPF instructions");
_Static_assert(sizeof(struct program) == 16 && _Alignof(struct program) == 8 && offsetof(struct program, length) == 0 && offsetof(struct program, instructions) == 8, "original BPF program");
_Static_assert(CAPACITY == 128 && OUTPUT_BYTES == 139264 && sizeof(struct snapshot) == 15424, "original snapshot and output bounds");
_Static_assert(sizeof(mode_t) == 4 && __builtin_types_compatible_p(mode_t, unsigned int), "original musl fixed-argument mode type");
#if defined(__aarch64__)
_Static_assert(sizeof(struct stat) == 128 && offsetof(struct stat, st_size) == 48, "original ARM stat size");
#elif defined(__x86_64__)
_Static_assert(sizeof(struct stat) == 144 && offsetof(struct stat, st_size) == 48, "original x86 stat size");
#else
#error The collector guest supports the two original kernel LP64 architectures.
#endif
#endif
