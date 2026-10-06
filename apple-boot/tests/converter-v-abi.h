/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_APPLE_CONVERTER_FIXTURE_ABI_H
#define VINIX_APPLE_CONVERTER_FIXTURE_ABI_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "adt.h"
#include "fdt.h"
typedef unsigned long long converter_ull;
_Static_assert(sizeof(converter_ull) == sizeof(uint64_t), "reg diagnostic word width");
_Static_assert(ADT_MAX_DEPTH == 64, "independent converter chain capacity");
#endif
