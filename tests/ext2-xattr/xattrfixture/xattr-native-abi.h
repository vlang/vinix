/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native declarations and scalar/layout constraints; fixture operations are V. */
#ifndef VINIX_XATTR_FIXTURE_NATIVE_ABI_H
#define VINIX_XATTR_FIXTURE_NATIVE_ABI_H
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <sys/reboot.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/xattr.h>
#include <time.h>
#include <unistd.h>
typedef atomic_int vxattr_atomic_int;
struct vxattr_copy_race { int fds[64]; vxattr_atomic_int stop, failed, changes; };
void *vxattr_change_source_attributes(void *);
_Static_assert(sizeof(long) == 8 && __builtin_types_compatible_p(long, ptrdiff_t), "native scanner/report long");
_Static_assert(sizeof(size_t) == 8 && sizeof(ssize_t) == 8 && __builtin_types_compatible_p(ssize_t, ptrdiff_t), "native transfer/iteration widths");
_Static_assert(sizeof(int) == 4 && sizeof(pid_t) == 4 && sizeof(uid_t) == 4 && sizeof(gid_t) == 4, "native descriptor/process/ownership words");
_Static_assert(sizeof(struct timespec) == 16 && _Alignof(struct timespec) == 8 && offsetof(struct timespec, tv_nsec) == 8 && sizeof(((struct timespec *)0)->tv_sec) == 8, "native metadata time record");
_Static_assert(sizeof(((struct stat *)0)->st_uid) == 4 && sizeof(((struct stat *)0)->st_gid) == 4 && sizeof(((struct stat *)0)->st_mode) == 4 && sizeof(((struct stat *)0)->st_blocks) == 8, "native inode fields");
_Static_assert(sizeof(((struct statfs *)0)->f_type) == 8 && sizeof(((struct statfs *)0)->f_bfree) == 8 && sizeof(((struct statfs *)0)->f_ffree) == 8, "native filesystem counters");
_Static_assert(sizeof(vxattr_atomic_int) == 4 && _Alignof(vxattr_atomic_int) == 4 && ATOMIC_INT_LOCK_FREE == 2, "native seq-cst atomic words");
_Static_assert(sizeof(struct vxattr_copy_race) == 268 && _Alignof(struct vxattr_copy_race) == 4 && offsetof(struct vxattr_copy_race, stop) == 256 && offsetof(struct vxattr_copy_race, failed) == 260 && offsetof(struct vxattr_copy_race, changes) == 264, "shared stack race layout");
/* Original fixture-local helpers have internal linkage; definitions remain V-owned. */
struct xattrfixture__Heap;
static void *xattrfixture__change_source_attributes(void *);
static _Bool xattrfixture__check(_Bool, int32_t);
static int32_t xattrfixture__heap_snapshot(struct xattrfixture__Heap *);
static int32_t xattrfixture__operations(int32_t, int32_t);
static int32_t xattrfixture__metadata_operations(int32_t, int32_t);
static int32_t xattrfixture__metadata_measure(char *, char *);
static int32_t xattrfixture__copied_identity(char *);
static int32_t xattrfixture__exercise(char *, int32_t);
static int32_t xattrfixture__block_release(void);
static int32_t xattrfixture__concurrent_copy_up(char *, char *, char *);
#endif
