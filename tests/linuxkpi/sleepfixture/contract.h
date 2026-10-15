/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Type, compiler-intrinsic and include metadata only. Runtime logic is V. */
#ifndef VINIX_CONDITIONAL_SLEEP_FIXTURE_H
#define VINIX_CONDITIONAL_SLEEP_FIXTURE_H
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define u64 vsl_linux_u64
#define timezone vsl_linux_timezone
#define ffs vsl_linux_ffs
#define fls vsl_linux_fls
#include <linux/kernel.h>
#undef u64
#undef timezone
#undef ffs
#undef fls
typedef const char *vkh_const_char_p;
/* Link the real V library entry while preserving its generated init guard. */
#define vsl_fixture_entry main
typedef double _Complex vsl_complex;
typedef struct { int value; } vsl_record;
typedef union { int value; double other; } vsl_union;
/* A compiler intrinsic binding, with executable observations in core.v. */
#define vsl_make_complex(real, imaginary) __builtin_complex((real), (imaginary))
_Static_assert(__builtin_types_compatible_p(__typeof__(&vinix_might_sleep_if_native), void (*)(_Bool, const char *, int)), "conditional sleep native ABI");
#endif
