module memory

import aarch64.cpu

// Retype private PMM backing before it is published, or after its final user
// and GPU aliases have retired. All HHDM leaves already exist for PMM RAM.
// Validate the entire span before cache maintenance or any descriptor write;
// looking up existing leaves under the same lock cannot allocate or fail later.
pub fn set_ram_direct_map_uncached(phys u64, length u64, uncached bool) bool {
	if !vmm_initialised || length == 0 || phys % kernel_page_size != 0
		|| length % kernel_page_size != 0 || phys > ~u64(0) - length
		|| phys > ~u64(0) - higher_half || phys + higher_half > ~u64(0) - length {
		return false
	}
	if cpu.read_ttbr1_el1() & kernel_pte_address_mask != u64(kernel_pagemap.top_level) & kernel_pte_address_mask {
		return false
	}
	end := phys + length
	expected_attr := if uncached { arm64_pte_attr_normal } else { arm64_pte_attr_uncached }
	new_attr := if uncached { arm64_pte_attr_uncached } else { arm64_pte_attr_normal }
	new_shareability := if uncached { u64(2) << 8 } else { arm64_pte_sh_inner }
	kernel_pagemap.l.acquire()
	defer { kernel_pagemap.l.release() }
	for page := phys; page < end; page += kernel_page_size {
		entry := kernel_pagemap.kernel_virt2pte(page + higher_half, false) or { return false }
		old := unsafe { *entry }
		if old & arm64_pte_valid != arm64_pte_valid || old & kernel_pte_address_mask != page
			|| old & arm64_pte_ap_ro != 0 || old & (u64(7) << 2) != expected_attr {
			return false
		}
	}
	if uncached { cpu.clean_invalidate_data_cache_to_poc(phys + higher_half, length) }
	else { cpu.dsb_sy() }
	for page := phys; page < end; page += kernel_page_size {
		mut entry := kernel_pagemap.kernel_virt2pte(page + higher_half, false) or {
			panic('validated RAM direct-map leaf disappeared under lock')
		}
		old := unsafe { *entry }
		new_pte := (old & ~((u64(7) << 2) | (u64(3) << 8))) | new_attr | new_shareability
		install_arm64_pte(mut entry, page + higher_half, new_pte, true)
	}
	cpu.dsb_sy()
	cpu.isb()
	return true
}
