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
/* Keep ww_mutex.h first: mutex.h must provide current before its inlines. */
#include <linux/ww_mutex.h>
#include <linux/sched.h>
#include <assert.h>

#if defined(__clang__) && defined(VINIX_LINUXKPI_HOST_TEST)
#pragma clang diagnostic pop
#endif
#undef fls
#undef ffs
#undef timezone
#undef u64
