/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_SMP_MASKS_V_CONTRACT_H
#define VINIX_LINUXKPI_SMP_MASKS_V_CONTRACT_H
#include "linuxkpi_smp_masks_v_primitives.h"
#include "linuxkpi_common_v_contract.h"
#include <linux/cpumask.h>

/* Every record and constant has its original Linux owner. V borrows actual
 * fields; it neither redeclares a native cpumask record nor exports globals. */
typedef const struct cpumask *vkms_const_cpumask;
_Static_assert(NR_CPUS == VKM_CPU_LIMIT && BITS_PER_LONG == 64,
	"native installed-CPU mask profile");
_Static_assert(sizeof(struct cpumask) == VKM_MASK_WORDS * sizeof(uint64_t) &&
	__builtin_offsetof(struct cpumask, bits) == 0,
	"original CPU-mask word storage");
_Static_assert(sizeof(atomic_t) == sizeof(int32_t) &&
	__builtin_offsetof(atomic_t, counter) == 0,
	"original online-counter field storage");
_Static_assert(sizeof(nr_cpu_ids) == sizeof(uint32_t),
	"original logical CPU bound storage");
#ifndef VINIX_LINUXKPI_HOST_TEST
_Static_assert(__builtin_types_compatible_p(uint64_t, unsigned long),
	"native V words preserve the original unsigned-long mask type");
#endif
_Static_assert(sizeof(cpu_bit_bitmap) == 65 * 4 * sizeof(uint64_t) &&
	sizeof(cpu_all_bits) == 4 * sizeof(uint64_t),
	"original compressed constant mask storage");
#if defined(CONFIG_INIT_ALL_POSSIBLE) || defined(CONFIG_FORCE_NR_CPUS)
#error Native boot masks require mutable installed-CPU storage
#endif

/* Original public constants and bitmap access, without a replacement loop.
 * These are used only for read-only queries bounded by the physical NR_CPUS
 * storage. cpumask_test_cpu is reserved for installed IDs below nr_cpu_ids. */
#define vkms_all_mask() (cpu_all_mask)
#define vkms_const_bits(mask) cpumask_bits(mask)
#endif
