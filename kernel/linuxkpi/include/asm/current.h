/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_ASM_CURRENT_H
#define VINIX_ASM_CURRENT_H
struct task_struct;
struct task_struct *vinix_linuxkpi_current_task(void);
/* Vinix's GS layout is not Linux's pcpu_hot layout. */
#define current vinix_linuxkpi_current_task()
#endif
