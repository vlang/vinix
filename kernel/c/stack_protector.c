// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The kernel's stack protector, as OpenBSD has built its kernel with
// ProPolice since 2003. The kernel is compiled with -fstack-protector-strong
// -mstack-protector-guard=global: every function with a buffer or an
// address-taken local puts __stack_chk_guard below its return address on
// entry and checks it before returning, so an overflow that reaches the
// return address has to have written the guard back too, which it cannot
// know. A mismatch panics instead of returning into whatever the overflow
// wrote.

#include <stdint.h>

// A placeholder until vinix_stack_guard_init() runs, first thing on the boot
// CPU. Every function that runs before that is one that never returns.
uintptr_t __stack_chk_guard = 0x595e9fbd94fda700;

// lib.kpanic(), which takes the saved registers or NULL.
void lib__kpanic(void *gpr_state, const char *message);

__attribute__((noreturn)) void __stack_chk_fail(void)
{
	lib__kpanic(0, "stack protector: a stack frame was overwritten past its buffers");
	__builtin_unreachable();
}

__attribute__((no_stack_protector)) static uint64_t mix64(uint64_t value)
{
	value ^= value >> 30;
	value *= 0xbf58476d1ce4e5b9ULL;
	value ^= value >> 27;
	value *= 0x94d049bb133111ebULL;
	value ^= value >> 31;
	return value;
}

#if defined(__x86_64__)
__attribute__((no_stack_protector)) static uint64_t boot_entropy(void)
{
	uint32_t low, high;
	__asm__ volatile("rdtsc" : "=a"(low), "=d"(high));
	uint64_t entropy = ((uint64_t)high << 32) | low;

	uint32_t eax = 1, ebx, ecx = 0, edx;
	__asm__ volatile("cpuid" : "+a"(eax), "=b"(ebx), "+c"(ecx), "=d"(edx));
	if (ecx & (1u << 30)) {
		// RDRAND. It can run dry for a moment; a few tries are plenty.
		for (int i = 0; i < 16; i++) {
			uint64_t value;
			unsigned char ok;
			__asm__ volatile("rdrand %0; setc %1" : "=r"(value), "=qm"(ok) : : "cc");
			if (ok) {
				entropy = mix64(entropy) ^ value;
				break;
			}
		}
	}
	return entropy;
}
#elif defined(__aarch64__)
__attribute__((no_stack_protector)) static uint64_t boot_entropy(void)
{
	uint64_t entropy;
	__asm__ volatile("mrs %0, cntvct_el0" : "=r"(entropy));

	uint64_t isar0;
	__asm__ volatile("mrs %0, id_aa64isar0_el1" : "=r"(isar0));
	if ((isar0 >> 60) & 0xf) {
		// RNDR, where FEAT_RNG has it. QEMU's max CPU does; the M1 does not,
		// and has only the counter's jitter since reset.
		for (int i = 0; i < 16; i++) {
			uint64_t value, ok;
			__asm__ volatile("mrs %0, s3_3_c2_c4_0\n\tcset %1, ne"
			    : "=r"(value), "=r"(ok) : : "cc");
			if (ok) {
				entropy = mix64(entropy) ^ value;
				break;
			}
		}
	}
	return entropy;
}
#endif

// Replace the placeholder guard. Called first thing by kmain() on the boot
// CPU, before any function that will return has put the placeholder in its
// frame; it cannot be protected itself, since it changes the guard its own
// frame would be checked against.
__attribute__((no_stack_protector)) void vinix_stack_guard_init(void)
{
	uint64_t guard = boot_entropy();
	// The boot stack's address, which the loader may place anywhere.
	guard ^= (uint64_t)(uintptr_t)&guard;
	guard = mix64(guard ^ __stack_chk_guard);
	// The lowest byte is zero, as glibc makes it: an overflow by a string
	// function has to write a terminator where the guard's first byte is,
	// and stops there.
	__stack_chk_guard = (uintptr_t)(guard & ~(uint64_t)0xff);
}
