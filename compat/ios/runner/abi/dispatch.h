/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_IOS_DISPATCH_H
#define VINIX_IOS_DISPATCH_H
#include <pthread.h>
#include <stdio.h>
#include <stdint.h>
#include <errno.h>
#include <stdarg.h>
#include <string.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/types.h>
#include <time.h>
#include <sys/stat.h>
#include <dirent.h>
/* Darwin's fortified overflow path terminates with an ARM64 breakpoint. */
static void ios_fortify_trap(void) { __builtin_trap(); }
/* A portable non-elidable wipe; keychain storage policy and crypto stay in V. */
static void ios_secure_zero(void *bytes, size_t length) {
    volatile unsigned char *cursor = (volatile unsigned char *)bytes;
    while (length--) *cursor++ = 0;
}
static int ios_readdir_info(void *directory, char *name, uint64_t *fields) {
    struct dirent *entry = readdir((DIR *)directory);
    if (!entry) return 0;
    size_t length = strlen(entry->d_name);
    if (length >= 1024) { errno = ENAMETOOLONG; return -1; }
    fields[0] = entry->d_ino;
    fields[1] = (uint64_t)telldir((DIR *)directory);
    fields[2] = entry->d_type;
    fields[3] = length;
    memcpy(name, entry->d_name, length + 1);
    return 1;
}
/* Read native libc's structure in C; the Darwin layout conversion is in V. */
static int ios_stat_info(const char *path, int fd, int kind, uint64_t *fields) {
    struct stat info;
    int result = kind == 2 ? fstat(fd, &info) : kind == 1 ? lstat(path, &info) : stat(path, &info);
    if (result) return result;
    fields[0] = info.st_dev; fields[1] = info.st_mode; fields[2] = info.st_nlink;
    fields[3] = info.st_ino; fields[4] = info.st_uid; fields[5] = info.st_gid; fields[6] = info.st_rdev;
#ifdef __APPLE__
    fields[7] = info.st_atimespec.tv_sec; fields[8] = info.st_atimespec.tv_nsec;
    fields[9] = info.st_mtimespec.tv_sec; fields[10] = info.st_mtimespec.tv_nsec;
    fields[11] = info.st_ctimespec.tv_sec; fields[12] = info.st_ctimespec.tv_nsec;
    fields[13] = info.st_birthtimespec.tv_sec; fields[14] = info.st_birthtimespec.tv_nsec;
    fields[18] = info.st_flags; fields[19] = info.st_gen;
#else
    fields[7] = info.st_atim.tv_sec; fields[8] = info.st_atim.tv_nsec;
    fields[9] = info.st_mtim.tv_sec; fields[10] = info.st_mtim.tv_nsec;
    fields[11] = info.st_ctim.tv_sec; fields[12] = info.st_ctim.tv_nsec;
    fields[13] = fields[14] = fields[18] = fields[19] = 0;
#endif
    fields[15] = info.st_size; fields[16] = info.st_blocks; fields[17] = info.st_blksize;
    return 0;
}
static int ios_mkdir(const char *path, uint32_t mode) { return mkdir(path, mode); }
static int ios_clock_gettime(int clock, void *time) { return clock_gettime(clock, time); }
static int ios_clock_getres(int clock, void *time) { return clock_getres(clock, time); }
static int ios_nanosleep(void *request, void *remainder) { return nanosleep(request, remainder); }
/* ARM64 Darwin and musl tm both use nine 32-bit fields, a 64-bit GMT offset
 * and a zone pointer (56 bytes). Native libc handles the calendar/timezone. */
static void *ios_localtime_r(void *value, void *output) { return localtime_r(value, output); }
static void *ios_gmtime_r(void *value, void *output) { return gmtime_r(value, output); }
static void *ios_localtime(void *value) { return localtime(value); }
static void *ios_gmtime(void *value) { return gmtime(value); }
static size_t ios_strftime(char *output, size_t size, const char *format, void *time) { return strftime(output, size, format, time); }
/* V's os header uses the same ABI-compatible opaque declarations. */
extern int posix_spawnp(pid_t *, const char *, const void *, const void *, char *const [], char *const []);
static void *ios_signal(int number, void *handler) { return (void *)signal(number, (void (*)(int))handler); }
static int ios_posix_spawn_default(void *pid, const char *path, char **arguments, char **environment) {
    return posix_spawnp((pid_t *)pid, path, NULL, NULL, arguments, environment);
}
/* Darwin ARM64 va_list is a stack pointer; Linux AAPCS64 va_list also carries
 * register-save areas. Empty register ranges force consumption from the same
 * stack slots. Long double differs in size and is rejected explicitly. */
static void ios_check_format(const char *format) {
    for (const char *p = format; *p; ++p) {
        if (*p != '%') continue;
        if (*++p == '%') continue;
        while (*p && !strchr("diouxXfFeEgGaAcspn%@", *p)) {
            if (*p++ == 'L') { fputs("iOS: long double varargs are not implemented\n", stderr); abort(); }
        }
        if (!*p) break;
    }
}
#ifdef __APPLE__
#define IOS_STACK_VA(arguments, stack) va_list arguments = (char *)(stack)
#else
#define IOS_STACK_VA(arguments, stack) va_list arguments; \
    arguments.__stack = (stack); arguments.__gr_top = NULL; arguments.__vr_top = NULL; \
    arguments.__gr_offs = 0; arguments.__vr_offs = 0
#endif
static int ios_vsnprintf(char *buffer, size_t size, const char *format, void *stack) {
    ios_check_format(format); IOS_STACK_VA(arguments, stack); return vsnprintf(buffer, size, format, arguments);
}
static int ios_vsprintf(char *buffer, const char *format, void *stack) {
    ios_check_format(format); IOS_STACK_VA(arguments, stack); return vsprintf(buffer, format, arguments);
}
static int ios_vfprintf(void *stream, const char *format, void *stack) {
    ios_check_format(format); IOS_STACK_VA(arguments, stack); return vfprintf(stream, format, arguments);
}
static int ios_vsscanf(const char *input, const char *format, void *stack) {
    ios_check_format(format); IOS_STACK_VA(arguments, stack); return vsscanf(input, format, arguments);
}
static int *ios_errno_address(void) { return &errno; }
static size_t ios_sizeof_mutex(void) { return sizeof(pthread_mutex_t); }
static size_t ios_sizeof_cond(void) { return sizeof(pthread_cond_t); }
static size_t ios_sizeof_once(void) { return sizeof(pthread_once_t); }
/* Return native stack bounds; the Darwin containment policy lives in V. */
static int ios_current_stack_bounds(uint64_t *bounds) {
#ifdef __APPLE__
    uintptr_t top = (uintptr_t)pthread_get_stackaddr_np(pthread_self());
    size_t size = pthread_get_stacksize_np(pthread_self());
    bounds[0] = top - size; bounds[1] = top;
    return 0;
#elif defined(__linux__)
    extern int pthread_getattr_np(pthread_t, pthread_attr_t *);
    pthread_attr_t attributes;
    int result = pthread_getattr_np(pthread_self(), &attributes);
    if (result) return result;
    void *base = NULL;
    size_t size = 0;
    result = pthread_attr_getstack(&attributes, &base, &size);
    int cleanup = pthread_attr_destroy(&attributes);
    if (result) return result;
    if (cleanup) return cleanup;
    bounds[0] = (uintptr_t)base; bounds[1] = (uintptr_t)base + size;
    return 0;
#else
    (void)bounds; return ENOTSUP;
#endif
}
static int ios_key_create(void *output, void *destructor) {
    pthread_key_t key;
    int result = pthread_key_create(&key, (void (*)(void *))destructor);
    if (!result) *(uint64_t *)output = key;
    return result;
}
static int ios_mutex_create(void *object, int kind) {
    pthread_mutexattr_t attr;
    int result = pthread_mutexattr_init(&attr);
    if (result) return result;
    result = pthread_mutexattr_settype(&attr, kind == 1 ? PTHREAD_MUTEX_ERRORCHECK : kind == 2 ? PTHREAD_MUTEX_RECURSIVE : PTHREAD_MUTEX_NORMAL);
    if (!result) result = pthread_mutex_init(object, &attr);
    pthread_mutexattr_destroy(&attr);
    return result;
}
static int ios_thread_name(const char *name) {
#ifdef __APPLE__
    return pthread_setname_np(name);
#else
    extern int pthread_setname_np(pthread_t, const char *);
    return pthread_setname_np(pthread_self(), name);
#endif
}
static void *ios_host_stdio(int index) { return index == 0 ? stdin : index == 1 ? stdout : stderr; }
static void ios_store_pointer(uint64_t *slot, uint64_t value) { __atomic_store_n(slot, value, __ATOMIC_RELEASE); }
static uint64_t ios_load_pointer(uint64_t *slot) { return __atomic_load_n(slot, __ATOMIC_ACQUIRE); }
static int64_t ios_ref_change(int64_t *slot, int64_t change) {
    return __atomic_fetch_add(slot, change, __ATOMIC_ACQ_REL);
}
static int ios_ref_try_retain(int64_t *slot) {
    int64_t value = __atomic_load_n(slot, __ATOMIC_ACQUIRE);
    while (value > 0) {
        if (__atomic_compare_exchange_n(slot, &value, value + 1, 0,
                __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) return 1;
    }
    return 0;
}
static pthread_mutex_t ios_initialize_mutex;
static pthread_once_t ios_initialize_once = PTHREAD_ONCE_INIT;
static void ios_initialize_mutex_create(void) {
    pthread_mutexattr_t attr;
    if (pthread_mutexattr_init(&attr) || pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE) ||
        pthread_mutex_init(&ios_initialize_mutex, &attr) || pthread_mutexattr_destroy(&attr)) abort();
}
static void ios_objc_initialize_lock(void) {
    if (pthread_once(&ios_initialize_once, ios_initialize_mutex_create) || pthread_mutex_lock(&ios_initialize_mutex)) abort();
}
static void ios_objc_initialize_unlock(void) {
    if (pthread_mutex_unlock(&ios_initialize_mutex)) abort();
}
#if defined(__aarch64__) || defined(__arm64__)
void ios_chkstk_darwin(void);
void ios_atomic_pair_load(uint64_t *head, uint64_t *output);
int ios_atomic_pair_exchange(uint64_t *head, uint64_t *expected, uint64_t *desired);
void ios_objc_msgsend(void);
void ios_objc_super(void);
void ios_objc_builtin(void);
void ios_snprintf(void);
void ios_tlv_get_addr(void);
void ios_lazy_entry(void);
void ios_nslog(void);
void ios_printf(void);
void ios_cxx_verbose_abort(void);
void ios_cg_image_create(void);
void ios_fprintf(void);
void ios_sprintf(void);
void ios_sscanf(void);
void ios_asprintf(void);
void ios_open(void);
void ios_fcntl(void);
void ios_snprintf_checked(void);
void ios_sprintf_checked(void);
#define IOS_ARC_REGISTERS(M) M(0) M(1) M(2) M(3) M(4) M(5) M(6) M(7) \
    M(8) M(9) M(10) M(11) M(12) M(13) M(14) M(15) M(19) M(20) M(21) \
    M(22) M(23) M(24) M(25) M(26) M(27) M(28)
#define IOS_ARC_DECLARE(n) void ios_arc_retain_x##n(void); void ios_arc_release_x##n(void);
IOS_ARC_REGISTERS(IOS_ARC_DECLARE)
#undef IOS_ARC_DECLARE
static void *ios_arc_register(int reg, int releasing) {
    switch (reg) {
#define IOS_ARC_ADDRESS(n) case n: return releasing ? (void *)ios_arc_release_x##n : (void *)ios_arc_retain_x##n;
    IOS_ARC_REGISTERS(IOS_ARC_ADDRESS)
#undef IOS_ARC_ADDRESS
    default: return NULL;
    }
}
#undef IOS_ARC_REGISTERS
#else
static void ios_chkstk_darwin(void) { abort(); }
static void ios_atomic_pair_load(uint64_t *head, uint64_t *output) { (void)head; (void)output; abort(); }
static int ios_atomic_pair_exchange(uint64_t *head, uint64_t *expected, uint64_t *desired) {
    (void)head; (void)expected; (void)desired; abort();
}
static void ios_objc_msgsend(void) { abort(); }
static void ios_objc_super(void) { abort(); }
static void ios_objc_builtin(void) { abort(); }
static void ios_snprintf(void) { abort(); }
static void ios_tlv_get_addr(void) { abort(); }
static void ios_lazy_entry(void) { abort(); }
static void ios_nslog(void) { abort(); }
static void ios_printf(void) { abort(); }
static void ios_cxx_verbose_abort(void) { abort(); }
static void ios_cg_image_create(void) { abort(); }
static void ios_fprintf(void) { abort(); }
static void ios_sprintf(void) { abort(); }
static void ios_sscanf(void) { abort(); }
static void ios_asprintf(void) { abort(); }
static void ios_open(void) { abort(); }
static void ios_fcntl(void) { abort(); }
static void ios_snprintf_checked(void) { abort(); }
static void ios_sprintf_checked(void) { abort(); }
static void *ios_arc_register(int reg, int releasing) { (void)reg; (void)releasing; return NULL; }
#endif
#endif
