/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_SPARSE_FIXTURE_NATIVE_ABI_H
#define VINIX_SPARSE_FIXTURE_NATIVE_ABI_H
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <time.h>
#include <unistd.h>
typedef unsigned long long vsparse_ull;
typedef long long vsparse_ll;
struct vsparse_volatile_byte { volatile unsigned char value; };
_Static_assert(sizeof(struct vsparse_volatile_byte) == 1 && _Alignof(struct vsparse_volatile_byte) == 1 && offsetof(struct vsparse_volatile_byte, value) == 0, "native volatile byte view");
_Static_assert(sizeof(long) == 8 && __builtin_types_compatible_p(long, ptrdiff_t), "native scanner long");
_Static_assert(sizeof(off_t) == 8 && __builtin_types_compatible_p(off_t, int64_t), "native sparse offset");
_Static_assert(sizeof(vsparse_ull) == 8 && sizeof(vsparse_ll) == 8 && sizeof(size_t) == 8, "native report and transfer widths");
_Static_assert(sizeof(int) == 4, "native descriptor words");
#endif
