/* V backend scalar names differ from the unchanged Linux native typedefs. */
#undef atomic_fetch_add
#undef atomic_fetch_sub
#undef atomic_fetch_and
#undef atomic_fetch_or
#undef atomic_fetch_xor
#undef atomic_exchange
#undef atomic_compare_exchange_strong
#undef atomic_compare_exchange_weak
#define u64 vks_linux_u64
#define timezone vks_linux_timezone
#define ffs vks_linux_ffs
#define fls vks_linux_fls
#if defined(__clang__) && defined(VINIX_LINUXKPI_HOST_TEST)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmacro-redefined"
#endif
/* SPDX-License-Identifier: GPL-2.0-only */
/* Keep sched.h first: original fence headers depend on its ktime types. */
#include <linux/sched.h>
#include <assert.h>

_Static_assert(PF_VCPU == 0x00000001, "Linux 6.6 PF_VCPU value");
_Static_assert(PF_EXITING == 0x00000004, "Linux 6.6 PF_EXITING value");
_Static_assert(sizeof(ktime_t) == sizeof(s64), "sched.h supplies original ktime_t");

#include <linux/string.h>
_Static_assert(sizeof(ktime_t) == sizeof(int64_t), "native ktime scalar width");
#if defined(__clang__) && defined(VINIX_LINUXKPI_HOST_TEST)
#pragma clang diagnostic pop
#endif
#undef fls
#undef ffs
#undef timezone
#undef u64
