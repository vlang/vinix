#ifndef VINIX_KRANDOM_HOST_NATIVE_ABI_H
#define VINIX_KRANDOM_HOST_NATIVE_ABI_H
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
typedef va_list vkrandom_host_va;
typedef long double vkrandom_host_ld;
typedef unsigned long long vkrandom_host_ull;
int kprintf(const char *, ...);
int vinix_hw_random64(uint64_t *);
void vinix_test_set_hardware(int);
#if defined(__APPLE__) && defined(__aarch64__)
_Static_assert(sizeof(va_list) == 8, "Darwin native stack cursor");
#elif defined(__aarch64__)
_Static_assert(sizeof(va_list) == 32, "AAPCS64 native cursor");
#elif defined(__x86_64__)
_Static_assert(sizeof(va_list) == 24, "SysV native cursor");
#else
#error Unsupported random host fixture ABI
#endif
#endif
