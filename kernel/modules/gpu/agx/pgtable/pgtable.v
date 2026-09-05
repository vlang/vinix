module pgtable

// Apple GPU UAT (Unified Address Translation) page table management
// ARM64 format with a 16 KiB granule and three page-table levels.
// 2048 PTEs per page (16KB / 8 bytes per PTE)
// The table shifts are 36, 25, and 14. G13/G14 use a 39-bit input address
// space (8 populated root entries), while G15+ uses 42 bits (64 entries).
// Translated from the Asahi Linux pgtable.rs / mmu.rs page table code.

import memory
import klock
import lib

// --- UAT page table geometry ---
pub const uat_pgsz = u64(16384)
pub const uat_pg_shift = u32(14)
pub const uat_pg_mask = uat_pgsz - 1
pub const uat_levels = 3
pub const uat_ptes_per_page = u32(2048) // 16384 / 8
pub const uat_pte_bits = u32(11) // log2(2048)
const uat_root_shift = u32(36)
const uat_middle_shift = u32(25)

// --- PTE descriptor bits (ARM64 stage-1 format) ---
pub const uat_pte_valid = u64(1) << 0
pub const uat_pte_table = u64(1) << 1 // Table descriptor at L1/L2
pub const uat_pte_page = u64(3) // Bits [1:0] = 0b11 for L3 page descriptors

// --- PTE attribute bits ---
pub const uat_pte_af = u64(1) << 10 // Access Flag (must be set)
pub const uat_pte_ng = u64(1) << 11 // ASID-local instead of global
pub const uat_pte_sh_inner = u64(3) << 8 // Inner Shareable
pub const uat_pte_sh_outer = u64(2) << 8 // Outer Shareable

// Access permissions (AP[7:6])
pub const uat_pte_ap_fw_gpu = u64(0b00) << 6 // FW + GPU read/write
pub const uat_pte_ap_fw_only = u64(0b01) << 6 // FW only (no GPU access)
pub const uat_pte_ap_gpu_only = u64(0b10) << 6 // GPU read-only

// Execute-never bits
pub const uat_pte_pxn = u64(1) << 53 // Privileged Execute Never
pub const uat_pte_uxn = u64(1) << 54 // Unprivileged Execute Never
pub const uat_pte_os = u64(1) << 55 // Mapping is owned by the host OS

// Memory attribute index field (AttrIndx[4:2])
pub const uat_attrindex_shift = u64(2)
pub const uat_memattr_normal_cached = u64(0) << 2 // Index 0: Write-Back cached
pub const uat_memattr_device = u64(1) << 2 // Index 1: Device-nGnRnE
pub const uat_memattr_normal_uncached = u64(2) << 2 // Index 2: Normal non-cacheable

// Composite mappings used by the AGX driver. These match Asahi's UAT
// protection encoding rather than the CPU's superficially similar AP bits.
pub const gpu_prot_fw_gpu_cached_rw = uat_pte_os | uat_pte_pxn | uat_pte_uxn |
	uat_pte_ap_fw_gpu | uat_memattr_normal_cached | uat_pte_af
pub const gpu_prot_fw_gpu_shared_rw = uat_pte_os | uat_pte_pxn | uat_pte_uxn |
	uat_pte_ap_fw_gpu | uat_memattr_normal_uncached | uat_pte_af
pub const gpu_prot_fw_shared_rw = uat_pte_os | uat_pte_pxn | uat_pte_uxn |
	uat_pte_ap_fw_only | uat_memattr_normal_uncached | uat_pte_af
pub const gpu_prot_fw_shared_ro = uat_pte_os | uat_pte_pxn | uat_pte_ap_fw_only |
	uat_memattr_normal_uncached | uat_pte_af
pub const gpu_prot_fw_private_rw = uat_pte_os | uat_pte_uxn | uat_pte_ap_fw_only |
	uat_memattr_normal_cached | uat_pte_af
// Firmware-only device mappings. The UAT permission encoding uses UXN as
// the firmware write-enable bit for AP=firmware; this intentionally mirrors
// Asahi's PROT_FW_MMIO_{RW,RO} encodings rather than CPU stage-1 semantics.
pub const gpu_prot_fw_mmio_rw = uat_pte_os | uat_pte_uxn | uat_pte_ap_fw_only |
	uat_memattr_device | uat_pte_af
pub const gpu_prot_fw_mmio_ro = uat_pte_os | uat_pte_ap_fw_only | uat_memattr_device |
	uat_pte_af
pub const gpu_prot_gpu_shared_rw = uat_pte_os | uat_pte_uxn | uat_pte_ap_gpu_only |
	uat_memattr_normal_uncached | uat_pte_af
pub const gpu_prot_gpu_shared_ro = uat_pte_os | uat_pte_ap_gpu_only |
	uat_memattr_normal_uncached | uat_pte_af

// Number of 4KB kernel pages required for one 16KB GPU page table page
const kernel_pages_per_uat_page = u64(4) // 4 * 4096 = 16384

// --- UAT page table structure ---

pub struct UatPgtable {
pub mut:
	l1         &u64     = unsafe { nil } // Root table physical address
	l1_phys    u64
	ias        u32
	oas_mask   u64
	non_global bool
	owns_root  bool
	lock       klock.Lock
}

// Allocate a single 16KB-aligned page table page.
// The kernel PMM uses 4KB pages, so we allocate 4 contiguous pages
// and zero them out (pmm_alloc already zeroes memory).
pub fn alloc_table_page() ?&u64 {
	ptr := memory.pmm_alloc_aligned(kernel_pages_per_uat_page, kernel_pages_per_uat_page)
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
pub fn new_pgtable(ias u32, oas u32) ?&UatPgtable {
	if ias < 37 || ias > 42 || oas < uat_pg_shift || oas > 48 {
		return none
	}
	l1 := alloc_table_page() or { return none }

	return &UatPgtable{
		l1:         l1
		l1_phys:    u64(l1)
		ias:        ias
		oas_mask:   (u64(1) << oas) - 1
		non_global: true
		owns_root:  true
	}
}

// Attach to the firmware/bootloader-reserved TTBR1 root. Existing entries
// are deliberately preserved because they contain firmware-owned mappings.
pub fn new_pgtable_with_root(root_phys u64, ias u32, oas u32) ?&UatPgtable {
	if root_phys & uat_pg_mask != 0 || ias < 37 || ias > 42 || oas < uat_pg_shift
		|| oas > 48 {
		return none
	}
	return &UatPgtable{
		l1:         unsafe { &u64(root_phys) }
		l1_phys:    root_phys
		ias:        ias
		oas_mask:   (u64(1) << oas) - 1
		non_global: false
		owns_root:  false
	}
}

// Destroy a page table, freeing the L1 root and all referenced L2/L3 tables.
pub fn destroy(pt &UatPgtable) {
	if pt == unsafe { nil } || pt.l1 == unsafe { nil } {
		return
	}
	if !pt.owns_root {
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

		l2_phys := l1_entry & pt.oas_mask & ~uat_pg_mask
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

			l3_phys := l2_entry & pt.oas_mask & ~uat_pg_mask
			free_table_page(unsafe { &u64(l3_phys) })
		}

		free_table_page(unsafe { &u64(l2_phys) })
	}

	free_table_page(pt.l1)
}

// Walk the page table for a given IOVA and return a pointer to the leaf PTE.
// If `allocate` is true, intermediate table levels are created as needed.
//
// Address decomposition for the three 16 KiB UAT levels:
//   root:   bits [IAS-1:36] (8 entries at 39-bit IAS, 64 at 42-bit IAS)
//   middle: bits [35:25]
//   leaf:   bits [24:14]
pub fn (pt &UatPgtable) get_pte(iova u64, allocate bool) ?&u64 {
	// Accept lower addresses and correctly sign-extended TTBR1 addresses only.
	upper := iova >> pt.ias
	upper_mask := (u64(1) << (64 - pt.ias)) - 1
	if upper != 0 && upper != upper_mask {
		return none
	}
	masked := iova & ((u64(1) << pt.ias) - 1)

	l1_idx := (masked >> uat_root_shift) & u64(uat_ptes_per_page - 1)
	l2_idx := (masked >> uat_middle_shift) & u64(uat_ptes_per_page - 1)
	l3_idx := (masked >> uat_pg_shift) & u64(uat_ptes_per_page - 1)

	// --- Walk L1 ---
	l1_virt := unsafe { &u64(u64(pt.l1) + higher_half) }
	l1_entry := unsafe { l1_virt[l1_idx] }

	mut l2_phys := u64(0)

	if l1_entry & uat_pte_valid != 0 {
		l2_phys = l1_entry & pt.oas_mask & ~uat_pg_mask
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
			l3_phys = l2_entry & pt.oas_mask & ~uat_pg_mask
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
		mut descriptor := (phys & pt.oas_mask & ~uat_pg_mask) | prot | uat_pte_page | uat_pte_af
		if pt.non_global {
			descriptor |= uat_pte_ng
		}
		*pte_ptr = descriptor
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
	return (pte_val & pt.oas_mask & ~uat_pg_mask) | (iova & uat_pg_mask)
}
