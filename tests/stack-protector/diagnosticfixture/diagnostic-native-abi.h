#ifndef VINIX_STACK_DIAGNOSTIC_NATIVE_ABI_H
#define VINIX_STACK_DIAGNOSTIC_NATIVE_ABI_H
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef unsigned long long vstack_diagnostic_ull;
_Static_assert(sizeof(vstack_diagnostic_ull) == sizeof(uint64_t), "original native printf width");
void vinix_stack_guard_message(const char *);
void vinix_stack_guard_diagnostic(uint64_t, uint64_t, uint64_t);
#endif
