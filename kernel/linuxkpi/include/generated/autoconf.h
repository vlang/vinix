/* SPDX-License-Identifier: GPL-2.0-or-later */
/* This compatibility build has an explicit, fixed x86-64 target. */
#ifndef VINIX_LINUX_AUTOCONF_H
#define VINIX_LINUX_AUTOCONF_H
#define CONFIG_64BIT 1
#define CONFIG_X86 1
#define CONFIG_X86_64 1
#define CONFIG_SMP 1
#define CONFIG_NR_CPUS 256
/* Tiger Lake has 64-byte cache lines; there is no NUMA configuration here. */
#define CONFIG_X86_L1_CACHE_SHIFT 6
#define CONFIG_X86_INTERNODE_CACHE_SHIFT 6
/* Compatibility time units. Timer/jiffies services still need a backend. */
#define CONFIG_HZ 1000
#endif
