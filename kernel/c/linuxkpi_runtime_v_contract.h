/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_RUNTIME_V_CONTRACT_H
#define VINIX_LINUXKPI_RUNTIME_V_CONTRACT_H
#include "linuxkpi_srcu_v_contract.h"
#include <linux/ioport.h>
#include <linux/printk.h>
#include <linux/slab.h>
#include <vinix/printk.h>
#include <vinix/gfp.h>

#if defined(CONFIG_KALLSYMS) || defined(CONFIG_SYMBOLIC_ERRNAME)
#error "Native formatter requires real symbol/errno services before enabling their configuration"
#endif
_Static_assert(sizeof(void *) == 8 && sizeof(long) == 8,
    "V runtime native word ABI");
_Static_assert(sizeof(struct va_format) == 16 &&
    offsetof(struct va_format, fmt) == 0 && offsetof(struct va_format, va) == 8,
    "V nested formatter descriptor ABI");
_Static_assert(sizeof(struct resource) == 64 &&
    offsetof(struct resource, start) == 0 && offsetof(struct resource, end) == 8 &&
    offsetof(struct resource, name) == 16 && offsetof(struct resource, flags) == 24 &&
    offsetof(struct resource, desc) == 32 && offsetof(struct resource, parent) == 40 &&
    offsetof(struct resource, sibling) == 48 && offsetof(struct resource, child) == 56,
    "V resource formatter ABI");
_Static_assert(GFP_KERNEL == 3264 && __GFP_HIGH == 0x20 && __GFP_ZERO == 0x100 &&
    __GFP_NOWARN == 0x2000 && __GFP_NORETRY == 0x10000 && __GFP_RETRY_MAYFAIL == 0x4000,
    "V allocation flags must match imported Linux");
_Static_assert(sizeof(raw_spinlock_t) == 4, "V logger raw-spin storage");
_Static_assert(sizeof(struct vinix_linuxkpi_printk_record) == 1048 &&
    offsetof(struct vinix_linuxkpi_printk_record, text) == 24,
    "V owned logger record ABI");
_Static_assert(sizeof(struct vinix_linuxkpi_printk_state) == 48,
    "V logger state ABI");
_Static_assert(CONSOLE_LOGLEVEL_DEFAULT == 7 && MESSAGE_LOGLEVEL_DEFAULT == 4 &&
    CONSOLE_LOGLEVEL_MIN == 1, "V logger static default levels");
_Static_assert(sizeof(struct vkw_mutex) == sizeof(struct mutex) &&
    _Alignof(struct vkw_mutex) == _Alignof(struct mutex) &&
    offsetof(struct vkw_mutex, wait_list) == offsetof(struct mutex, wait_list),
    "V logger static lifecycle mutex ABI");
_Static_assert(sizeof(struct vkw_completion) == sizeof(struct completion) &&
    _Alignof(struct vkw_completion) == _Alignof(struct completion) &&
    offsetof(struct vkw_completion, wait.task_list) ==
        offsetof(struct completion, wait.task_list),
    "V logger static readiness completion ABI");
#endif
