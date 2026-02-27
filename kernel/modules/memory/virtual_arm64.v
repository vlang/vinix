@[has_globals]
module memory

import lib
import limine
import aarch64.cpu

// ARM64 output address mask: bits [47:12]
pub const pte_flags_mask = u64(0x0000_FFFF_FFFF_F000)

// ARM64-internal PTE bits
const arm64_pte_valid = u64(0b11)
const arm64_pte_af = u64(1) << 10
const arm64_pte_sh_inner = u64(3) << 8
const arm64_pte_ap_ro = u64(1) << 7 // AP[2]=1 -> read-only
const arm64_pte_ap_user = u64(1) << 6 // AP[1]=1 -> EL0 access
const arm64_pte_pxn = u64(1) << 53
const arm64_pte_uxn = u64(1) << 54
const arm64_pte_attr_normal = u64(0) << 2 // MAIR index 0 (Normal Write-Back Cacheable)
const arm64_pte_attr_device = u64(1) << 2 // MAIR index 1 (Device-nGnRnE)
const arm64_pte_attr_uncached = u64(2) << 2 // MAIR index 2 (Normal Non-Cacheable)
const arm64_pte_table = u64(0b11)

// Translate portable flags into an ARM64 L3 page descriptor.
fn portable_to_arm64_pte(phys u64, flags u64) u64 {
	mut attr := arm64_pte_attr_normal
	mut sh := arm64_pte_sh_inner
	if flags & pte_device != 0 {
		attr = arm64_pte_attr_device
		sh = u64(0) // Device memory must not be shareable
	} else if flags & pte_uncached != 0 {
		attr = arm64_pte_attr_uncached
		// Non-cacheable memory uses outer shareable for framebuffers
		sh = u64(2) << 8 // Outer Shareable
	}
	mut pte := (phys & pte_flags_mask) | arm64_pte_valid | arm64_pte_af | sh | attr

	if flags & pte_noexec != 0 {
		pte |= arm64_pte_pxn | arm64_pte_uxn
	}

	// ARM64: AP[2]=0 means writable, AP[2]=1 means read-only.
	// The portable convention: pte_writable SET = writable.
	if flags & pte_writable == 0 {
		pte |= arm64_pte_ap_ro
	}

	if flags & pte_user != 0 {
		pte |= arm64_pte_ap_user
	}

	return pte
}

pub fn new_pagemap() &Pagemap {
	mut top_level := &u64(pmm_alloc(1))
	if top_level == 0 {
		panic('new_pagemap() allocation failure')
	}

	// On ARM64, TTBR1 handles kernel space. User pagemaps (TTBR0) do
	// not need higher-half entries copied.
	return &Pagemap{
		top_level:   top_level
		mmap_ranges: []voidptr{}
	}
}

pub fn (pagemap &Pagemap) virt2pte(virt u64, allocate bool) ?&u64 {
	// ARM64 4-level with 4KB granule: L0[47:39] L1[38:30] L2[29:21] L3[20:12]
	l0_entry := (virt & (u64(0x1ff) << 39)) >> 39
	l1_entry := (virt & (u64(0x1ff) << 30)) >> 30
	l2_entry := (virt & (u64(0x1ff) << 21)) >> 21
	l3_entry := (virt & (u64(0x1ff) << 12)) >> 12

	l0 := pagemap.top_level
	l1 := get_next_level(l0, l0_entry, allocate) or { return none }
	l2 := get_next_level(l1, l1_entry, allocate) or { return none }
	l3 := get_next_level(l2, l2_entry, allocate) or { return none }

	return unsafe { &u64(u64(&l3[l3_entry]) + higher_half) }
}

pub fn (pagemap &Pagemap) virt2phys(virt u64) ?u64 {
	pte_p := pagemap.virt2pte(virt, false) or { return none }
	if unsafe { *pte_p } & 1 == 0 {
		return none
	}
	return unsafe { *pte_p } & pte_flags_mask
}

pub fn (mut pagemap Pagemap) switch_to() {
	top_level := u64(pagemap.top_level)
	cpu.write_ttbr0_el1(top_level)
	cpu.isb()
	cpu.tlbi_vmalle1()
}

fn get_next_level(current_level &u64, index u64, allocate bool) ?&u64 {
	mut ret := unsafe { &u64(0) }
	mut entry := unsafe { &u64(u64(current_level) + higher_half + index * 8) }

	if unsafe { *entry } & 0x01 != 0 {
		ret = unsafe { &u64(*entry & pte_flags_mask) }
	} else {
		if allocate == false {
			return none
		}
		ret = pmm_alloc(1)
		if ret == 0 {
			return none
		}
		unsafe {
			*entry = u64(ret) | arm64_pte_table
		}
	}
	return ret
}

pub fn (mut pagemap Pagemap) unmap_page(virt u64) ? {
	l0_entry := (virt & (u64(0x1ff) << 39)) >> 39
	l1_entry := (virt & (u64(0x1ff) << 30)) >> 30
	l2_entry := (virt & (u64(0x1ff) << 21)) >> 21
	l3_entry := (virt & (u64(0x1ff) << 12)) >> 12

	mut l0 := pagemap.top_level
	mut l1 := get_next_level(l0, l0_entry, false) or { return none }
	mut l1_p := unsafe { &u64(u64(l1) + higher_half) }
	mut l2 := get_next_level(l1, l1_entry, false) or { return none }
	mut l2_p := unsafe { &u64(u64(l2) + higher_half) }
	mut l3 := get_next_level(l2, l2_entry, false) or { return none }
	mut l3_p := unsafe { &u64(u64(l3) + higher_half) }

	mut pte_p := unsafe { &u64(u64(&l3[l3_entry]) + higher_half) }

	unsafe {
		*pte_p = 0

		mut i := u64(0)
		for ; i < 512; i++ {
			if l3_p[i] != 0 {
				break
			}
		}
		if i == 512 {
			pmm_free(l3, 1)
			l2_p[l2_entry] = 0
		}

		i = u64(0)
		for ; i < 512; i++ {
			if l2_p[i] != 0 {
				break
			}
		}
		if i == 512 {
			pmm_free(l2, 1)
			l1_p[l1_entry] = 0
		}

		i = u64(0)
		for ; i < 512; i++ {
			if l1_p[i] != 0 {
				break
			}
		}
		if i == 512 {
			pmm_free(l1, 1)
			// Don't free L0 (root table)
		}
	}

	cpu.tlbi_vaae1(virt >> 12)
}

pub fn (mut pagemap Pagemap) flag_page(virt u64, flags u64) ? {
	pte_p := pagemap.virt2pte(virt, false) or { return none }
	phys := unsafe { *pte_p } & pte_flags_mask
	new_pte := portable_to_arm64_pte(phys, flags)
	unsafe {
		*pte_p = new_pte
	}
	cpu.tlbi_vaae1(virt >> 12)
}

pub fn (mut pagemap Pagemap) map_page(virt u64, phys u64, flags u64) ? {
	pagemap.l.acquire()
	defer {
		pagemap.l.release()
	}

	l0_entry := (virt & (u64(0x1ff) << 39)) >> 39
	l1_entry := (virt & (u64(0x1ff) << 30)) >> 30
	l2_entry := (virt & (u64(0x1ff) << 21)) >> 21
	l3_entry := (virt & (u64(0x1ff) << 12)) >> 12

	l0 := pagemap.top_level
	l1 := get_next_level(l0, l0_entry, true) or { return none }
	l2 := get_next_level(l1, l1_entry, true) or { return none }
	mut l3 := get_next_level(l2, l2_entry, true) or { return none }

	entry := unsafe { &u64(u64(l3) + higher_half + l3_entry * 8) }

	new_pte := portable_to_arm64_pte(phys, flags)
	unsafe {
		*entry = new_pte
	}
	// Invalidate any stale TLB entry for this virtual address.
	cpu.tlbi_vaae1(virt >> 12)
}

@[_linker_section: '.requests']
@[cinit]
__global (
	volatile paging_mode_req = limine.LiminePagingModeRequest{
		response: unsafe { nil }
		revision: 1
		mode:     limine.limine_paging_mode_aarch64_4lvl
		max_mode: limine.limine_paging_mode_aarch64_4lvl
		min_mode: limine.limine_paging_mode_aarch64_4lvl
	}
)

pub fn vmm_init() {
	kernel_pagemap.top_level = pmm_alloc(1)
	if kernel_pagemap.top_level == 0 {
		panic('vmm_init() allocation failure')
	}

	// Pre-allocate L1 tables for the kernel half (indices 256..511)
	for i := u64(256); i < 512; i++ {
		get_next_level(kernel_pagemap.top_level, i, true) or { panic('vmm init failure') }
	}

	if kaddr_req.response == unsafe { nil } {
		panic('Kernel address bootloader response missing')
	}
	print('vmm: Kernel physical base: 0x${kaddr_req.response.physical_base:x}\n')
	print('vmm: Kernel virtual base: 0x${kaddr_req.response.virtual_base:x}\n')
	virtual_base := kaddr_req.response.virtual_base
	physical_base := kaddr_req.response.physical_base

	// Map kernel text (executable, read-only)
	text_virt := u64(voidptr(C.text_start))
	text_phys := (text_virt - virtual_base) + physical_base
	text_len := u64(voidptr(C.text_end)) - text_virt
	map_kernel_span(text_virt, text_phys, text_len, pte_present)

	// Map kernel rodata (no-exec, read-only)
	rodata_virt := u64(voidptr(C.rodata_start))
	rodata_phys := (rodata_virt - virtual_base) + physical_base
	rodata_len := u64(voidptr(C.rodata_end)) - rodata_virt
	map_kernel_span(rodata_virt, rodata_phys, rodata_len, pte_present | pte_noexec)

	// Map kernel data (no-exec, read-write)
	data_virt := u64(voidptr(C.data_start))
	data_phys := (data_virt - virtual_base) + physical_base
	data_len := u64(voidptr(C.data_end)) - data_virt
	map_kernel_span(data_virt, data_phys, data_len, pte_present | pte_noexec | pte_writable)

	// Map first 4GB of physical memory into HHDM.
	// QEMU virt device MMIO range (0x00000000-0x3FFFFFFF) uses Device memory type.
	// Everything else uses Normal cacheable.
	for i := u64(0); i < 0x100000000; i += page_size {
		mut flags := pte_present | pte_noexec | pte_writable
		if i < u64(0x40000000) {
			flags |= pte_device
		}
		kernel_pagemap.map_page(i + higher_half, i, flags) or {
			panic('vmm init failure')
		}
	}

	// Map remaining physical memory
	memmap := memmap_req.response
	entries := memmap.entries
	for i := 0; i < memmap.entry_count; i++ {
		base := unsafe { lib.align_down(entries[i].base, page_size) }
		top := unsafe { lib.align_up(entries[i].base + entries[i].length, page_size) }
		if top <= u64(0x100000000) {
			continue
		}
		for j := base; j < top; j += page_size {
			if j < u64(0x100000000) {
				continue
			}
			kernel_pagemap.map_page(j + higher_half, j, pte_present | pte_noexec | pte_writable) or {
				panic('vmm init failure')
			}
		}
	}

	// Remap framebuffer regions as Non-Cacheable.
	// Normal Write-Back Cacheable (the default) causes writes to stay in CPU cache,
	// never reaching the actual display device.
	for k := u64(0); k < memmap.entry_count; k++ {
		entry := unsafe { entries[k] }
		if entry.@type == limine.limine_memmap_framebuffer {
			fb_base := lib.align_down(entry.base, page_size)
			fb_top := lib.align_up(entry.base + entry.length, page_size)
			for pg := fb_base; pg < fb_top; pg += page_size {
				kernel_pagemap.map_page(pg + higher_half, pg, pte_present | pte_noexec | pte_writable | pte_uncached) or {
					panic('vmm init failure: framebuffer remap')
				}
			}
		}
	}

	// Set up MAIR_EL1:
	//   Index 0: Normal Write-Back Cacheable (0xFF)
	//   Index 1: Device-nGnRnE (0x00)
	//   Index 2: Normal Non-Cacheable (0x44)
	mair := u64(0xFF) | (u64(0x00) << 8) | (u64(0x44) << 16)
	cpu.write_mair_el1(mair)

	// Set up TCR_EL1 for 4KB granule, 48-bit VA and a runtime-detected
	// physical address size from ID_AA64MMFR0_EL1.PARange.
	// PARange and TCR.IPS use the same encoding.
	mmfr0 := cpu.read_id_aa64mmfr0_el1()
	mut tcr_ips := (mmfr0 >> 0) & 0xf
	if tcr_ips > 6 {
		// Fallback to 48-bit PA if the encoding is unknown/reserved.
		tcr_ips = 5
	}
	tcr := u64(16) | // T0SZ = 16 -> 48-bit user VA
		(u64(16) << 16) | // T1SZ = 16 -> 48-bit kernel VA
		(u64(0b00) << 14) | // TG0 = 4KB granule (TTBR0)
		(u64(0b10) << 30) | // TG1 = 4KB granule (TTBR1)
		(tcr_ips << 32) | // IPS = physical address size
		(u64(0b11) << 12) | // SH0 = inner shareable
		(u64(0b11) << 28) | // SH1 = inner shareable
		(u64(0b01) << 10) | // ORGN0 = Write-Back
		(u64(0b01) << 26) | // ORGN1 = Write-Back
		(u64(0b01) << 8) | // IRGN0 = Write-Back
		(u64(0b01) << 24) // IRGN1 = Write-Back
	cpu.write_tcr_el1(tcr)

	// Load TTBR1 with kernel page tables
	cpu.write_ttbr1_el1(u64(kernel_pagemap.top_level))
	// Load TTBR0 with kernel page tables (replaced per-process later)
	cpu.write_ttbr0_el1(u64(kernel_pagemap.top_level))

	cpu.tlbi_vmalle1()
	cpu.dsb_sy()
	cpu.isb()

	vmm_initialised = true
}
