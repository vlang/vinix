/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_COMPILER_ATTRIBUTES_H
#define VINIX_LINUX_COMPILER_ATTRIBUTES_H
/* Host libc and Apple Clang use these names too. The unchanged Linux header
 * owns this namespace in compatibility translation units and host tests. */
#ifndef __LINUX_COMPILER_ATTRIBUTES_H
#undef __deprecated
#undef __pure
#undef __weak
#undef __always_inline
#undef __cold
#undef __counted_by
#undef __alloc_size
#undef static_assert
#endif
#include_next <linux/compiler_attributes.h>
#if defined(VINIX_LINUXKPI_HOST_TEST) && defined(__APPLE__)
/* The Mach-O test executable has no Linux linker script or init-section
 * reclamation. Keep ordinary code/data placement there; the per-CPU template
 * has its own real host section. Native kernel section attributes are intact. */
#undef __section
#define __section(name)
#endif
#endif
