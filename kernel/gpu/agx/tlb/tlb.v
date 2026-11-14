// SPDX-License-Identifier: GPL-2.0-or-later
module tlb

// Apple UAT listens to the CPU's outer-shareable TLBI broadcasts. CPU-local
// and inner-shareable invalidations do not reach the GPU. Ported from
// drivers/gpu/drm/asahi/mem.rs in Omarchy's linux-aurora driver.
// Both barriers are required: publish the PTE/root before invalidating, then
// wait for completion before firmware uses the new mapping or backing is freed.
pub fn invalidate_all() {
	asm volatile aarch64 {
		dsb sy
		tlbi vmalle1os
		dsb sy
		; ; ; memory
	}
}

// UAT uses eight-bit ASIDs in TTBR[55:48]. Invalidating the entire ASID also
// covers intermediate walk caches. This deliberately uses the reference's
// ASID fallback instead of range instructions whose encoding depends on the
// CPU page granule. Global firmware mappings require invalidate_all().
pub fn invalidate_asid(asid u8) {
	operand := u64(asid) << 48
	asm volatile aarch64 {
		dsb sy
		tlbi aside1os, operand
		dsb sy
		; ; r (operand)
		; memory
	}
}
