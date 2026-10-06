/* SPDX-License-Identifier: BSD-2-Clause */
#ifndef VINIX_QEMU_CORE_INT_FIXTURE_NATIVE_ABI_H
#define VINIX_QEMU_CORE_INT_FIXTURE_NATIVE_ABI_H
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <fcntl.h>
#include <sys/syscall.h>
#include <unistd.h>
_Static_assert(sizeof(long)==8 && sizeof(int)==4 && sizeof(void *)==8,"native syscall word, C-int and pointer widths");
#endif
