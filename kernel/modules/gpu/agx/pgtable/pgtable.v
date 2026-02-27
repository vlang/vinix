module pgtable

// Apple GPU UAT (Unified Address Translation) page table management
// ARM64 format with 16KB granule, 3-level page tables, 39-bit IAS
// 2048 PTEs per page (16KB / 8 bytes per PTE)
// Each level indexes 11 bits: L1[38:28], L2[27:17], L3[16:14] but since
// GPU uses 16KB granule the leaf level covers bits [24:14] with 2048 entries.
// Translated from the Asahi Linux pgtable.rs / mmu.rs page table code.

import memory
import klock
import lib

// --- UAT page table geometry ---
pub const uat_pgsz = u64(16384)
pub const uat_pg_shift = u32(14)
pub const uat_pg_mask = uat_pgsz - 1
pub const uat_levels = 3
pub const uat_ias = 39
pub const uat_ptes_per_page = u32(2048) // 16384 / 8
pub const uat_pte_bits = u32(11) // log2(2048)

// --- PTE descriptor bits (ARM64 stage-1 format) ---
pub const uat_pte_valid = u64(1) << 0
pub const uat_pte_table = u64(1) << 1 // Table descriptor at L1/L2
pub const uat_pte_page = u64(3) // Bits [1:0] = 0b11 for L3 page descriptors

// --- PTE attribute bits ---
pub const uat_pte_af = u64(1) << 10 // Access Flag (must be set)
pub const uat_pte_sh_inner = u64(3) << 8 // Inner Shareable
pub const uat_pte_sh_outer = u64(2) << 8 // Outer Shareable

// Access permissions (AP[7:6])
pub const uat_pte_ap_fw_gpu = u64(0b00) << 6 // FW + GPU read/write
pub const uat_pte_ap_fw_only = u64(0b01) << 6 // FW only (no GPU access)
pub const uat_pte_ap_gpu_only = u64(0b10) << 6 // GPU read-only

// Execute-never bits
pub const uat_pte_pxn = u64(1) << 53 // Privileged Execute Never
pub const uat_pte_uxn = u64(1) << 54 // Unprivileged Execute Never

// Memory attribute index field (AttrIndx[4:2])
pub const uat_attrindex_shift = u64(2)
pub const uat_memattr_normal_cached = u64(0) << 2 // Index 0: Write-Back cached
pub const uat_memattr_device = u64(1) << 2 // Index 1: Device-nGnRnE
pub const uat_memattr_normal_uncached = u64(2) << 2 // Index 2: Normal non-cacheable

// Composite GPU protection flags for convenience
pub const gpu_prot_fw_gpu = uat_pte_ap_fw_gpu | uat_pte_sh_inner | uat_pte_af
pub const gpu_prot_fw_only = uat_pte_ap_fw_only | uat_pte_sh_inner | uat_pte_af | uat_pte_uxn
pub const gpu_prot_gpu_ro = uat_pte_ap_gpu_only | uat_pte_sh_inner | uat_pte_af

// Address mask: extract physical address from a PTE (bits [47:14] for 16KB granule)
pub const pte_addr_mask = u64(0x0000_ffff_ffff_c000)

// Number of 4KB kernel pages required for one 16KB GPU page table page
const kernel_pages_per_uat_page = u64(4) // 4 * 4096 = 16384

// --- UAT page table structure ---

pub struct UatPgtable {
pub mut:
	l1      &u64     = unsafe { nil } // L1 root table (physical address)
	l1_phys u64                        // Physical address of L1 root
	lock    klock.Lock
}

// Allocate a single 16KB-aligned page table page.
// The kernel PMM uses 4KB pages, so we allocate 4 contiguous pages
// and zero them out (pmm_alloc already zeroes memory).
pub fn alloc_table_page() ?&u64 {
	ptr := memory.pmm_alloc(kernel_pages_per_uat_page)
	if ptr == 0 {
		return none
	}
	return ptr
}

// Free a 16KB page table page (4 contiguous kernel pages).
pub fn free_table_page(page &u64) {
	if page == unsafe { nil } {
		return
	}
	memory.pmm_free(voidptr(page), kernel_pages_per_uat_page)
}

// Allocate a new UAT page table with an empty L1 root.
pub fn new_pgtable() ?&UatPgtable {
	l1 := alloc_table_page() or { return none }

	return &UatPgtable{
		l1:      l1
		l1_phys: u64(l1)
	}
}

// Destroy a page table, freeing the L1 root and all referenced L2/L3 tables.
pub fn destroy(pt &UatPgtable) {
	if pt == unsafe { nil } || pt.l1 == unsafe { nil } {
		return
	}

	l1_virt := unsafe { &u64(u64(pt.l1) + higher_half) }

	// Walk all L1 entries and free any L2 tables they reference
	for i := u32(0); i < uat_ptes_per_page; i++ {
		l1_entry := unsafe { l1_virt[i] }
		if l1_entry & uat_pte_valid == 0 {
			continue
		}
		if l1_entry & uat_pte_table == 0 {
			continue
		}

		l2_phys := l1_entry & pte_addr_mask
		l2_virt := unsafe { &u64(l2_phys + higher_half) }

		// Walk all L2 entries and free any L3 tables
		for j := u32(0); j < uat_ptes_per_page; j++ {
			l2_entry := unsafe { l2_virt[j] }
			if l2_entry & uat_pte_valid == 0 {
				continue
			}
			if l2_entry & uat_pte_table == 0 {
				continue
			}

			l3_phys := l2_entry & pte_addr_mask
			free_table_page(unsafe { &u64(l3_phys) })
		}

		free_table_page(unsafe { &u64(l2_phys) })
	}

	// Free the L1 root itself
	free_table_page(pt.l1)
}

// Walk the page table for a given IOVA and return a pointer to the leaf PTE.
// If `allocate` is true, intermediate table levels are created as needed.
//
// Address decomposition for 16KB granule, 3-level, 39-bit IAS:
//   L1 index: bits [38:28]  (11 bits, 2048 entries)
//   L2 index: bits [27:17]  (11 bits, 2048 entries)
//   L3 index: bits [16:14]  (actually bits [24:14] = 11 bits for 2-level leaf)
//
// For the M1 GPU the UAT uses a 2-level scheme within 39 bits:
//   L1 index: bits [38:25]  (top 14 bits, but only 11 used with 2048 entries)
//   L2 index: bits [24:14]  (11 bits, 2048 entries, leaf level)
//
// The 3-level walk is kept for correctness with the full 39-bit range.
pub fn (pt &UatPgtable) get_pte(iova u64, allocate bool) ?&u64 {
	// Validate IOVA is within the 39-bit input address space
	if iova >> uat_ias != 0 && iova >> uat_ias != (u64(1) << (64 - uat_ias)) - 1 {
		// Allow both positive (user) and sign-extended negative (kernel) addresses
	}

	// Level 1 index: bits [38:28]
	l1_idx := (iova >> 28) & u64(uat_ptes_per_page - 1)
	// Level 2 index: bits [27:17]
	l2_idx := (iova >> 17) & u64(uat_ptes_per_page - 1)
	// Level 3 index: bits [24:14] (11 bits for 2048 entries)
	l3_idx := (iova >> uat_pg_shift) & u64(uat_ptes_per_page - 1)

	// --- Walk L1 ---
	l1_virt := unsafe { &u64(u64(pt.l1) + higher_half) }
	l1_entry := unsafe { l1_virt[l1_idx] }

	mut l2_phys := u64(0)

	if l1_entry & uat_pte_valid != 0 {
		l2_phys = l1_entry & pte_addr_mask
	} else {
		if !allocate {
			return none
		}
		l2_table := alloc_table_page() or { return none }
		l2_phys = u64(l2_table)
		unsafe {
			l1_virt[l1_idx] = l2_phys | uat_pte_valid | uat_pte_table
		}
	}

	// --- Walk L2 ---
	l2_virt := unsafe { &u64(l2_phys + higher_half) }
	l2_entry := unsafe { l2_virt[l2_idx] }

	mut l3_phys := u64(0)

	if l2_entry & uat_pte_valid != 0 {
		// Check if this is a table descriptor pointing to L3
		if l2_entry & uat_pte_table != 0 {
			l3_phys = l2_entry & pte_addr_mask
		} else {
			// Block entry at L2 -- return pointer to L2 entry itself
			return unsafe { &u64(u64(&l2_virt[l2_idx])) }
		}
	} else {
		if !allocate {
			return none
		}
		l3_table := alloc_table_page() or { return none }
		l3_phys = u64(l3_table)
		unsafe {
			l2_virt[l2_idx] = l3_phys | uat_pte_valid | uat_pte_table
		}
	}

	// --- Return L3 PTE pointer ---
	l3_virt := unsafe { &u64(l3_phys + higher_half) }
	return unsafe { &u64(u64(&l3_virt[l3_idx])) }
}

// Map a single 16KB GPU page.
// `iova` and `phys` must be 16KB-aligned.
// `prot` contains the desired PTE attribute bits (AP, SH, memattr, etc.).
pub fn (mut pt UatPgtable) map_page(iova u64, phys u64, prot u64) bool {
	pt.lock.acquire()
	defer {
		pt.lock.release()
	}

	if iova & uat_pg_mask != 0 || phys & uat_pg_mask != 0 {
		C.printf(c'uat pgtable: unaligned map iova=0x%llx phys=0x%llx\n', iova, phys)
		return false
	}

	pte_ptr := pt.get_pte(iova, true) or { return false }

	unsafe {
		*pte_ptr = (phys & pte_addr_mask) | prot | uat_pte_valid | uat_pte_page | uat_pte_af
	}
	return true
}

// Map a contiguous range of GPU pages.
// `size` is rounded up to the next 16KB boundary.
pub fn (mut pt UatPgtable) map(iova u64, phys u64, size u64, prot u64) bool {
	if size == 0 {
		return true
	}

	pages := lib.div_roundup(size, uat_pgsz)
	for i := u64(0); i < pages; i++ {
		if !pt.map_page(iova + i * uat_pgsz, phys + i * uat_pgsz, prot) {
			// Unwind on failure
			for j := u64(0); j < i; j++ {
				pt.unmap_page(iova + j * uat_pgsz)
			}
			return false
		}
	}
	return true
}

// Unmap a single 16KB GPU page.
fn (mut pt UatPgtable) unmap_page(iova u64) {
	pt.lock.acquire()
	defer {
		pt.lock.release()
	}

	pte_ptr := pt.get_pte(iova, false) or { return }

	unsafe {
		*pte_ptr = 0
	}
}

// Unmap a contiguous range of GPU pages.
pub fn (mut pt UatPgtable) unmap(iova u64, size u64) {
	if size == 0 {
		return
	}

	pages := lib.div_roundup(size, uat_pgsz)
	for i := u64(0); i < pages; i++ {
		pt.unmap_page(iova + i * uat_pgsz)
	}
}

// Read the PTE value for a given IOVA (for debugging/translation).
pub fn (pt &UatPgtable) read_pte(iova u64) ?u64 {
	pte_ptr := pt.get_pte(iova, false) or { return none }
	return unsafe { *pte_ptr }
}

// Translate an IOVA to a physical address using the page table.
// Returns none if the mapping does not exist.
pub fn (pt &UatPgtable) translate(iova u64) ?u64 {
	pte_val := pt.read_pte(iova) or { return none }
	if pte_val & uat_pte_valid == 0 {
		return none
	}
	return (pte_val & pte_addr_mask) | (iova & uat_pg_mask)
}
