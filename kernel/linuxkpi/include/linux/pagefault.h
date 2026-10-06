/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_PAGEFAULT_H
#define VINIX_LINUX_PAGEFAULT_H

#include <stdbool.h>

/* Task-local nesting suppresses native page-in/COW without disabling
 * preemption or ordinary task sleeps. Fault-handler queries include the
 * native preemption pins and actual maskable IRQ depth. Full Linux context-bit
 * encoding, NMI/BH accounting and exception fixups remain separate services. */
void pagefault_disable(void);
void pagefault_enable(void);
bool pagefault_disabled(void);
bool faulthandler_disabled(void);

#endif
