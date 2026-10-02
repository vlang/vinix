/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_ASM_PROCESSOR_H
#define VINIX_ASM_PROCESSOR_H
#include <vinix/runtime.h>

/* A native spin hint also services TLB shootdowns while IRQs are disabled.
 * Other Linux CPU, page-table and task-switch services are not supplied here. */
static inline void cpu_relax(void)
{
    vinix_linuxkpi_spin_wait();
}
#endif
