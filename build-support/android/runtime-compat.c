// SPDX-License-Identifier: GPL-2.0-or-later
// musl discovers the initial thread's stack with 4 KiB mremap probes. QEMU
// forwards those probes to Vinix, whose native mappings use 16 KiB pages.
// Read QEMU's target /proc/self/maps instead: it describes the actual mapped
// x86 stack. This library is preloaded only into the private Android runtime.
// QEMU also discards x86 MAP_32BIT on ARM. Honor that flag using genuine low
// target mappings, which ART requires for its compressed object references.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>

#ifndef MAP_FIXED_NOREPLACE
#define MAP_FIXED_NOREPLACE 0x100000
#endif

// Align hints to both the target's 4 KiB and Vinix's native 16 KiB pages.
#define LOW_MAP_ALIGNMENT UINT64_C(16384)
#define LOW_MAP_BEGIN UINT64_C(0x10000)
#define LOW_MAP_END UINT64_C(0x80000000)

static pthread_t initial_thread;
static uintptr_t initial_stack_anchor;
static int (*next_pthread_getattr_np)(pthread_t, pthread_attr_t *);
static void *(*next_mmap)(void *, size_t, int, int, int, off_t);
static int (*next_munmap)(void *, size_t);
static pthread_once_t mapping_symbols_once = PTHREAD_ONCE_INIT;
static pthread_mutex_t low_mapping_lock = PTHREAD_MUTEX_INITIALIZER;
static uintptr_t low_mapping_cursor = UINT64_C(0x10000000);

static void prepare_low_mapping_fork(void)
{
    pthread_mutex_lock(&low_mapping_lock);
}

static void release_low_mapping_fork(void)
{
    pthread_mutex_unlock(&low_mapping_lock);
}

static void resolve_mapping_symbols(void)
{
    next_mmap = dlsym(RTLD_NEXT, "mmap");
    next_munmap = dlsym(RTLD_NEXT, "munmap");
}

__attribute__((constructor)) static void initialize_stack_compat(void)
{
    initial_thread = pthread_self();
    // Keep an address inside the initial stack for queries from other threads.
    // Only its numeric value is used after this constructor returns.
    uintptr_t stack_local;
    initial_stack_anchor = (uintptr_t)&stack_local;
    next_pthread_getattr_np = dlsym(RTLD_NEXT, "pthread_getattr_np");
    pthread_once(&mapping_symbols_once, resolve_mapping_symbols);
    // Fork from a different thread must not leave the child holding a mutex
    // whose owner exists only in the parent process.
    pthread_atfork(prepare_low_mapping_fork, release_low_mapping_fork, release_low_mapping_fork);
}

static uintptr_t align_low_hint(uintptr_t address)
{
    return (address + LOW_MAP_ALIGNMENT - 1) & ~(LOW_MAP_ALIGNMENT - 1);
}

// QEMU supplies sorted target mappings, including mapped PROT_NONE ranges.
// Checking all of them avoids treating a reserved ART arena as a free hole.
static int find_low_hint(uintptr_t start, size_t span, uintptr_t *hint)
{
    FILE *maps = fopen("/proc/self/maps", "r");
    if (maps == NULL) {
        return errno;
    }
    uintptr_t candidate = align_low_hint(start);
    char *line = NULL;
    size_t capacity = 0;
    while (getline(&line, &capacity, maps) >= 0) {
        unsigned long begin, end;
        if (sscanf(line, "%lx-%lx", &begin, &end) != 2 || end <= candidate) {
            continue;
        }
        if (candidate > LOW_MAP_END - span || begin >= candidate + span) {
            break;
        }
        candidate = align_low_hint(end);
    }
    int result = ferror(maps) ? EIO : 0;
    free(line);
    fclose(maps);
    if (result == 0 && (candidate < LOW_MAP_BEGIN || candidate > LOW_MAP_END - span)) {
        result = ENOMEM;
    }
    if (result == 0) {
        *hint = candidate;
    }
    return result;
}

void *mmap(void *address, size_t length, int protection, int flags, int fd, off_t offset)
{
    pthread_once(&mapping_symbols_once, resolve_mapping_symbols);
    if (next_mmap == NULL || next_munmap == NULL) {
        errno = ENOSYS;
        return MAP_FAILED;
    }
    // MAP_32BIT has no effect for fixed mappings. Preserve every other mmap
    // request, including fixed reservations and the caller's file offset.
    if ((flags & MAP_32BIT) == 0 || (flags & (MAP_FIXED | MAP_FIXED_NOREPLACE)) != 0
        || length == 0 || offset < 0 || offset % 4096 != 0) {
        return next_mmap(address, length, protection, flags, fd, offset);
    }
    if (length > LOW_MAP_END - LOW_MAP_BEGIN) {
        errno = ENOMEM;
        return MAP_FAILED;
    }
    size_t span = align_low_hint(length);
    if (span > LOW_MAP_END - LOW_MAP_BEGIN) {
        errno = ENOMEM;
        return MAP_FAILED;
    }

    int saved_errno = errno;
    int previous_cancel_state;
    // mmap itself is not a cancellation point. Reading maps must not turn it
    // into one while the allocator owns its mutex and temporary FILE/buffer.
    int error = pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &previous_cancel_state);
    if (error != 0) {
        errno = error;
        return MAP_FAILED;
    }
    error = pthread_mutex_lock(&low_mapping_lock);
    if (error != 0) {
        pthread_setcancelstate(previous_cancel_state, NULL);
        errno = error;
        return MAP_FAILED;
    }
    uintptr_t start = low_mapping_cursor;
    if ((uintptr_t)address >= LOW_MAP_BEGIN && (uintptr_t)address <= LOW_MAP_END - span) {
        start = (uintptr_t)address & ~(LOW_MAP_ALIGNMENT - 1);
    }
    void *mapping = MAP_FAILED;
    int wrapped = 0;
    error = ENOMEM;
    for (unsigned attempt = 0; attempt < 128; ++attempt) {
        uintptr_t hint = 0;
        error = find_low_hint(start, span, &hint);
        if (error == ENOMEM && !wrapped && start != LOW_MAP_BEGIN) {
            start = LOW_MAP_BEGIN;
            wrapped = 1;
            continue;
        }
        if (error != 0) {
            break;
        }
        // This is deliberately a hint, without MAP_FIXED: another thread can
        // occupy the hole after maps is read, and mmap must not replace it.
        // QEMU's partial-host-page MAP_FIXED_NOREPLACE path does not provide
        // the same guarantee, so verify the actual nonfixed result instead.
        mapping = next_mmap((void *)hint, length, protection, flags & ~MAP_32BIT, fd, offset);
        if (mapping == MAP_FAILED) {
            error = errno;
            break;
        }
        uintptr_t actual = (uintptr_t)mapping;
        if (actual >= LOW_MAP_BEGIN && actual <= LOW_MAP_END - span) {
            low_mapping_cursor = align_low_hint(actual + span);
            if (low_mapping_cursor >= LOW_MAP_END) {
                low_mapping_cursor = LOW_MAP_BEGIN;
            }
            error = 0;
            break;
        }
        // A kernel may ignore the hint. Reject and release a high mapping
        // rather than returning an address ART would truncate to 32 bits.
        if (next_munmap(mapping, length) != 0) {
            error = errno;
            mapping = MAP_FAILED;
            break;
        }
        mapping = MAP_FAILED;
        start = hint + LOW_MAP_ALIGNMENT;
        error = ENOMEM;
    }
    pthread_mutex_unlock(&low_mapping_lock);
    pthread_setcancelstate(previous_cancel_state, NULL);
    errno = error == 0 ? saved_errno : error;
    return mapping;
}

// musl names mmap64 as a source alias. Export the ELF name as well for JNI
// libraries built with other libc headers; x86-64 off_t already has 64 bits.
#ifdef mmap64
#undef mmap64
#endif
void *mmap64(void *address, size_t length, int protection, int flags, int fd, off_t offset)
{
    return mmap(address, length, protection, flags, fd, offset);
}

static int mapped_stack_bounds(uintptr_t anchor, uintptr_t *base, size_t *size)
{
    FILE *maps = fopen("/proc/self/maps", "r");
    if (maps == NULL) {
        return errno;
    }
    char *line = NULL;
    size_t capacity = 0;
    int result = ENOENT;
    while (getline(&line, &capacity, maps) >= 0) {
        unsigned long begin, end;
        char permissions[5];
        if (sscanf(line, "%lx-%lx %4s", &begin, &end, permissions) != 3) {
            continue;
        }
        if (begin <= anchor && anchor < end && permissions[0] == 'r'
            && permissions[1] == 'w') {
            *base = begin;
            *size = end - begin;
            result = 0;
            break;
        }
    }
    free(line);
    fclose(maps);
    return result;
}

int pthread_getattr_np(pthread_t thread, pthread_attr_t *attributes)
{
    if (next_pthread_getattr_np == NULL) {
        return ENOSYS;
    }
    if (!pthread_equal(thread, initial_thread)) {
        return next_pthread_getattr_np(thread, attributes);
    }

    int saved_errno = errno;
    int result = next_pthread_getattr_np(thread, attributes);
    if (result != 0) {
        errno = saved_errno;
        return result;
    }
    // Preserve musl's detach state and every other reported attribute. Its
    // initial-stack probe returns successfully with a one-page size on Vinix;
    // only the stack bounds need to come from QEMU's mapped target ranges.
    uintptr_t base = 0;
    size_t size = 0;
    result = mapped_stack_bounds(initial_stack_anchor, &base, &size);
    if (result == 0) {
        result = pthread_attr_setstack(attributes, (void *)base, size);
        if (result == 0) {
            // QEMU's mapped initial stack has no pthread-created guard.
            result = pthread_attr_setguardsize(attributes, 0);
        }
    }
    if (result != 0) {
        pthread_attr_destroy(attributes);
    }
    errno = saved_errno;
    return result;
}
