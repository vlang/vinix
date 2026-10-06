/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_SCHED_H
#define VINIX_LINUX_SCHED_H
#include <linux/types.h>
#include <linux/kernel.h>
#include <linux/limits.h>
#include <linux/ktime.h>
#include <linux/preempt.h>
#include <linux/spinlock_types_raw.h>
#include <asm/current.h>
#include <vinix/runtime.h>

#define TASK_COMM_LEN 16
#define PF_VCPU 0x00000001
#define PF_EXITING 0x00000004
#define TASK_RUNNING 0x00000000
#define TASK_INTERRUPTIBLE 0x00000001
#define TASK_UNINTERRUPTIBLE 0x00000002
#define TASK_DEAD 0x00000080
#define TASK_WAKEKILL 0x00000100
#define TASK_NOLOAD 0x00000400
#define TASK_KILLABLE (TASK_WAKEKILL | TASK_UNINTERRUPTIBLE)
#define TASK_IDLE (TASK_UNINTERRUPTIBLE | TASK_NOLOAD)
#define TASK_NORMAL (TASK_INTERRUPTIBLE | TASK_UNINTERRUPTIBLE)
/* Embedded in the native Thread. current is borrowed; get_task_struct pins
 * that owner across exit. Linux address spaces and scheduler internals are
 * deliberately absent until their native implementations exist. */
struct task_struct {
    void *vinix_thread;
    int pid, tgid;
    unsigned int flags;
    unsigned int __state;
    raw_spinlock_t vinix_wait_lock;
    char comm[TASK_COMM_LEN];
    char vinix_initial_comm[TASK_COMM_LEN];
    /* Fits the native view tail padding; nested I/O scopes restore this flag. */
    unsigned int in_iowait;
};
void vinix_linuxkpi_set_task_state(unsigned int state);
#define set_current_state(state) vinix_linuxkpi_set_task_state(state)
#define __set_current_state(state) vinix_linuxkpi_set_task_state(state)
bool vinix_task_is_running(const struct task_struct *);
#define task_is_running vinix_task_is_running
void schedule(void);
int io_schedule_prepare(void) __must_check;
void io_schedule_finish(int token);
void io_schedule(void);
long io_schedule_timeout(long timeout);
#define MAX_SCHEDULE_TIMEOUT LONG_MAX
long schedule_timeout(long timeout);
long schedule_timeout_interruptible(long timeout);
long schedule_timeout_uninterruptible(long timeout);
long schedule_timeout_killable(long timeout);
long schedule_timeout_idle(long timeout);
int wake_up_process(struct task_struct *task);
int wake_up_state(struct task_struct *task, unsigned int state);
int task_pid_nr(const struct task_struct *);
int task_tgid_nr(const struct task_struct *);
bool need_resched(void);
int cond_resched(void);
#endif
