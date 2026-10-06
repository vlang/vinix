/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_SCHED_SIGNAL_H
#define VINIX_LINUX_SCHED_SIGNAL_H
#include <linux/sched.h>
int signal_pending(struct task_struct *);
int fatal_signal_pending(struct task_struct *);
int signal_pending_state(unsigned int, struct task_struct *);
#endif
