/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native libc declarations and scalar constraints only. */
#ifndef VINIX_REBOOT_PERSISTENCE_NATIVE_ABI_H
#define VINIX_REBOOT_PERSISTENCE_NATIVE_ABI_H
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/reboot.h>
#include <unistd.h>
_Static_assert(sizeof(int) == 4, "native descriptors, modes and reboot command");
_Static_assert(sizeof(size_t) == 8 && sizeof(ssize_t) == 8 &&
    __builtin_types_compatible_p(ssize_t, ptrdiff_t), "native persistence transfer counts");
#endif
