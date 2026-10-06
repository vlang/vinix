#ifndef VINIX_PRINT_FIXTURE_NATIVE_ABI_H
#define VINIX_PRINT_FIXTURE_NATIVE_ABI_H
#include <assert.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
typedef unsigned long long vprint_ull;
typedef long long vprint_ll;
_Static_assert(sizeof(vprint_ull) == 8 && sizeof(vprint_ll) == 8, "original native varargs width");
#ifdef PROD
#define VINIX_PRINT_FIXTURE_PROD 1
#else
#define VINIX_PRINT_FIXTURE_PROD 0
#endif
int fixture_printf(const char *, ...);
int fixture_panic(char *, ...);
int fixture_kprintf(const char *, ...);
int fixture_benchmark(const char *, ...);
int fixture_fprintf(void *, const char *, ...);
#endif
