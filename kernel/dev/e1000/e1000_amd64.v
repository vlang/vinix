module e1000

import memory
import x86.kio

// Page attribute bits: PWT and PCD together select the uncached PAT entry.
const pte_write_through = u64(1) << 3
const pte_cache_disable = u64(1) << 4

// The kernel's direct map already covers the first 4 GiB, which is where a
// 32-bit BAR -- every card this drives has one -- always is, and the
// firmware's MTRRs make the PCI hole there uncached. A BAR above that is
// mapped here, uncached.
fn map_registers(phys u64, length u64) u64 {
	hhdm := memory.get_hhdm_offset()
	if phys + length <= u64(0x100000000) {
		return phys + hhdm
	}
	flags := memory.pte_present | memory.pte_writable | memory.pte_noexec | pte_write_through | pte_cache_disable
	for page := phys & ~u64(0xfff); page < phys + length; page += 0x1000 {
		kernel_pagemap.map_page(page + hhdm, page, flags) or { return 0 }
	}
	return phys + hhdm
}

fn reg_read(offset u64) u32 {
	return kio.mmin[u32](unsafe { &u32(e1000_regs + offset) })
}

fn reg_write(offset u64, value u32) {
	kio.mmout[u32](unsafe { &u32(e1000_regs + offset) }, value)
}

// Order the descriptor and buffer accesses against each other and against the
// register writes that hand them to the card.
fn dma_barrier() {
	asm volatile amd64 {
		mfence
		; ; ; memory
	}
}
