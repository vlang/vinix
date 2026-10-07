/* SPDX-License-Identifier: GPL-2.0-only */
/* Original constant CPU-mask data from Linux 6.6.157 kernel/cpu.c.
 * CPU control: (C) 2001, 2002, 2003, 2004 Rusty Russell, licensed under GPL.
 * Only compiler-owned data lives here; native publication lives in V.
 */
#ifdef VINIX_LINUXKPI
#include <linux/cache.h>
#include <linux/cpumask.h>

#if defined(CONFIG_INIT_ALL_POSSIBLE) || defined(CONFIG_FORCE_NR_CPUS)
#error Native boot masks require the installed-CPU compiler profile
#endif

_Static_assert(NR_CPUS == 256 && BITS_PER_LONG == 64,
	"native boot CPU mask compiler profile");
_Static_assert(sizeof(struct cpumask) == 32 && sizeof(atomic_t) == 4,
	"original CPU mask and online-counter storage");

/* cpu_bit_bitmap[0] is empty - so we can back into it */
#define MASK_DECLARE_1(x)	[x+1][0] = (1UL << (x))
#define MASK_DECLARE_2(x)	MASK_DECLARE_1(x), MASK_DECLARE_1(x+1)
#define MASK_DECLARE_4(x)	MASK_DECLARE_2(x), MASK_DECLARE_2(x+2)
#define MASK_DECLARE_8(x)	MASK_DECLARE_4(x), MASK_DECLARE_4(x+4)

const unsigned long cpu_bit_bitmap[BITS_PER_LONG+1][BITS_TO_LONGS(NR_CPUS)] = {

	MASK_DECLARE_8(0),	MASK_DECLARE_8(8),
	MASK_DECLARE_8(16),	MASK_DECLARE_8(24),
#if BITS_PER_LONG > 32
	MASK_DECLARE_8(32),	MASK_DECLARE_8(40),
	MASK_DECLARE_8(48),	MASK_DECLARE_8(56),
#endif
};

const DECLARE_BITMAP(cpu_all_bits, NR_CPUS) = CPU_BITS_ALL;

/* Genuine original storage declarations. The sole native boot owner publishes
 * its installed logical CPUs before compatibility users; no hotplug updater
 * or fabricated firmware CPU population is supplied.
 */
struct cpumask __cpu_possible_mask __read_mostly;
struct cpumask __cpu_online_mask __read_mostly;
struct cpumask __cpu_present_mask __read_mostly;
struct cpumask __cpu_active_mask __read_mostly;
struct cpumask __cpu_dying_mask __read_mostly;
atomic_t __num_online_cpus __read_mostly;
unsigned int nr_cpu_ids __read_mostly = NR_CPUS;
#endif
