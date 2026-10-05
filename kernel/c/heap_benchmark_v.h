/* Shared ABI for the generated V sampler; platform/compiler selection is C. */
#ifndef VINIX_HEAP_BENCHMARK_V_H
#define VINIX_HEAP_BENCHMARK_V_H
#include <stddef.h>
#include <stdint.h>
#if defined(__clang__)
#define VKB_COMPILER "clang"
#define VKB_COMPILER_MAJOR __clang_major__
#define VKB_COMPILER_MINOR __clang_minor__
#define VKB_COMPILER_PATCH __clang_patchlevel__
#elif defined(__GNUC__)
#define VKB_COMPILER "gcc"
#define VKB_COMPILER_MAJOR __GNUC__
#define VKB_COMPILER_MINOR __GNUC_MINOR__
#define VKB_COMPILER_PATCH __GNUC_PATCHLEVEL__
#else
#define VKB_COMPILER "unknown"
#define VKB_COMPILER_MAJOR 0
#define VKB_COMPILER_MINOR 0
#define VKB_COMPILER_PATCH 0
#endif
#if defined(VINIX_KALLOC_HOST_TEST)
void *vkb_test_alloc(size_t);
void vkb_test_free(void *);
int vkb_test_log(const char *, ...);
uint64_t vkb_test_ticks(void);
#define vkb_alloc vkb_test_alloc
#define vkb_free vkb_test_free
#define vkb_log vkb_test_log
#define VKB_PLATFORM "vinix"
#elif defined(__APPLE__)
void *kern_os_malloc(size_t);
void kern_os_free(void *);
void IOLog(const char *, ...);
#define vkb_alloc kern_os_malloc
#define vkb_free kern_os_free
#define vkb_log IOLog
#define VKB_PLATFORM "xnu"
#else
void *malloc(size_t);
void free(void *);
int printf_benchmark(const char *, ...);
#define vkb_alloc malloc
#define vkb_free free
#define vkb_log printf_benchmark
#define VKB_PLATFORM "vinix"
#endif
#endif
