// SPDX-License-Identifier: GPL-2.0-or-later
// Vinix reserves room for the main stack to grow beyond its current limit.
// Report its mapped bounds and usable finite limit to the private ARM runtime.
// The legacy x86 runtime also needs mapped bounds because its musl uses 4 KiB
// mremap probes on Vinix's 16 KiB ARM mappings. Its QEMU host discards x86
// MAP_32BIT, so honor that flag with genuine low target mappings for ART's
// compressed references. Native ARM ART already uses its own low allocator.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <unistd.h>

#if defined(__aarch64__) && defined(__linux__)
#include <stdio_ext.h>
#include "musl-statistics.h"

// ART's external diagnostic utilities inherit this preload while using the
// host libc. They do not call the Android allocator API. Only that API requires
// the private provider; never fabricate statistics if a caller lacks it.
extern int __vinix_malloc_stats(struct vinix_malloc_stats *, size_t)
    __attribute__((weak));

// Bionic's LP64 mallinfo uses size_t fields, unlike glibc's legacy int ABI.
// These values describe the real private mallocng allocator. Its allocation
// groups use mmap; separately guarded allocator metadata is not user storage.
struct android_mallinfo {
    size_t arena, ordblks, smblks, hblks, hblkhd;
    size_t usmblks, fsmblks, uordblks, fordblks, keepcost;
};
_Static_assert(sizeof(struct android_mallinfo) == 80, "Bionic ARM64 mallinfo ABI");

struct android_mallinfo bionic_mallinfo(void)
{
    struct vinix_malloc_stats statistics;
    if (__vinix_malloc_stats == NULL ||
        __vinix_malloc_stats(&statistics, sizeof(statistics)) != 0) {
        fputs("Android allocator statistics ABI mismatch\n", stderr);
        abort();
    }
    return (struct android_mallinfo){
        .ordblks = statistics.free_blocks,
        .hblks = statistics.mapped_blocks,
        .hblkhd = statistics.mapped_bytes,
        .usmblks = statistics.peak_mapped_bytes,
        .uordblks = statistics.live_bytes,
        .fordblks = statistics.free_bytes,
    };
}

// The Bionic linker prefers bionic_ names for Android relocations. These
// checks keep the NDK calling conventions while doing the actual I/O through
// the private musl runtime; native Linux callers retain their libc symbols.
__attribute__((noreturn))
static void android_buffer_overflow(const char *function, const char *action,
                                    size_t requested, size_t available)
{
    fprintf(stderr, "FORTIFY: %s: prevented %zu-byte %s %zu-byte buffer\n",
            function, requested, action, available);
    abort();
}

__attribute__((noreturn))
void bionic___assert(const char *file, int line, const char *expression)
{
    fprintf(stderr, "%s:%d: assertion \"%s\" failed\n", file, line, expression);
    abort();
}

static FILE *android_host_stream(FILE *stream)
{
    // Pinned bionic_translation's LP64 libc-stdio.h exposes three opaque
    // 152-byte __sF entries for the standard streams. Every other FILE comes
    // directly from musl. Resolve the facade at use time, since the Bionic
    // library may be loaded after this preload library's constructor.
    int saved_errno = errno;
    const unsigned char *standard = dlsym(RTLD_DEFAULT, "bionic___sF");
    errno = saved_errno;
    if (standard != NULL) {
        if ((void *)stream == (void *)standard) return stdin;
        if ((void *)stream == (void *)(standard + 152)) return stdout;
        if ((void *)stream == (void *)(standard + 304)) return stderr;
    }
    return stream;
}

size_t bionic___fread_chk(void *buffer, size_t size, size_t count, FILE *stream,
                         size_t buffer_size)
{
    size_t total;
    if (__builtin_mul_overflow(size, count, &total)) {
        // Bionic fread reports EOVERFLOW and marks the stream on overflow.
        // musl fread multiplies unchecked, so do not delegate this case.
        FILE *host_stream = android_host_stream(stream);
        flockfile(host_stream);
        __fseterr(host_stream);
        funlockfile(host_stream);
        errno = EOVERFLOW;
        return 0;
    }
    if (total > buffer_size) {
        android_buffer_overflow("fread", "write into", total, buffer_size);
    }
    return fread(buffer, size, count, android_host_stream(stream));
}

ssize_t bionic___readlink_chk(const char *path, char *buffer, size_t size,
                             size_t buffer_size)
{
    if (size > SSIZE_MAX) {
        fprintf(stderr, "FORTIFY: readlink: size %zu > SSIZE_MAX\n", size);
        abort();
    }
    if (size > buffer_size) {
        android_buffer_overflow("readlink", "write into", size, buffer_size);
    }
    return readlink(path, buffer, size);
}

ssize_t bionic___sendto_chk(int socket, const void *buffer, size_t size,
                           size_t buffer_size, int flags,
                           const struct sockaddr *address, socklen_t address_size)
{
    if (size > buffer_size) {
        android_buffer_overflow("sendto", "read from", size, buffer_size);
    }
    return sendto(socket, buffer, size, flags, address, address_size);
}

size_t bionic___strlcpy_chk(char *destination, const char *source, size_t size,
                           size_t destination_size)
{
    // AOSP fortify.cpp checks the supplied bound before calling strlcpy.
    // The real copy retains its source-length return value and truncation.
    if (size > destination_size) {
        android_buffer_overflow("strlcpy", "write into", size, destination_size);
    }
    return strlcpy(destination, source, size);
}
#endif

static pthread_t initial_thread;
static uintptr_t initial_stack_anchor;
static int (*next_pthread_getattr_np)(pthread_t, pthread_attr_t *);

#if defined(__aarch64__)
// Android's four-argument registration associates callbacks with the DSO's
// __cxa_finalize handle. musl has no atfork unregister operation. One fixed
// thunk per registration lets the host preserve ordering with its own ART
// callbacks while finalized DSOs leave inert thunks. Registered slots cannot
// be reused; exhausting this bounded table returns ENOMEM.
#define ANDROID_FORK_SLOTS(M) \
    M(0) M(1) M(2) M(3) M(4) M(5) M(6) M(7) \
    M(8) M(9) M(10) M(11) M(12) M(13) M(14) M(15) \
    M(16) M(17) M(18) M(19) M(20) M(21) M(22) M(23) \
    M(24) M(25) M(26) M(27) M(28) M(29) M(30) M(31) \
    M(32) M(33) M(34) M(35) M(36) M(37) M(38) M(39) \
    M(40) M(41) M(42) M(43) M(44) M(45) M(46) M(47) \
    M(48) M(49) M(50) M(51) M(52) M(53) M(54) M(55) \
    M(56) M(57) M(58) M(59) M(60) M(61) M(62) M(63) \
    M(64) M(65) M(66) M(67) M(68) M(69) M(70) M(71) \
    M(72) M(73) M(74) M(75) M(76) M(77) M(78) M(79) \
    M(80) M(81) M(82) M(83) M(84) M(85) M(86) M(87) \
    M(88) M(89) M(90) M(91) M(92) M(93) M(94) M(95) \
    M(96) M(97) M(98) M(99) M(100) M(101) M(102) M(103) \
    M(104) M(105) M(106) M(107) M(108) M(109) M(110) M(111) \
    M(112) M(113) M(114) M(115) M(116) M(117) M(118) M(119) \
    M(120) M(121) M(122) M(123) M(124) M(125) M(126) M(127)

struct android_fork_handler {
    pthread_mutex_t lock;
    void (*prepare)(void);
    void (*parent)(void);
    void (*child)(void);
    void *dso;
    unsigned used;
};

#define ANDROID_FORK_INITIALIZER(index) { .lock = PTHREAD_MUTEX_INITIALIZER },
static struct android_fork_handler android_fork_handlers[] = {
    ANDROID_FORK_SLOTS(ANDROID_FORK_INITIALIZER)
};
#undef ANDROID_FORK_INITIALIZER
static pthread_mutex_t android_fork_registration_lock = PTHREAD_MUTEX_INITIALIZER;
static int android_fork_guard_error;

static void prepare_android_fork_registry(void)
{
    pthread_mutex_lock(&android_fork_registration_lock);
}

static void release_android_fork_registry(void)
{
    pthread_mutex_unlock(&android_fork_registration_lock);
}

static void android_fork_prepare(unsigned index)
{
    struct android_fork_handler *handler = &android_fork_handlers[index];
    // Keep each slot locked until its parent/child callback finishes so a
    // concurrent DSO finalizer cannot unload a callback being executed.
    pthread_mutex_lock(&handler->lock);
    if (handler->prepare != NULL) {
        handler->prepare();
    }
}

static void android_fork_finish(unsigned index, int child)
{
    struct android_fork_handler *handler = &android_fork_handlers[index];
    void (*callback)(void) = child ? handler->child : handler->parent;
    if (callback != NULL) {
        callback();
    }
    pthread_mutex_unlock(&handler->lock);
}

#define ANDROID_FORK_THUNKS(index) \
    static void android_prepare_##index(void) { android_fork_prepare(index); } \
    static void android_parent_##index(void) { android_fork_finish(index, 0); } \
    static void android_child_##index(void) { android_fork_finish(index, 1); }
ANDROID_FORK_SLOTS(ANDROID_FORK_THUNKS)
#undef ANDROID_FORK_THUNKS
#define ANDROID_FORK_FUNCTIONS(index) \
    { android_prepare_##index, android_parent_##index, android_child_##index },
static void (*const android_fork_thunks[][3])(void) = {
    ANDROID_FORK_SLOTS(ANDROID_FORK_FUNCTIONS)
};
#undef ANDROID_FORK_FUNCTIONS
#undef ANDROID_FORK_SLOTS

int bionic___register_atfork(void (*prepare)(void), void (*parent)(void),
                            void (*child)(void), void *dso)
{
    if (android_fork_guard_error != 0) {
        return android_fork_guard_error;
    }
    const unsigned count = sizeof(android_fork_handlers) / sizeof(android_fork_handlers[0]);
    pthread_mutex_lock(&android_fork_registration_lock);
    unsigned index;
    for (index = 0; index < count && android_fork_handlers[index].used; ++index) {}
    if (index == count) {
        pthread_mutex_unlock(&android_fork_registration_lock);
        return ENOMEM;
    }
    struct android_fork_handler *handler = &android_fork_handlers[index];
    handler->used = 1;
    pthread_mutex_lock(&handler->lock);
    handler->prepare = prepare;
    handler->parent = parent;
    handler->child = child;
    handler->dso = dso;
    pthread_mutex_unlock(&handler->lock);
    pthread_mutex_unlock(&android_fork_registration_lock);

    // The host also locks its atfork list. Hold neither registry lock while
    // registering, since a concurrent fork can already be inside our thunk.
    int result = pthread_atfork(android_fork_thunks[index][0],
                               android_fork_thunks[index][1], android_fork_thunks[index][2]);
    if (result != 0) {
        // No host callback references a failed registration, so this slot can
        // be reused. Successful registrations stay reserved after finalizing.
        pthread_mutex_lock(&android_fork_registration_lock);
        pthread_mutex_lock(&handler->lock);
        handler->prepare = handler->parent = handler->child = NULL;
        handler->dso = NULL;
        handler->used = 0;
        pthread_mutex_unlock(&handler->lock);
        pthread_mutex_unlock(&android_fork_registration_lock);
    }
    return result;
}

int bionic_pthread_atfork(void (*prepare)(void), void (*parent)(void), void (*child)(void))
{
    return bionic___register_atfork(prepare, parent, child, NULL);
}

void bionic___cxa_finalize(void *dso)
{
    extern void __cxa_finalize(void *);
    if (android_fork_guard_error != 0) {
        // No Android registration can have succeeded without the fork guard.
        __cxa_finalize(dso);
        return;
    }
    for (unsigned index = 0; index < sizeof(android_fork_handlers) / sizeof(android_fork_handlers[0]); ++index) {
        struct android_fork_handler *handler = &android_fork_handlers[index];
        // Unpublished slots need the registry guard across their critical
        // section, since they have no prepare/child thunk to release a lock
        // inherited during fork. A busy slot can only be a published thunk
        // or a finalizer already waiting on one: registration/failure cleanup
        // always holds the registry while owning an unpublished slot.
        pthread_mutex_lock(&android_fork_registration_lock);
        int guarded = pthread_mutex_trylock(&handler->lock) == 0;
        if (!guarded) {
            // Never wait on a fork-held slot while owning the registry: its
            // prepare guard acquires the registry after all later thunks.
            pthread_mutex_unlock(&android_fork_registration_lock);
            pthread_mutex_lock(&handler->lock);
        }
        if (dso == NULL || handler->dso == dso) {
            handler->prepare = handler->parent = handler->child = NULL;
            handler->dso = NULL;
        }
        pthread_mutex_unlock(&handler->lock);
        if (guarded) {
            pthread_mutex_unlock(&android_fork_registration_lock);
        }
    }
    // Preserve the host's existing C++ finalization behavior. Only Android
    // relocations bind this bionic_ wrapper; native host DSOs are unaffected.
    __cxa_finalize(dso);
}
#endif

#if defined(__x86_64__)
#ifndef MAP_FIXED_NOREPLACE
#define MAP_FIXED_NOREPLACE 0x100000
#endif

// Align hints to both the target's 4 KiB and Vinix's native 16 KiB pages.
#define LOW_MAP_ALIGNMENT UINT64_C(16384)
#define LOW_MAP_BEGIN UINT64_C(0x10000)
#define LOW_MAP_END UINT64_C(0x80000000)

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
#endif

__attribute__((constructor)) static void initialize_stack_compat(void)
{
    initial_thread = pthread_self();
    // Keep an address inside the initial stack for queries from other threads.
    // Only its numeric value is used after this constructor returns.
    uintptr_t stack_local;
    initial_stack_anchor = (uintptr_t)&stack_local;
    next_pthread_getattr_np = dlsym(RTLD_NEXT, "pthread_getattr_np");
#if defined(__aarch64__)
    // Register before any Android thunk: prepare takes the registry after
    // later slot locks, and parent/child releases it before their callbacks.
    // A failed guard registration must fail subsequent Android registrations.
    android_fork_guard_error = pthread_atfork(prepare_android_fork_registry,
                                             release_android_fork_registry,
                                             release_android_fork_registry);
#endif
#if defined(__x86_64__)
    pthread_once(&mapping_symbols_once, resolve_mapping_symbols);
    // Fork from a different thread must not leave the child holding a mutex
    // whose owner exists only in the parent process.
    pthread_atfork(prepare_low_mapping_fork, release_low_mapping_fork, release_low_mapping_fork);
#endif
}

#if defined(__x86_64__)
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
#endif

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

static int initial_stack_bounds(uintptr_t *base, size_t *size)
{
    int result = mapped_stack_bounds(initial_stack_anchor, base, size);
#if defined(__aarch64__)
    if (result == 0) {
        struct rlimit limit;
        if (getrlimit(RLIMIT_STACK, &limit) != 0) {
            return errno;
        }
        // Vinix reserves space for the main stack to grow when its limit is
        // raised. Report the usable finite limit within that reservation so
        // ART installs its guard at the actual stack boundary. Preserve the
        // high address, rounding the bottom to a native 16 KiB page.
        if (limit.rlim_cur != RLIM_INFINITY && limit.rlim_cur < *size) {
            size_t usable = (size_t)limit.rlim_cur & ~((size_t)16384 - 1);
            if (usable == 0) {
                return EINVAL;
            }
            *base += *size - usable;
            *size = usable;
        }
    }
#endif
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
    // Preserve musl's detach state and every other reported attribute. Older
    // x86 musl reports one page; native musl reports the growth reservation.
    // Supply the usable initial bounds within the process's mapped ranges.
    uintptr_t base = 0;
    size_t size = 0;
    result = initial_stack_bounds(&base, &size);
    if (result == 0) {
        result = pthread_attr_setstack(attributes, (void *)base, size);
        if (result == 0) {
            // The mapped initial stack has no pthread-created guard.
            result = pthread_attr_setguardsize(attributes, 0);
        }
    }
    if (result != 0) {
        pthread_attr_destroy(attributes);
    }
    errno = saved_errno;
    return result;
}
