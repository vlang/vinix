/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_APPLICATION_SANDBOX_HOST_FIXTURE_ABI_H
#define VINIX_APPLICATION_SANDBOX_HOST_FIXTURE_ABI_H
#include <assert.h>
#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#define VINIX_V_RUNTIME
#include "sandbox_v.h"
int vinix_sandbox_main(int, char **);
_Static_assert(sizeof(int) == 4, "original errno and return width");
_Static_assert(sizeof(unsigned long) == 8, "original prctl argument width");
_Static_assert(sizeof(size_t) == 8 && sizeof(void *) == 8, "original pointer and index width");
_Static_assert(sizeof(uint32_t) == 4, "original identity width");
_Static_assert(sizeof(struct sb_cap_data) == 12 && _Alignof(struct sb_cap_data) == 4,
               "original capability layout");
_Static_assert(offsetof(struct sb_cap_data, effective) == 0 &&
               offsetof(struct sb_cap_data, permitted) == 4 &&
               offsetof(struct sb_cap_data, inheritable) == 8, "original capability offsets");
_Static_assert(SB_MAX_ENV == 64, "original environment bound");
#endif
