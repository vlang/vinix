/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_PAGEFAULT_V_CONTRACT_H
#define VINIX_LINUXKPI_PAGEFAULT_V_CONTRACT_H

#include <stdbool.h>
#include <stdint.h>

/* Borrow the current native task's aligned counter synchronously. The getter
 * allocates and schedules nothing and returns NULL before a task exists.
 * Queries can call it without an IRQ guard. No caller retains its result. */
uint32_t *vinix_linuxkpi_fault_depth(void);
uint64_t vinix_linuxkpi_irq_save(void);
void vinix_linuxkpi_irq_restore(uint64_t flags);
uint32_t vinix_linuxkpi_preempt_count(void);

/* Existing native CPU/worker primitives used by the task-scope fixture.
 * Keep their declarations independent of the Linux header/type namespace. */
uint32_t vinix_linuxkpi_cpu_id(void);
uint32_t vinix_linuxkpi_percpu_count(void);
int vinix_linuxkpi_worker_bind(uint32_t cpu);
void vinix_linuxkpi_preempt_disable(void);
void vinix_linuxkpi_preempt_enable(void);

/* These algorithms are implemented by the production V compatibility core.
 * Native user-copy and trap policy must consult the same task-owned counter. */
void pagefault_disable(void);
void pagefault_enable(void);
bool pagefault_disabled(void);
bool faulthandler_disabled(void);

#endif
