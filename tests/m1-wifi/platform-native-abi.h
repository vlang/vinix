/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_WIFI_PLATFORM_NATIVE_ABI_H
#define VINIX_WIFI_PLATFORM_NATIVE_ABI_H
#include <assert.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "platform_fixture.h"
uint64_t vinix_m1_test_clock_us(void);
void vinix_m1_test_delay(uint32_t);
void vinix_m1_test_barrier(void);
void vinix_m1_test_cache_sync(void *, size_t, int32_t);
_Static_assert(sizeof(uint64_t) == 8 && sizeof(void *) == 8, "native register/word widths");
#endif
