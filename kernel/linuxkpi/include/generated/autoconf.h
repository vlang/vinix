/* SPDX-License-Identifier: GPL-2.0-or-later */
/* This compatibility build has an explicit, fixed x86-64 target. */
#ifndef VINIX_LINUX_AUTOCONF_H
#define VINIX_LINUX_AUTOCONF_H
#define CONFIG_64BIT 1
#define CONFIG_X86 1
#define CONFIG_X86_64 1
#define CONFIG_SMP 1
#define CONFIG_NR_CPUS 256
/* Task identity and ordinary waits are backed by the native Thread. */
#define CONFIG_THREAD_INFO_IN_TASK 1
/* Tiger Lake has 64-byte cache lines; there is no NUMA configuration here. */
#define CONFIG_X86_L1_CACHE_SHIFT 6
#define CONFIG_X86_INTERNODE_CACHE_SHIFT 6
/* Native tick frequency and Linux timeout conversion units. */
#define CONFIG_HZ 1000
#if defined(VINIX_LINUXKPI_HOST_TEST) && defined(__APPLE__)
/* Mach-O has no ELF .data..cacheline_aligned section. Keep its alignment. */
#define __cacheline_aligned __attribute__((__aligned__(64)))
#endif
#endif
