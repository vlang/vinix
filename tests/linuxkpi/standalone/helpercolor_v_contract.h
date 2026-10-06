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
/* Keep this first: a prior kernel.h include would conceal missing dependencies
 * of the unchanged DRM header's LUT rounding and clamp implementation. */
#include <drm/drm_color_mgmt.h>
#include <assert.h>

typedef volatile u32 vks_volatile_u32;
typedef volatile int vks_volatile_int;
#if defined(__clang__) && defined(VINIX_LINUXKPI_HOST_TEST)
#pragma clang diagnostic pop
#endif
#undef fls
#undef ffs
#undef timezone
#undef u64
