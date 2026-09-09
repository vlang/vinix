/* SPDX-License-Identifier: GPL-2.0-or-later
 * Small libc compatibility declarations required by current V3 vlib. */
#ifndef VINIX_DESKTOP_LIBC_COMPAT_H
#define VINIX_DESKTOP_LIBC_COMPAT_H

#include <pthread.h>

/* musl and mlibc implement POSIX rwlocks but omit glibc's non-portable
 * writer-preference attribute used by V3's closure runtime. Ignoring that
 * optional preference retains the required POSIX locking semantics. */
#if defined(__linux__) && !defined(__GLIBC__) && \
    !defined(PTHREAD_RWLOCK_PREFER_WRITER_NONRECURSIVE_NP)
#define PTHREAD_RWLOCK_PREFER_WRITER_NONRECURSIVE_NP 0
static inline int pthread_rwlockattr_setkind_np(
    pthread_rwlockattr_t *attribute, int kind) {
    (void)attribute;
    (void)kind;
    return 0;
}
#endif

#endif
