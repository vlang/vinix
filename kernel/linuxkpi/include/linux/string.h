/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_STRING_H
#define VINIX_LINUX_STRING_H
/* Kernel prototypes must not depend on the host libc (whose swab/fls names
 * collide with Linux). Native entry points implement the basic operations. */
#include_next <linux/string.h>
#endif
