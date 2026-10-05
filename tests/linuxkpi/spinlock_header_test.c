/* SPDX-License-Identifier: GPL-2.0-only */
/* Keep this first: original x86 spinlocks expose the CPU hint transitively. */
#include <linux/spinlock.h>
_Static_assert(__builtin_types_compatible_p(__typeof__(&cpu_relax), void (*)(void)),
               "spinlock headers must expose the native CPU hint");
int main(void) { return 0; }
