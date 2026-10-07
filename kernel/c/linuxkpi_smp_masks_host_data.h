/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_SMP_MASKS_HOST_DATA_H
#define VINIX_LINUXKPI_SMP_MASKS_HOST_DATA_H
#if !defined(VINIX_LINUXKPI_HOST_TEST) || !defined(VINIX_LINUXKPI)
#error CPU-mask host storage requires the explicit host compiler profile
#endif

/* The native build has a separate storage object. The general host suite has
 * one header module instead; reuse that same original typed data here. */
#include <linux/cache.h>
#ifdef __APPLE__
/* Original x86 __read_mostly spells an ELF section directly, independently of
 * Linux's __section macro. Keep the host objects writable in Mach-O and restore
 * the upstream annotation after these declarations. Algorithms are unchanged. */
#pragma push_macro("__read_mostly")
#undef __read_mostly
#define __read_mostly __attribute__((__section__("__DATA,__data")))
#endif
#include "linuxkpi_cpu_masks_data.c"
#ifdef __APPLE__
#pragma pop_macro("__read_mostly")
#endif
#endif
