/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_RESOURCE_OPEN_FIXTURE_NATIVE_ABI_H
#define VINIX_RESOURCE_OPEN_FIXTURE_NATIVE_ABI_H
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <termios.h>
#include <unistd.h>
typedef unsigned long long vro_ull;
typedef long long vro_ll;
_Static_assert(sizeof(vro_ull) == 8 && sizeof(vro_ll) == 8 && sizeof(size_t) == 8, "native scanner/diagnostic widths");
_Static_assert(sizeof(unsigned) == 4 && sizeof(int) == 4, "native resource fixture integers");
#endif
