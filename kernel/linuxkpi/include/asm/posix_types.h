/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_ASM_POSIX_TYPES_H
#define VINIX_ASM_POSIX_TYPES_H
/* x86-64's historical ID/device widths override the generic defaults. */
typedef unsigned short __kernel_old_uid_t;
typedef unsigned short __kernel_old_gid_t;
#define __kernel_old_uid_t __kernel_old_uid_t
typedef unsigned long __kernel_old_dev_t;
#define __kernel_old_dev_t __kernel_old_dev_t
#include <asm-generic/posix_types.h>
#endif
