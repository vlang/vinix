/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_SCHED_SIGNAL_H
#define VINIX_LINUX_SCHED_SIGNAL_H
#include <linux/sched.h>
static inline int signal_pending(struct task_struct *task) {
    return vinix_linuxkpi_task_signal_pending(task->vinix_thread, false);
}
static inline int fatal_signal_pending(struct task_struct *task) {
    return vinix_linuxkpi_task_signal_pending(task->vinix_thread, true);
}
static inline int signal_pending_state(unsigned int state, struct task_struct *task) {
    if (!(state & (TASK_INTERRUPTIBLE | TASK_WAKEKILL))) return 0;
    return (state & TASK_INTERRUPTIBLE) ? signal_pending(task) : fatal_signal_pending(task);
}
#endif
