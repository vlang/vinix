/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_SCHED_TASK_H
#define VINIX_LINUX_SCHED_TASK_H
#include <linux/sched.h>
struct task_struct *get_task_struct(struct task_struct *);
/* No task dereference may follow the final native owner release. */
void put_task_struct(struct task_struct *);
#endif
