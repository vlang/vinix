// SPDX-License-Identifier: GPL-2.0-or-later
module nvme

import memory

// Register and doorbell pages stay mapped for this boot-lived controller.
// PWT+PCD selects the x86 uncached PAT entry; never assume a high PCI BAR is
// part of the RAM direct map. The caller bounds the aperture to its BAR size.
fn map_registers(phys u64, length u64) u64 {
	hhdm := memory.get_hhdm_offset()
	if phys == 0 || length == 0 || length > 1024 * 1024
		|| phys > u64(-1) - hhdm || length > u64(-1) - hhdm - phys { return 0 }
	flags := memory.pte_present | memory.pte_writable | memory.pte_noexec | (u64(1) << 3) | (u64(1) << 4)
	for page := phys & ~u64(0xfff); page < phys + length; page += 4096 {
		kernel_pagemap.map_page(page + hhdm, page, flags) or { return 0 }
	}
	return phys + hhdm
}

fn map_doorbells(phys u64, size u64, strides u64) bool {
	if strides > 15 { return false }
	stride := u64(4) << strides
	// SQ0, CQ0, SQ1, CQ1: the final register occupies four bytes, not
	// a whole trailing stride. Map touched pages without the stride gaps.
	end := page_size + 3 * stride + 4
	if end > size || phys > u64(-1) - end { return false }
	mut previous := u64(-1)
	for index := u64(0); index < 4; index++ {
		address := phys + page_size + index * stride
		page := address & ~u64(0xfff)
		if page == previous { continue }
		if map_registers(address, 4) == 0 { return false }
		previous = page
	}
	return true
}
