/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifdef VINIX_LINUXKPI
#include <linux/bug.h>
#include <linux/errno.h>
#include <linux/sched.h>
#include <linux/sched/signal.h>
#include <linux/smp.h>
#include <linux/string.h>

/* Must match proc.Thread.linuxkpi_task, an aligned, zeroed 64-byte buffer.
 * No allocation or independent lifetime: the running native thread owns it. */
_Static_assert(sizeof(struct task_struct) <= 64, "native task view buffer is too small");
_Static_assert(_Alignof(struct task_struct) <= _Alignof(u64), "native task view alignment");

static void copy_comm(char *destination, const char *name, size_t length)
{
    size_t count = length < TASK_COMM_LEN - 1 ? length : TASK_COMM_LEN - 1;
    if (count) memcpy(destination, name, count);
    memset(destination + count, 0, TASK_COMM_LEN - count);
}

void vinix_linuxkpi_task_init(void *storage, void *thread, int pid, int tgid,
                            const char *name, size_t length)
{
    BUG_ON(!storage || !thread);
    struct task_struct *task = storage;
    task->vinix_thread = thread;
    task->pid = pid;
    task->tgid = tgid;
    task->flags = 0;
    copy_comm(task->vinix_initial_comm, name, length);
    memcpy(task->comm, task->vinix_initial_comm, TASK_COMM_LEN);
}

void vinix_linuxkpi_task_inherit(void *storage, void *thread, int pid, int tgid,
                               const void *source)
{
    const struct task_struct *parent = source;
    vinix_linuxkpi_task_init(storage, thread, pid, tgid, parent->comm, TASK_COMM_LEN);
}

void *vinix_linuxkpi_task_view(void *storage, void *thread, int pid, int tgid,
                             const char *name, size_t length, bool exiting)
{
    BUG_ON(!storage || !thread);
    struct task_struct *task = storage;
    BUG_ON(task->vinix_thread != thread);
    task->pid = pid;
    task->tgid = tgid;
    task->flags = exiting ? PF_EXITING : 0;
    if (length) copy_comm(task->comm, name, length);
    else memcpy(task->comm, task->vinix_initial_comm, TASK_COMM_LEN);
    return task;
}

int vinix_linuxkpi_task_selftest(void)
{
    struct task_struct *task = current;
    int pid = task_pid_nr(task), tgid = task_tgid_nr(task);
    if (!task->comm[0] || strnlen(task->comm, TASK_COMM_LEN) == TASK_COMM_LEN) return -EIO;
    unsigned int cpu = get_cpu();
    int result = 0;
    if (smp_processor_id() != cpu || raw_smp_processor_id() != cpu || cond_resched()) result = -EIO;
    put_cpu();
    unsigned long flags = vinix_linuxkpi_irq_save();
    if (cond_resched()) result = -EIO;
    vinix_linuxkpi_irq_restore(flags);
    if (cond_resched() != 1 || current != task || task_pid_nr(task) != pid ||
        task_tgid_nr(task) != tgid) result = -EIO;
    return result;
}
#endif
