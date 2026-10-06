#ifndef VINIX_ALLOC_BENCH_NATIVE_ABI_H
#define VINIX_ALLOC_BENCH_NATIVE_ABI_H
#define _POSIX_C_SOURCE 200809L
#define _DEFAULT_SOURCE 1
#define _DARWIN_C_SOURCE 1
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/utsname.h>
#include <time.h>
#include <unistd.h>
#if !defined(MAP_ANONYMOUS) && defined(MAP_ANON)
#define MAP_ANONYMOUS MAP_ANON
#endif
#ifndef MAP_ANONYMOUS
#error This benchmark requires anonymous mmap support
#endif
typedef const void alloc_bench_const_void;
struct alloc_bench_byte { volatile unsigned char value; };
struct alloc_bench_word { unsigned long long value; };
struct alloc_bench_observed { volatile unsigned long long value; };
struct alloc_bench_outcome { unsigned long long checksum, expected; };
_Static_assert(sizeof(struct alloc_bench_byte) == 1, "byte access stride");
_Static_assert(sizeof(struct alloc_bench_word) == 8, "sample width");
#if defined(__APPLE__)
#define VAB_ERRNO __error
#else
#define VAB_ERRNO __errno_location
#endif
#if defined(__clang__)
#define VAB_COMPILER "clang"
#define VAB_COMPILER_MAJOR __clang_major__
#define VAB_COMPILER_MINOR __clang_minor__
#define VAB_COMPILER_PATCH __clang_patchlevel__
#define VAB_COMPILER_KNOWN 1
#elif defined(__GNUC__)
#define VAB_COMPILER "gcc"
#define VAB_COMPILER_MAJOR __GNUC__
#define VAB_COMPILER_MINOR __GNUC_MINOR__
#define VAB_COMPILER_PATCH __GNUC_PATCHLEVEL__
#define VAB_COMPILER_KNOWN 1
#else
#define VAB_COMPILER "unknown"
#define VAB_COMPILER_MAJOR 0
#define VAB_COMPILER_MINOR 0
#define VAB_COMPILER_PATCH 0
#define VAB_COMPILER_KNOWN 0
#endif
#ifdef __VERSION__
#define VAB_VERSION_KNOWN 1
#define VAB_VERSION __VERSION__
#else
#define VAB_VERSION_KNOWN 0
#define VAB_VERSION ""
#endif
#endif
