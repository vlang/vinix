/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_PAGECACHE_FIXTURE_NATIVE_ABI_H
#define VINIX_PAGECACHE_FIXTURE_NATIVE_ABI_H
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/statfs.h>
#include <unistd.h>
_Static_assert(sizeof(long) == 8 && __builtin_types_compatible_p(long, intptr_t) && __builtin_types_compatible_p(long, ptrdiff_t), "native scanner long");
_Static_assert(sizeof(off_t) == 8 && __builtin_types_compatible_p(off_t, int64_t), "native file offset");
_Static_assert(sizeof(size_t) == 8 && sizeof(ssize_t) == 8, "native transfer counts");
_Static_assert(sizeof(int) == 4, "native descriptor and advice words");
#endif
