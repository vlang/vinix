/* SPDX-License-Identifier: GPL-2.0-only */
/* I/O scheduling scopes and bit actions follow Linux 6.6.157
 * kernel/sched/core.c and kernel/sched/wait_bit.c. Native queue transitions
 * maintain the real blocked-CPU counts independently of these intent tokens. */
#ifdef VINIX_LINUXKPI
#include <linux/sched.h>
#include <linux/sched/signal.h>
#include <linux/init.h>
#include <linux/bitops.h>
#include <linux/wait_bit.h>
#include <linux/jiffies.h>
#include <linux/bug.h>
#include <linux/errno.h>
#include <vinix/runtime.h>

bool vinix_linuxkpi_task_in_iowait(const void *storage)
{
    const struct task_struct *task = storage;
    /* The native scheduler calls this under its queue lock. Do not acquire
     * compatibility locks, query current, or change IRQ state here. */
    return __atomic_load_n(&task->in_iowait, __ATOMIC_ACQUIRE) != 0;
}

int io_schedule_prepare(void)
{
    return __atomic_exchange_n(&current->in_iowait, 1, __ATOMIC_ACQ_REL);
}

void io_schedule_finish(int token)
{
    BUG_ON(token != 0 && token != 1);
    __atomic_store_n(&current->in_iowait, token, __ATOMIC_RELEASE);
}

void io_schedule(void)
{
    int token = io_schedule_prepare();
    schedule();
    io_schedule_finish(token);
}

long io_schedule_timeout(long timeout)
{
    int token = io_schedule_prepare();
    long result = schedule_timeout(timeout);
    io_schedule_finish(token);
    return result;
}

unsigned int nr_iowait_cpu(int cpu)
{
    BUG_ON(cpu < 0 || (unsigned int)cpu >= vinix_linuxkpi_percpu_count());
    return vinix_linuxkpi_iowait_count(cpu);
}

unsigned int nr_iowait(void)
{
    unsigned int result = 0;
    unsigned int count = vinix_linuxkpi_percpu_count();
    for (unsigned int cpu = 0; cpu < count; cpu++) {
        unsigned int blocked = vinix_linuxkpi_iowait_count(cpu);
        BUG_ON(blocked > ~0U - result);
        result += blocked;
    }
    return result;
}

int bit_wait_io(struct wait_bit_key *key, int mode)
{
    io_schedule();
    return signal_pending_state(mode, current) ? -EINTR : 0;
}

int bit_wait_io_timeout(struct wait_bit_key *key, int mode)
{
    unsigned long now = READ_ONCE(jiffies);
    if (time_after_eq(now, key->timeout)) return -EAGAIN;
    io_schedule_timeout(key->timeout - now);
    return signal_pending_state(mode, current) ? -EINTR : 0;
}

/* CONFIG_BLOCK and CONFIG_TASK_DELAY_ACCT are disabled. No block-plug,
 * per-task delay statistics or CPU idle-time service is supplied here. */
#endif
