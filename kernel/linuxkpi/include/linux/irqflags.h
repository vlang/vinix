/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_IRQFLAGS_H
#define VINIX_LINUX_IRQFLAGS_H
#include <vinix/runtime.h>
#define local_irq_save(flags) do { (flags) = vinix_linuxkpi_irq_save(); } while (0)
#define local_irq_restore(flags) vinix_linuxkpi_irq_restore(flags)
#define local_irq_disable() ((void)vinix_linuxkpi_irq_save())
#define local_irq_enable() vinix_linuxkpi_irq_restore(1UL << 9)
static inline bool irqs_disabled(void) {
    return !(vinix_linuxkpi_irq_flags() & (1UL << 9));
}
static inline bool irqs_disabled_flags(unsigned long flags) { return !(flags & (1UL << 9)); }
#define local_save_flags(flags) do { (flags) = vinix_linuxkpi_irq_flags(); } while (0)
#define raw_local_irq_save local_irq_save
#define raw_local_irq_restore local_irq_restore
#define raw_local_irq_disable local_irq_disable
#define raw_local_irq_enable local_irq_enable
#define raw_irqs_disabled irqs_disabled
#define raw_irqs_disabled_flags irqs_disabled_flags
#define raw_local_save_flags local_save_flags
#endif
