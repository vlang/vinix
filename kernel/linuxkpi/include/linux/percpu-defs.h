/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_PERCPU_DEFS_H
#define VINIX_LINUX_PERCPU_DEFS_H
#include <linux/types.h>
#include <linux/cache.h>
#include <linux/preempt.h>
#include <vinix/runtime.h>
#include_next <linux/percpu-defs.h>

#ifdef VINIX_LINUXKPI_HOST_TEST
/* Native ELF uses the original section declarations. Host tests group those
 * sections for Mach-O/ELF and avoid ASan global redzones inside the template:
 * copying the complete linker section legitimately reads alignment padding.
 * The allocated CPU copies and all runtime accesses still use ASan/UBSan. */
#undef __PCPU_ATTRS
#ifdef __APPLE__
#define __PCPU_ATTRS(sec) __percpu __attribute__((section("__DATA,vinixpcpu"), no_sanitize("address")))
#else
#define __PCPU_ATTRS(sec) __percpu __attribute__((section("vinixpcpu"), no_sanitize("address")))
#endif
#endif

/* Static symbols address an initialization template. Dynamic allocations use
 * compact per-allocation strides. Both translate through the native registry;
 * a Linux per-CPU pointer must never be applied to Vinix's GS segment. */
#undef per_cpu_ptr
#define per_cpu_ptr(ptr, cpu) ({ \
    __auto_type __vinix_pcpu = (ptr); \
    (__typeof__(__vinix_pcpu))vinix_linuxkpi_percpu_ptr(__vinix_pcpu, (cpu)); \
})
#undef raw_cpu_ptr
#define raw_cpu_ptr(ptr) per_cpu_ptr(ptr, vinix_linuxkpi_cpu_id())
#undef this_cpu_ptr
#define this_cpu_ptr(ptr) raw_cpu_ptr(ptr)
#endif
