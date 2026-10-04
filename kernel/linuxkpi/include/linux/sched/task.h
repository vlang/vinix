/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_SCHED_TASK_H
#define VINIX_LINUX_SCHED_TASK_H
#include <linux/sched.h>
static inline struct task_struct *get_task_struct(struct task_struct *task)
{
    vinix_linuxkpi_task_get(task->vinix_thread);
    return task;
}
static inline void put_task_struct(struct task_struct *task)
{
    /* Nothing may dereference task after the native owner loses this pin. */
    vinix_linuxkpi_task_put(task->vinix_thread);
}
#endif
