/* SPDX-License-Identifier: ISC */
#ifndef VINIX_WIFI_HELPER_NATIVE_ABI_H
#define VINIX_WIFI_HELPER_NATIVE_ABI_H
#include "wifi_v.h"
#include <assert.h>
typedef const struct termios wifi_helper_const_termios;
_Static_assert(sizeof(int) == 4 && sizeof(int64_t) == 8, "native helper widths");
#endif
