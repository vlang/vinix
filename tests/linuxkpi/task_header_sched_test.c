/* SPDX-License-Identifier: GPL-2.0-only */
/* Keep sched.h first: original fence headers depend on its ktime types. */
#include <linux/sched.h>
#include <assert.h>

_Static_assert(PF_VCPU == 0x00000001, "Linux 6.6 PF_VCPU value");
_Static_assert(PF_EXITING == 0x00000004, "Linux 6.6 PF_EXITING value");
_Static_assert(sizeof(ktime_t) == sizeof(s64), "sched.h supplies original ktime_t");

int main(void)
{
    ktime_t value = ktime_set(1, 123);
    assert(ktime_to_ns(value) == 1000000123LL);
    assert(ktime_to_ns(ktime_add_ns(value, 77)) == 1000000200LL);
    assert(ktime_to_ns(ktime_sub_ns(value, 124)) == 999999999LL);
    assert(ktime_set(KTIME_SEC_MAX, 0) == KTIME_MAX);
    assert(ktime_before(value, value + 1));
    assert(ktime_after(value, value - 1));
    return 0;
}
