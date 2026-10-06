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
/* Keep this first: kernel.h must supply the original integer helpers itself. */
#include <linux/kernel.h>
#include <assert.h>

_Static_assert(U32_MAX == 0xffffffffU && S32_MAX == 2147483647, "kernel limits visibility");
_Static_assert(U64_MAX == 0xffffffffffffffffULL, "64-bit kernel limits visibility");
_Static_assert(BIT(5) == 32, "kernel bit constants must be available");
_Static_assert(const_ilog2(1ULL << 63) == 63, "64-bit constant logarithm");
_Static_assert(__builtin_types_compatible_p(__typeof__(kstrtoull),
        int(const char *, unsigned int, unsigned long long *)), "kernel unsigned parser visibility");
_Static_assert(__builtin_types_compatible_p(__typeof__(kstrtoll),
        int(const char *, unsigned int, long long *)), "kernel signed parser visibility");
_Static_assert(__builtin_types_compatible_p(__typeof__(kstrtobool),
        int(const char *, bool *)), "kernel Boolean parser visibility");

typedef volatile unsigned long vks_volatile_ulong;
typedef volatile u32 vks_volatile_u32;
typedef volatile u64 vks_volatile_u64;
_Static_assert(BITS_PER_LONG == 64, "V native word width");
#if defined(__clang__) && defined(VINIX_LINUXKPI_HOST_TEST)
#pragma clang diagnostic pop
#endif
#undef fls
#undef ffs
#undef timezone
#undef u64
