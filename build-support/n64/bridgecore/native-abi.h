/* SPDX-License-Identifier: MIT */
/* Native declarations only; bridge state, decisions and ownership are V. */
#ifndef VINIX_N64_NATIVE_ABI_H
#define VINIX_N64_NATIVE_ABI_H
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include "../bridge.h"
#include "../budget.h"
#include <libretro.h>
#include <m64p_frontend.h>
#include <m64p_types.h>
#include "device/device.h"
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
typedef const void n64_const_void;
typedef const int16_t n64_const_sample;
typedef const char n64_const_char;
typedef jmp_buf n64_frame_escape;
typedef va_list n64_native_va;
extern int frame_break, g_rsp_force_halt, g_real_stop;
extern struct device g_dev;
void vinix_n64_log_message(enum retro_log_level, const char *, ...);
_Static_assert(sizeof(unsigned) == 4 && sizeof(int) == 4, "native callback/control words");
_Static_assert(sizeof(size_t) == 8 && sizeof(off_t) == 8, "native ROM/save sizes");
_Static_assert(sizeof(enum retro_log_level) == 4, "native variadic severity argument");
#if defined(__APPLE__) && defined(__aarch64__)
_Static_assert(sizeof(n64_native_va) == 8, "Darwin native stack cursor");
#elif defined(__aarch64__)
_Static_assert(sizeof(n64_native_va) == 32, "AAPCS64 complete register cursor");
#elif defined(__x86_64__)
_Static_assert(sizeof(n64_native_va) == 24, "SysV64 complete register cursor");
#else
#error Unsupported N64 bridge native ABI
#endif
#endif
