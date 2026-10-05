/* SPDX-License-Identifier: GPL-2.0-only */
/* Keep this first: bit_spinlock callers rely on preempt's CPU hint import. */
#include <linux/preempt.h>
_Static_assert(__builtin_types_compatible_p(__typeof__(&cpu_relax), void (*)(void)),
               "preempt headers must expose the native CPU hint");
int main(void) { return 0; }
