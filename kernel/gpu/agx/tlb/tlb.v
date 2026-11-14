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
// covers intermediate walk caches. Global firmware mappings require
// invalidate_all(); edits within one nonglobal mapping use invalidate_range().
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

// Vinix/aarch64 and the G13 UAT both use 16 KiB pages. The reference's 4 KiB
// CPU adjustment and newer-SoC page-TLBI quirk therefore do not apply here.
pub fn invalidate_range(asid u8, address u64, size u64) {
	plan := range_plan(asid, address, size) or { return }
	asm volatile aarch64 {
		dsb sy
		; ; ; memory
	}
	for index := u64(0); index < plan.count; index++ {
		operand := plan.operand(index) or { break }
		if plan.page {
			asm volatile aarch64 {
				tlbi vae1os, operand
				; ; r (operand)
				; memory
			}
		} else {
			asm volatile aarch64 {
				tlbi rvae1os, operand
				; ; r (operand)
				; memory
			}
		}
	}
	asm volatile aarch64 {
		dsb sy
		; ; ; memory
	}
}
