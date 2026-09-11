/* SPDX-License-Identifier: GPL-2.0-or-later
 * Small libc compatibility declarations required by current V3 vlib. */
#ifndef VINIX_DESKTOP_LIBC_COMPAT_H
#define VINIX_DESKTOP_LIBC_COMPAT_H

#include <pthread.h>
#include <stdint.h>

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

/* The native surface producer and compositor share two aligned uint32_t
 * ownership fields. Keep the atomic operations in C so V does not have to
 * depend on compiler-specific atomic builtins directly. The claim retries if
 * publication raced it; after two matching active-buffer reads the producer
 * will observe the claim before it can reuse that buffer. */
static inline uint32_t vinix_surface_claim_reader(
    const uint32_t *active_buffer, uint32_t *reader_buffer) {
    for (;;) {
        uint32_t active = __atomic_load_n(active_buffer, __ATOMIC_ACQUIRE);
        __atomic_store_n(reader_buffer, active, __ATOMIC_RELEASE);
        /* If the producer published between our load and claim, move the
         * claim to the new active buffer before exposing any pixels. Once the
         * two reads agree, the producer must choose the other buffer. */
        if (__atomic_load_n(active_buffer, __ATOMIC_ACQUIRE) == active) {
            return active;
        }
    }
}

static inline void vinix_surface_release_reader(uint32_t *reader_buffer) {
    __atomic_store_n(reader_buffer, UINT32_MAX, __ATOMIC_RELEASE);
}

#endif
