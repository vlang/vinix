/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_SCHED_H
#define VINIX_LINUX_SCHED_H
#include <linux/types.h>
#include <linux/preempt.h>
#include <asm/current.h>
#include <vinix/runtime.h>

#define TASK_COMM_LEN 16
#define PF_EXITING 0x00000004
/* A borrowed view embedded in the native Thread. Only current-task access is
 * supported. Retained task references, mm, blocking states and Linux scheduler
 * internals need native lifetime/waiting implementations before being exposed. */
struct task_struct {
    void *vinix_thread;
    int pid, tgid;
    unsigned int flags;
    char comm[TASK_COMM_LEN];
    char vinix_initial_comm[TASK_COMM_LEN];
};
static inline int task_pid_nr(const struct task_struct *task) { return task->pid; }
static inline int task_tgid_nr(const struct task_struct *task) { return task->tgid; }
static inline bool need_resched(void) { return vinix_linuxkpi_need_resched(); }
static inline int cond_resched(void) { return vinix_linuxkpi_cond_resched(); }
#endif
