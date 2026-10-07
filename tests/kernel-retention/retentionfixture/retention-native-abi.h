/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_RETENTION_FIXTURE_NATIVE_ABI_H
#define VINIX_RETENTION_FIXTURE_NATIVE_ABI_H
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>
typedef struct {
    uint64_t ino;
    int64_t offset;
    uint16_t length;
    uint8_t type;
    char name[];
} vret_dirent64;
_Static_assert(offsetof(vret_dirent64, length) == 16 && offsetof(vret_dirent64, name) == 19, "native directory record offsets");
_Static_assert(sizeof(long) == 8 && __builtin_types_compatible_p(long, intptr_t) && __builtin_types_compatible_p(long, ptrdiff_t), "native long scanner and syscall width");
_Static_assert(sizeof(unsigned) == 4 && sizeof(int) == 4, "native fixture integer width");
#endif
