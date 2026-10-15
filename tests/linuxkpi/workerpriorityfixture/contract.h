/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Declaration metadata only; executable transports and checks are V. */
#ifndef VINIX_WORKER_PRIORITY_FIXTURE_H
#define VINIX_WORKER_PRIORITY_FIXTURE_H
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vinix/runtime.h>
#define v_fixed_index wph_fixed_index
#define v_fixed_index_u64 wph_fixed_index_u64
_Static_assert(__builtin_types_compatible_p(__typeof__(&vinix_linuxkpi_worker_set_nice), int (*)(int)), "native worker priority ABI");
#endif
