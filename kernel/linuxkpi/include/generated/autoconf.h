/* SPDX-License-Identifier: GPL-2.0-or-later */
/* This compatibility build has an explicit, fixed x86-64 target. */
#ifndef VINIX_LINUX_AUTOCONF_H
#define VINIX_LINUX_AUTOCONF_H
#define CONFIG_64BIT 1
#define CONFIG_X86 1
#define CONFIG_X86_64 1
#define CONFIG_SMP 1
#define CONFIG_NR_CPUS 256
#endif
