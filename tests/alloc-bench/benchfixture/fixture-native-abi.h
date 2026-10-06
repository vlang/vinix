#ifndef VINIX_ALLOC_BENCH_FIXTURE_NATIVE_ABI_H
#define VINIX_ALLOC_BENCH_FIXTURE_NATIVE_ABI_H
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
#if defined(__APPLE__)
#define VAB_FIXTURE_ERRNO __error
#else
#define VAB_FIXTURE_ERRNO __errno_location
#endif
struct vab_fixture_word { unsigned long long value; };
#endif
