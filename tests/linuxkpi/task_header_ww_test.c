/* SPDX-License-Identifier: GPL-2.0-only */
/* Keep ww_mutex.h first: mutex.h must provide current before its inlines. */
#include <linux/ww_mutex.h>
#include <linux/sched.h>
#include <assert.h>

static struct task_struct header_test_task;
struct task_struct *vinix_linuxkpi_current_task(void)
{
    return &header_test_task;
}

int main(void)
{
    DEFINE_WW_CLASS(wound_wait);
    DEFINE_WD_CLASS(wait_die);
    struct ww_acquire_ctx first, second, other;
    header_test_task.flags = PF_VCPU;
    ww_acquire_init(&first, &wound_wait);
    ww_acquire_init(&second, &wound_wait);
    ww_acquire_init(&other, &wait_die);
    assert(first.task == &header_test_task && second.task == first.task && other.task == first.task);
    assert(first.stamp == 1 && second.stamp == 2 && other.stamp == 1);
    assert(!first.acquired && !first.wounded && !first.is_wait_die);
    assert(!other.acquired && !other.wounded && other.is_wait_die);
    assert(header_test_task.flags == PF_VCPU);
    ww_acquire_done(&first);
    ww_acquire_fini(&first);
    ww_acquire_fini(&second);
    ww_acquire_fini(&other);
    return 0;
}
