/* SPDX-License-Identifier: GPL-2.0-or-later */
/* This compatibility build has an explicit, fixed x86-64 target. */
#ifndef VINIX_LINUX_AUTOCONF_H
#define VINIX_LINUX_AUTOCONF_H
#define CONFIG_64BIT 1
#define CONFIG_X86 1
#define CONFIG_X86_64 1
/* Native user mappings use hardware page tables. This selects the genuine
 * MMU header layout; Linux page ownership and GPU mappings remain separate. */
#define CONFIG_MMU 1
/* Native x86 paging supports Limine's four- and five-level modes. Select the
 * genuine five-level-capable type ABI; Linux page ownership and runtime
 * geometry bindings remain separate dependencies. */
#define CONFIG_X86_5LEVEL 1
#define CONFIG_PGTABLE_LEVELS 5
#define CONFIG_SMP 1
#define CONFIG_NR_CPUS 256
/* Ordinary process/IRQ capture uses a native owned-byte logger. NMI entry,
 * panic bypass and device log metadata are separate pending services. */
#define CONFIG_PRINTK 1
#define CONFIG_MESSAGE_LOGLEVEL_DEFAULT 4
#define CONFIG_CONSOLE_LOGLEVEL_DEFAULT 7
#define CONFIG_CONSOLE_LOGLEVEL_QUIET 4
/* SMP SRCU has independent reader/grace-period state. Ordinary RCU is pending. */
#define CONFIG_TREE_SRCU 1
/* Do not alias NMI entrypoints to readers using the native per-CPU registry. */
#define CONFIG_NEED_SRCU_NMI_SAFE 1
/* Task identity and ordinary waits are backed by the native Thread. */
#define CONFIG_THREAD_INFO_IN_TASK 1
/* Tiger Lake has 64-byte cache lines; there is no NUMA configuration here. */
#define CONFIG_X86_L1_CACHE_SHIFT 6
#define CONFIG_X86_INTERNODE_CACHE_SHIFT 6
/* Native tick frequency and Linux timeout conversion units. */
#define CONFIG_HZ 1000
/* Pinned i915 Kconfig.profile default; no fence execution is implied. */
#define CONFIG_DRM_I915_FENCE_TIMEOUT 10000
#if defined(VINIX_LINUXKPI_HOST_TEST) && defined(__APPLE__)
/* Mach-O has no ELF .data..cacheline_aligned section. Keep its alignment. */
#define __cacheline_aligned __attribute__((__aligned__(64)))
#endif
#endif
