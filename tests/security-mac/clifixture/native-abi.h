/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_MAC_CLI_FIXTURE_NATIVE_ABI_H
#define VINIX_MAC_CLI_FIXTURE_NATIVE_ABI_H
#include <assert.h>
#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#define VINIX_V_RUNTIME
#include "mac.h"
#include "mac_v.h"
typedef const char mac_cli_const_char;
typedef const void mac_cli_const_void;
typedef char *const mac_cli_const_pointer;
int vm_main(int, char **);
int vm_number(const char *, unsigned, unsigned *);
int vm_permissions(const char *, unsigned *);
int mock_prctl(int, ...);
int mock_lsetxattr(const char *, const char *, const void *, size_t, int);
int mock_execvp(const char *, char *const *);
int vinix_mac_cli_capture(int, uint64_t, uint64_t, uint64_t, uint64_t);
_Static_assert(sizeof(int) == 4 && sizeof(unsigned) == 4, "original scalar widths");
_Static_assert(sizeof(unsigned long) == 8 && _Alignof(unsigned long) == 8,
               "original variadic unsigned-long words");
_Static_assert(sizeof(uint64_t) == 8 && sizeof(size_t) == 8 && sizeof(void *) == 8,
               "native word and pointer widths");
#endif
