/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_APPLICATION_SANDBOX_GUEST_NATIVE_ABI_H
#define VINIX_APPLICATION_SANDBOX_GUEST_NATIVE_ABI_H
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include "../../../tools/sandbox/sandbox_v.h"
int vinix_sandbox_main(int, char **);
_Static_assert(sizeof(int) == 4 && sizeof(pid_t) == 4, "native status words");
_Static_assert(sizeof(uint32_t) == 4 && sizeof(uint64_t) == 8, "capability words");
_Static_assert(sizeof(size_t) == 8 && sizeof(ssize_t) == 8 && sizeof(off_t) == 8,
               "native buffer and file widths");
_Static_assert(sizeof(struct sb_cap_data) == 12, "two native capability records");
#endif
