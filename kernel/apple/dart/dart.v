@[has_globals]
module dart

// Apple DART (Device Address Resolution Table) -- IOMMU
// Maps IOVA (I/O Virtual Address) to physical addresses for DMA
// Used by GPU, DCP, and other Apple coprocessors

import aarch64.kio
import aarch64.cpu
import memory
import klock
import lib

// DART register offsets
const dart_params1 = u32(0x0000)
const dart_params2 = u32(0x0004)
const dart_tbl_config = u32(0x0100) // per-stream table config base
const dart_err_status = u32(0x0040)
const dart_err_addrl = u32(0x0050)
const dart_err_addrh = u32(0x0054)
const dart_tcr = u32(0x0100) // Translation Control Register (per-stream, stride 4)
const dart_ttbr_base = u32(0x0200) // Translation Table Base (per-stream, 4 TTBRs each)
const dart_stream_select = u32(0x0034) // Stream mask for TLB flush (SIDMASK)
const dart_cmd = u32(0x0020) // TLB command register (busy bit polled here)
const dart_config = u32(0x0060)
const dart_config_lock = u32(1 << 15)
const dart_enabled_streams = u32(0x00fc)

// TTBR encoding (T8020-style DART, matches Linux apple-dart.c):
//   value = (phys >> 12) | VALID(bit 31); four TTBRs per stream, 4 bytes apart.
const dart_ttbr_valid = u32(1) << 31
const dart_ttbr_shift = u32(12)
const dart_ttbrs_per_stream = u32(4)

// DART commands
const dart_cmd_tlb_invalidate = u32(1 << 20)
const dart_cmd_busy_bit = u32(1 << 2)

// DART TCR bits
const dart_tcr_translate_enable = u32(1 << 7)
const dart_tcr_bypass = u32(1 << 8)

// T8020 DART page-table format. Unlike an ARM translation table, an L1 entry
// is an address plus VALID only. Leaf entries also disable sub-page protection
// and permit all 4 KiB sub-pages inside the 16 KiB DART page.
const dart_pte_valid = u64(1 << 0)
const dart_pte_disable_sp = u64(1 << 1)
const dart_pte_sp_end_all = u64(0xfff) << 40
const dart_leaf_flags = dart_pte_sp_end_all | dart_pte_disable_sp | dart_pte_valid

// Apple DART uses 16KB pages for t8103
const dart_page_shift = u32(14) // 16KB = 1 << 14
const dart_page_size = u64(1) << dart_page_shift
const dart_page_mask = dart_page_size - 1
const dart_pte_address_mask = ((u64(1) << 40) - 1) & ~dart_page_mask

// Each t8103 TTBR covers 36 IOVA bits with a 2-level, 16 KiB-page scheme:
//   L1 index: bits [35:25] (11 bits)
//   L2 index: bits [24:14] (11 bits, leaf)
// This implementation owns/adopts TTBR0, which covers all t8103 DCP and
// PIODMA ranges advertised by m1n1.
const dart_l1_bits = u32(11)
const dart_l1_entries = u32(1) << dart_l1_bits
const dart_l2_bits = u32(11)
const dart_l2_entries = u32(1) << dart_l2_bits
const dart_l1_pages = u64((dart_l1_entries * 8 + 4095) / 4096) // 16 KiB
const dart_l2_pages = u64(4) // 16 KiB

pub struct DART {
pub mut:
	base      u64
	lock      klock.Lock
	stream_id u8
	l1_table  &u64 = unsafe { nil }
}

// Allocate `pages` contiguous 4 KiB pages whose base is 16 KiB aligned, as the
// DART table/descriptor format requires (the L1->L2 pointer masks the low 14
// bits, so a merely 4 KiB-aligned table would be truncated).
fn alloc_16k_aligned(pages u64) &u64 {
	raw := memory.pmm_alloc_aligned_fallible(pages, dart_page_size / 4096)
	if raw == unsafe { nil } {
		return unsafe { nil }
	}
	return unsafe { &u64(raw) }
}

pub fn new_dart(base u64, stream_id u8) DART {
	mut d := DART{
		// Map the DART register aperture as Device memory.
		base: memory.map_mmio(base, 0x4000)
		stream_id: stream_id
	}

	// Allocate the TTBR0 root table (16 KiB aligned).
	d.l1_table = alloc_16k_aligned(dart_l1_pages)
	if d.l1_table == unsafe { nil } {
		panic('dart: Failed to allocate L1 page table')
	}
	unsafe {
		C.memset(voidptr(u64(d.l1_table) + higher_half), 0, dart_l1_pages * 4096)
	}

	println('dart: DART at 0x${base:x}, stream ${stream_id}')

	return d
}

fn (d &DART) read_reg(offset u32) u32 {
	return kio.mmin32(unsafe { &u32(d.base + offset) })
}

fn (d &DART) write_reg(offset u32, value u32) {
	kio.mmout32(unsafe { &u32(d.base + offset) }, value)
}

// Initialize the DART for a given stream
pub fn (mut d DART) init() {
	// T8020 DARTs have a global stream-enable bitmap in addition to each
	// stream's TCR. Firmware normally leaves this set, but a cold boot need not.
	d.write_reg(dart_enabled_streams, d.read_reg(dart_enabled_streams) | (u32(1) << d.stream_id))

	// Program TTBR0 for our stream. Each stream owns four TTBRs (4 bytes
	// apart); we only use the first. The address field is (phys >> 12) and
	// bit 31 is the VALID flag.
	ttbr_offset := dart_ttbr_base + u32(d.stream_id) * dart_ttbrs_per_stream * 4
	phys := u64(d.l1_table)

	d.write_reg(ttbr_offset, u32(phys >> dart_ttbr_shift) | dart_ttbr_valid)

	// Enable translation for this stream (TCR stride is 4 bytes).
	tcr_offset := dart_tcr + u32(d.stream_id) * 4
	d.write_reg(tcr_offset, dart_tcr_translate_enable)

	// Invalidate TLB
	d.flush_tlb()
}

// Adopt TTBR0 when m1n1 has locked a display DART to protect its inherited
// framebuffer mapping. A locked DART ignores replacement TTBR/TCR writes; the
// active table must instead be extended in place. On an unlocked DART this is
// equivalent to init().
pub fn (mut d DART) init_preserving() bool {
	if d.read_reg(dart_config) & dart_config_lock == 0 {
		d.init()
		return true
	}
	tcr := d.read_reg(dart_tcr + u32(d.stream_id) * 4)
	if tcr & dart_tcr_translate_enable == 0 || tcr & dart_tcr_bypass != 0 {
		C.printf(c'dart: locked stream %u is not translating\n', d.stream_id)
		return false
	}
	ttbr_offset := dart_ttbr_base + u32(d.stream_id) * dart_ttbrs_per_stream * 4
	ttbr := d.read_reg(ttbr_offset)
	if ttbr & dart_ttbr_valid == 0 {
		C.printf(c'dart: locked stream %u has no TTBR0\n', d.stream_id)
		return false
	}
	root_phys := u64(ttbr & ~dart_ttbr_valid) << dart_ttbr_shift
	if root_phys == 0 || root_phys & dart_page_mask != 0 {
		return false
	}
	// Ensure the reserved bootloader table has a Normal-memory CPU mapping.
	memory.map_uncached(root_phys, dart_page_size)
	d.l1_table = unsafe { &u64(root_phys) }
	d.flush_tlb()
	C.printf(c'dart: adopted locked stream %u TTBR0 at 0x%llx\n', d.stream_id, root_phys)
	return true
}

// Map an IOVA range to physical addresses
pub fn (mut d DART) map(iova u64, phys u64, size u64) bool {
	d.lock.acquire()
	defer {
		d.lock.release()
	}

	if size == 0 || iova & dart_page_mask != 0 || phys & dart_page_mask != 0
		|| iova >= (u64(1) << 36) || size > (u64(1) << 36) - iova
		|| phys >= (u64(1) << 40) || size > (u64(1) << 40) - phys {
		C.printf(c'dart: invalid map: iova=0x%llx phys=0x%llx size=0x%llx\n', iova, phys, size)
		return false
	}

	pages := lib.div_roundup(size, dart_page_size)

	for i := u64(0); i < pages; i++ {
		va := iova + i * dart_page_size
		pa := phys + i * dart_page_size

		if !d.map_page(va, pa) {
			return false
		}
	}

	d.flush_tlb()
	return true
}

fn (mut d DART) map_page(iova u64, phys u64) bool {
	l1_idx := (iova >> 25) & u64(dart_l1_entries - 1)
	l2_idx := (iova >> dart_page_shift) & u64(dart_l2_entries - 1)

	// Get L2 table
	l1_p := unsafe { &u64(u64(d.l1_table) + higher_half) }
	mut l2_table := &u64(unsafe { nil })

	l1_entry := unsafe { l1_p[l1_idx] }
	if l1_entry & dart_pte_valid != 0 {
		l2_phys := l1_entry & dart_pte_address_mask
		memory.map_uncached(l2_phys, dart_page_size)
		l2_table = unsafe { &u64(l2_phys) }
	} else {
		// Allocate L2 table (16KB leaf table, 16 KiB aligned)
		l2_table = alloc_16k_aligned(dart_l2_pages)
		if l2_table == unsafe { nil } {
			return false
		}
		unsafe {
			C.memset(voidptr(u64(l2_table) + higher_half), 0, dart_l2_pages * 4096)
		}
		unsafe {
			l1_p[l1_idx] = (u64(l2_table) & dart_pte_address_mask) | dart_pte_valid
		}
	}

	// Set L2 (leaf) entry
	l2_p := unsafe { &u64(u64(l2_table) + higher_half) }
	unsafe {
		l2_p[l2_idx] = (phys & dart_pte_address_mask) | dart_leaf_flags
	}

	return true
}

// Unmap an IOVA range
pub fn (mut d DART) unmap(iova u64, size u64) {
	d.lock.acquire()
	defer {
		d.lock.release()
	}

	pages := lib.div_roundup(size, dart_page_size)

	for i := u64(0); i < pages; i++ {
		va := iova + i * dart_page_size
		d.unmap_page(va)
	}

	d.flush_tlb()
}

fn (mut d DART) unmap_page(iova u64) {
	l1_idx := (iova >> 25) & u64(dart_l1_entries - 1)
	l2_idx := (iova >> dart_page_shift) & u64(dart_l2_entries - 1)

	l1_p := unsafe { &u64(u64(d.l1_table) + higher_half) }
	l1_entry := unsafe { l1_p[l1_idx] }
	if l1_entry & dart_pte_valid == 0 {
		return
	}

	l2_phys := l1_entry & dart_pte_address_mask
	memory.map_uncached(l2_phys, dart_page_size)
	l2_p := unsafe { &u64(l2_phys + higher_half) }
	unsafe {
		l2_p[l2_idx] = 0
	}
}

// Flush DART TLB
pub fn (mut d DART) flush_tlb() {
	// Select the stream(s) to invalidate BEFORE issuing the command, then poll
	// the busy bit in the command register itself (0x20), not a separate reg.
	d.write_reg(dart_stream_select, u32(1) << d.stream_id)
	// T8020 page-table walks are coherent, but the command must not pass the
	// stores that populated the tables.
	cpu.dmb_sy()
	d.write_reg(dart_cmd, dart_cmd_tlb_invalidate)

	// Wait for invalidation to complete
	for i := 0; i < 100000; i++ {
		if d.read_reg(dart_cmd) & dart_cmd_busy_bit == 0 {
			return
		}
		cpu.isb()
	}
	C.printf(c'dart: TLB invalidate timeout\n')
}

// Translate an IOVA to physical address (for debugging)
pub fn (d &DART) translate(iova u64) ?u64 {
	l1_idx := (iova >> 25) & u64(dart_l1_entries - 1)
	l2_idx := (iova >> dart_page_shift) & u64(dart_l2_entries - 1)

	l1_p := unsafe { &u64(u64(d.l1_table) + higher_half) }
	l1_entry := unsafe { l1_p[l1_idx] }
	if l1_entry & dart_pte_valid == 0 {
		return none
	}

	l2_phys := l1_entry & dart_pte_address_mask
	memory.map_uncached(l2_phys, dart_page_size)
	l2_p := unsafe { &u64(l2_phys + higher_half) }
	l2_entry := unsafe { l2_p[l2_idx] }
	if l2_entry & dart_pte_valid == 0 {
		return none
	}

	return (l2_entry & dart_pte_address_mask) | (iova & dart_page_mask)
}
