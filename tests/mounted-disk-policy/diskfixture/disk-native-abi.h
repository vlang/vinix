/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native declarations and scalar constraints; fixture operations are V. */
#ifndef VINIX_MOUNTED_DISK_FIXTURE_NATIVE_ABI_H
#define VINIX_MOUNTED_DISK_FIXTURE_NATIVE_ABI_H
#define _GNU_SOURCE
#include <errno.h>
#include <dirent.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/uio.h>
#include <unistd.h>
typedef unsigned long long vdisk_ull;
typedef long long vdisk_ll;
_Static_assert(sizeof(long) == 8 && __builtin_types_compatible_p(long, ptrdiff_t), "native scanner/report long");
_Static_assert(sizeof(off_t) == 8 && __builtin_types_compatible_p(off_t, int64_t), "native offset outparameters");
_Static_assert(sizeof(size_t) == 8 && sizeof(ssize_t) == 8 && __builtin_types_compatible_p(ssize_t, ptrdiff_t), "native transfer words");
_Static_assert(sizeof(int) == 4 && sizeof(mode_t) == 4 && sizeof(dev_t) == 8 && (dev_t)-1 > 0, "descriptor/mode/device words");
_Static_assert(sizeof(vdisk_ull) == 8 && sizeof(vdisk_ll) == 8, "native variadic report words");
_Static_assert(sizeof(struct iovec) == 16 && _Alignof(struct iovec) == 8 && offsetof(struct iovec, iov_base) == 0 && offsetof(struct iovec, iov_len) == 8, "native borrowed transfer vector");
_Static_assert(sizeof(((struct stat *)0)->st_mode) == 4 && sizeof(((struct stat *)0)->st_rdev) == 8 && sizeof(((struct stat *)0)->st_size) == 8, "native device metadata fields");
_Static_assert(sizeof(struct statfs) == 120 && _Alignof(struct statfs) == 8 && offsetof(struct statfs, f_type) == 0 && sizeof(((struct statfs *)0)->f_type) == 8, "native filesystem magic storage");
_Static_assert(sizeof(DIR *) == 8 && sizeof(struct dirent) == 280 && _Alignof(struct dirent) == 8 && offsetof(struct dirent, d_name) == 19 && sizeof(((struct dirent *)0)->d_name) == 256, "native directory borrow/name storage");
#if defined(__aarch64__)
_Static_assert(sizeof(struct stat) == 128 && _Alignof(struct stat) == 8 && offsetof(struct stat, st_mode) == 16 && offsetof(struct stat, st_rdev) == 32 && offsetof(struct stat, st_size) == 48, "native ARM device metadata layout");
#elif defined(__x86_64__)
_Static_assert(sizeof(struct stat) == 144 && _Alignof(struct stat) == 8 && offsetof(struct stat, st_mode) == 24 && offsetof(struct stat, st_rdev) == 40 && offsetof(struct stat, st_size) == 48, "native x86 device metadata layout");
#endif
/* Original fixture-local routines and their V macro/scalar helpers stay private. */
static void diskfixture__check(_Bool, int32_t, char *);
static void diskfixture__level(int32_t);
static ptrdiff_t diskfixture__slab(void);
static void diskfixture__denied_open(char *);
static void diskfixture__denied_write(int32_t);
static void diskfixture__denied_transfer(int32_t, int32_t);
static vdisk_ull diskfixture__ull(uint64_t);
static vdisk_ll diskfixture__ll(int64_t);
#endif
