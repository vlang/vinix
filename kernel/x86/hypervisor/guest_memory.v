// SPDX-License-Identifier: GPL-2.0-only
module hypervisor

import memory

// One PD covers 1 GiB with 512 independently allocated 4 KiB leaf tables.
// The leaf entries own the RAM frames too, so no second page-pointer array
// or physically contiguous guest-RAM allocation is needed.
pub const max_guest_memory = u64(1024 * 1024 * 1024)
const ept_entries = u64(512)
const ept_address_mask = u64(0x000ffffffffff000)

struct GuestMemory {
mut:
	pml4  u64
	pdpt  u64
	pd    u64
	pages u64
	ready bool
}

fn guest_memory_size_valid(size u64) bool {
	return size > 0 && size <= max_guest_memory
}

fn guest_memory_alloc_page() ?u64 {
	$if hv_memory_selftest ? {
		if memory_test_fail_after == 0 { return none }
		if memory_test_fail_after > 0 { memory_test_fail_after-- }
	}
	page := memory.pmm_alloc_fallible(1)
	if page == unsafe { nil } { return none }
	address := u64(page)
	if address & ~ept_address_mask != 0 {
		memory.pmm_free(page, 1)
		return none
	}
	return address
}

fn guest_memory_entry(table u64, index u64) u64 {
	unsafe {
		return (&u64(table + memory.get_hhdm_offset()))[index]
	}
}

fn guest_memory_set_entry(table u64, index u64, value u64) {
	unsafe {
		mut entries := &u64(table + memory.get_hhdm_offset())
		entries[index] = value
	}
}

fn (mut ram GuestMemory) initialise(size u64) bool {
	if ram.pml4 != 0 || !guest_memory_size_valid(size) { return false }
	ram.pages = (size + page_size - 1) / page_size
	ram.pml4 = guest_memory_alloc_page() or {
		ram.release()
		return false
	}
	ram.pdpt = guest_memory_alloc_page() or {
		ram.release()
		return false
	}
	ram.pd = guest_memory_alloc_page() or {
		ram.release()
		return false
	}
	guest_memory_set_entry(ram.pml4, 0, ram.pdpt | 7)
	guest_memory_set_entry(ram.pdpt, 0, ram.pd | 7)
	for page := u64(0); page < ram.pages; page++ {
		table_index := page / ept_entries
		if page % ept_entries == 0 {
			table := guest_memory_alloc_page() or {
				ram.release()
				return false
			}
			guest_memory_set_entry(ram.pd, table_index, table | 7)
		}
		table := guest_memory_entry(ram.pd, table_index) & ept_address_mask
		frame := guest_memory_alloc_page() or {
			ram.release()
			return false
		}
		// RWX and write-back memory, without accessed/dirty tracking.
		guest_memory_set_entry(table, page % ept_entries, frame | 0x37)
	}
	ram.ready = true
	return true
}

// Used for both partial allocation rollback and final destruction. Every
// successfully allocated page is published into this private ownership tree
// before another allocation can fail. Clear children before their parent.
fn (mut ram GuestMemory) release() {
	ram.ready = false
	if ram.pd != 0 {
		for table_index := u64(0); table_index < ept_entries; table_index++ {
			table := guest_memory_entry(ram.pd, table_index) & ept_address_mask
			if table == 0 { continue }
			for page := u64(0); page < ept_entries; page++ {
				frame := guest_memory_entry(table, page) & ept_address_mask
				if frame == 0 { continue }
				guest_memory_set_entry(table, page, 0)
				memory.pmm_free(voidptr(frame), 1)
			}
			guest_memory_set_entry(ram.pd, table_index, 0)
			memory.pmm_free(voidptr(table), 1)
		}
		memory.pmm_free(voidptr(ram.pd), 1)
	}
	if ram.pdpt != 0 { memory.pmm_free(voidptr(ram.pdpt), 1) }
	if ram.pml4 != 0 { memory.pmm_free(voidptr(ram.pml4), 1) }
	ram.pml4 = 0
	ram.pdpt = 0
	ram.pd = 0
	ram.pages = 0
}

fn (ram &GuestMemory) size() u64 { return ram.pages * page_size }

fn (ram &GuestMemory) page(index u64) voidptr {
	if !ram.ready || index >= ram.pages { return unsafe { nil } }
	table := guest_memory_entry(ram.pd, index / ept_entries) & ept_address_mask
	if table == 0 { return unsafe { nil } }
	return voidptr(guest_memory_entry(table, index % ept_entries) & ept_address_mask)
}

// File I/O is not necessarily page aligned, and adjacent GPAs need not have
// adjacent host frames. Never memcpy a multi-page span from one frame.
fn (ram &GuestMemory) copy(address u64, buffer voidptr, length u64, into_guest bool) bool {
	if !ram.ready || address > ram.size() || length > ram.size() - address
		|| length != 0 && buffer == unsafe { nil } {
		return false
	}
	mut done := u64(0)
	for done < length {
		guest_address := address + done
		frame := ram.page(guest_address / page_size)
		if frame == unsafe { nil } { return false }
		offset := guest_address & (page_size - 1)
		remaining := length - done
		count := if remaining < page_size - offset { remaining } else { page_size - offset }
		mapped := voidptr(u64(frame) + memory.get_hhdm_offset() + offset)
		local := voidptr(u64(buffer) + done)
		unsafe {
			if into_guest {
				C.memcpy(mapped, local, count)
			} else {
				C.memcpy(local, mapped, count)
			}
		}
		done += count
	}
	return true
}
