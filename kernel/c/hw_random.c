/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <stdint.h>

/*
 * One 64-bit word from the CPU's own random number generator: RDSEED, or
 * RDRAND, on x86-64; RNDR on arm64 where FEAT_RNG has it (QEMU's max CPU,
 * not the M1). Answers 0 when there is none or it keeps failing. Cheap enough
 * to call when the kernel generator reseeds, unlike its boot-time sources.
 */
int vinix_hw_random64(uint64_t *out)
{
#if defined(__x86_64__)
	uint32_t a, b, c, d;
	__asm__ volatile("cpuid" : "=a"(a), "=b"(b), "=c"(c), "=d"(d) : "a"(7), "c"(0));
	int have_rdseed = (b >> 18) & 1;
	__asm__ volatile("cpuid" : "=a"(a), "=b"(b), "=c"(c), "=d"(d) : "a"(1), "c"(0));
	int have_rdrand = (c >> 30) & 1;
	for (int i = 0; i < 32; i++) {
		uint64_t value;
		unsigned char ok = 0;
		if (have_rdseed)
			__asm__ volatile("rdseed %0; setc %1" : "=r"(value), "=qm"(ok) : : "cc");
		else if (have_rdrand)
			__asm__ volatile("rdrand %0; setc %1" : "=r"(value), "=qm"(ok) : : "cc");
		else
			return 0;
		if (ok) {
			*out = value;
			return 1;
		}
	}
	return 0;
#elif defined(__aarch64__)
	uint64_t isar0;
	__asm__ volatile("mrs %0, id_aa64isar0_el1" : "=r"(isar0));
	if (((isar0 >> 60) & 0xf) == 0)
		return 0;
	for (int i = 0; i < 32; i++) {
		uint64_t value, ok;
		__asm__ volatile("mrs %0, s3_3_c2_c4_0\n\tcset %1, ne" : "=r"(value), "=r"(ok) : : "cc");
		if (ok) {
			*out = value;
			return 1;
		}
	}
	return 0;
#else
	(void)out;
	return 0;
#endif
}
