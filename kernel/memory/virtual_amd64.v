@[has_globals]
module memory

import katomic
import lib
import limine
import x86.cpu
import x86.msr

pub const pte_flags_mask = ~(u64(0xfff) | pte_present | pte_writable | pte_user | pte_noexec)

const amd64_msr_efer = u32(0xc0000080)
const amd64_efer_nxe = u64(1) << 11
const amd64_cpuid_nx = u32(1) << 20

__global (
	la57 = bool(false)
)

pub fn user_address_limit() u64 {
	return if la57 { u64(1) << 56 } else { u64(1) << 47 }
}

// Vinix installs bit 63 in non-executable PTEs, so NX is a required amd64
// facility rather than an optional optimization. Enable EFER.NXE explicitly
// on every CPU instead of depending on firmware or the bootloader to leave it
// set. OpenBSD likewise programs EFER.NXE before relying on NX page entries.
pub fn enable_nx() {
	supported, _, _, _, edx := cpu.cpuid(0x80000001, 0)
	if !supported || edx & amd64_cpuid_nx == 0 {
		panic('security: amd64 CPU does not support NX')
	}
	mut efer := msr.rdmsr(amd64_msr_efer)
	efer |= amd64_efer_nxe
	msr.wrmsr(amd64_msr_efer, efer)
}

pub fn new_pagemap() &Pagemap {
	mut top_level := &u64(pmm_alloc(1))
	if top_level == 0 {
		panic('new_pagemap() allocation failure')
	}

	// Import higher half from kernel pagemap
	mut p1 := unsafe { &u64(u64(top_level) + higher_half) }
	p2 := unsafe { &u64(u64(kernel_pagemap.top_level) + higher_half) }
	for i := u64(256); i < 512; i++ {
		unsafe {
			p1[i] = p2[i]
		}
	}
	mut pagemap := &Pagemap{
		top_level:   top_level
		track_residency: true
		mmap_ranges: []voidptr{}
	}
	// Nothing keeps a copy of the list, so growing it can give back the
	// storage it outgrew; V keeps that for arrays that might be sliced, and
	// every fork and exec lost three blocks of it. `|=`, not flags.set():
	// V 0.5.2 compiles set() on an array's flags to nothing.
	pagemap.mmap_ranges.flags |= .noslices
	return pagemap
}

pub fn (pagemap &Pagemap) virt2pte(virt u64, allocate bool) ?&u64 {
	pml5_entry := (virt & (u64(0x1ff) << 48)) >> 48
	pml4_entry := (virt & (u64(0x1ff) << 39)) >> 39
	pml3_entry := (virt & (u64(0x1ff) << 30)) >> 30
	pml2_entry := (virt & (u64(0x1ff) << 21)) >> 21
	pml1_entry := (virt & (u64(0x1ff) << 12)) >> 12

	pml5 := pagemap.top_level
	pml4 := if !la57 {
		pagemap.top_level
	} else {
		get_next_level(pml5, pml5_entry, allocate) or { return none }
	}
	pml3 := get_next_level(pml4, pml4_entry, allocate) or { return none }
	pml2 := get_next_level(pml3, pml3_entry, allocate) or { return none }
	pml1 := get_next_level(pml2, pml2_entry, allocate) or { return none }

	return unsafe { &u64(u64(&pml1[pml1_entry]) + higher_half) }
}

pub fn (pagemap &Pagemap) virt2phys(virt u64) ?u64 {
	pte_p := pagemap.virt2pte(virt, false) or { return none }
	if unsafe { *pte_p } & 1 == 0 {
		return none
	}
	return unsafe { *pte_p } & pte_flags_mask
}

// Resolve one userspace page for a checked kernel copy. Callers must hold the
// pagemap lock while using the returned physical address so munmap/mprotect
// cannot invalidate the access between validation and memcpy.
pub fn (pagemap &Pagemap) user_page_phys(virt u64, write bool) ?u64 {
	user_limit := user_address_limit()
	if virt >= user_limit {
		return none
	}
	pte_p := pagemap.virt2pte(virt, false) or { return none }
	pte := unsafe { *pte_p }
	if pte & pte_present == 0 || pte & pte_user == 0 {
		return none
	}
	if write && pte & pte_writable == 0 {
		return none
	}
	mut mutable_map := unsafe { pagemap }
	mutable_map.touch_user_page_unlocked(virt, write)
	return pte & pte_flags_mask
}

pub fn (mut pagemap Pagemap) switch_to() {
	top_level := pagemap.top_level

	asm volatile amd64 {
		mov cr3, top_level
		; ; r (top_level)
		; memory
	}
}

fn get_next_level(current_level &u64, index u64, allocate bool) ?&u64 {
	mut ret := unsafe { &u64(0) }

	mut entry := unsafe { &u64(u64(current_level) + higher_half + index * 8) }

	// Check if entry is present
	if unsafe { *entry } & 0x01 != 0 {
		// If present, return pointer to it
		ret = unsafe { &u64(*entry & pte_flags_mask) }
	} else {
		if allocate == false {
			return none
		}

		// Else, allocate the page table
		ret = pmm_alloc(1)
		if ret == 0 {
			return none
		}
		unsafe {
			*entry = u64(ret) | 0b111
		}
	}
	return ret
}

pub fn (mut pagemap Pagemap) unmap_page(virt u64) ? {
	pagemap.l.acquire()
	defer {
		pagemap.l.release()
	}
	pagemap.unmap_page_unlocked(virt)?
}

pub fn (mut pagemap Pagemap) unmap_page_unlocked(virt u64) ? {
	pml5_entry := (virt & (u64(0x1ff) << 48)) >> 48
	pml4_entry := (virt & (u64(0x1ff) << 39)) >> 39
	pml3_entry := (virt & (u64(0x1ff) << 30)) >> 30
	pml2_entry := (virt & (u64(0x1ff) << 21)) >> 21
	pml1_entry := (virt & (u64(0x1ff) << 12)) >> 12

	mut pml5 := pagemap.top_level
	mut pml5_p := unsafe { &u64(u64(pml5) + higher_half) }
	mut pml4 := if !la57 {
		pagemap.top_level
	} else {
		get_next_level(pml5, pml5_entry, false) or { return none }
	}
	mut pml4_p := unsafe { &u64(u64(pml4) + higher_half) }
	mut pml3 := get_next_level(pml4, pml4_entry, false) or { return none }
	mut pml3_p := unsafe { &u64(u64(pml3) + higher_half) }
	mut pml2 := get_next_level(pml3, pml3_entry, false) or { return none }
	mut pml2_p := unsafe { &u64(u64(pml2) + higher_half) }
	mut pml1 := get_next_level(pml2, pml2_entry, false) or { return none }
	mut pml1_p := unsafe { &u64(u64(pml1) + higher_half) }

	mut pte_p := unsafe { &u64(u64(&pml1[pml1_entry]) + higher_half) }

	unsafe {
		old := *pte_p
		*pte_p = 0
		pagemap.account_resident(virt, old & pte_present != 0, false)
		// The next entry usually remains mapped while a contiguous range is
		// removed in address order. Check it first; sparse tables still get
		// the complete scan, including entries with software-only flags.
		if !table_empty_after_clear(pml1_p, pml1_entry) {
			if old & 1 != 0 {
				pagemap.invalidate(virt)
			}
			return
		}

		// A surviving child makes every ancestor nonempty. Only scan the
		// next level after removing an empty child, and detach all reclaimed
		// tables before the shootdown so no CPU can walk them after it.
		pml2_p[pml2_entry] = 0
		remove_pml2 := table_empty_after_clear(pml2_p, pml2_entry)
		mut remove_pml3 := false
		mut remove_pml4 := false
		if remove_pml2 {
			pml3_p[pml3_entry] = 0
			remove_pml3 = table_empty_after_clear(pml3_p, pml3_entry)
			if remove_pml3 {
				pml4_p[pml4_entry] = 0
				if la57 {
					remove_pml4 = table_empty_after_clear(pml4_p, pml4_entry)
					if remove_pml4 {
						pml5_p[pml5_entry] = 0
					}
				}
			}
		}
		// Before any detached table goes back: a CPU may have cached its
		// parent even when the leaf was absent. Drop those paging-structure
		// entries as well as any translation before returning the pages.
		pagemap.invalidate(virt)
		pmm_free(pml1, 1)
		if remove_pml2 {
			pmm_free(pml2, 1)
		}
		if remove_pml3 {
			pmm_free(pml3, 1)
		}
		if remove_pml4 {
			pmm_free(pml4, 1)
		}
	}
}

// Called with the page-map lock held, after clearing `index`. A single live
// successor proves the table nonempty; when it is absent, inspect every entry
// so a hole or a live entry earlier in the table cannot hide a mapped page.
@[inline]
fn table_empty_after_clear(table &u64, index u64) bool {
	if index < 511 && unsafe { table[index + 1] } != 0 {
		return false
	}
	for i := u64(0); i < 512; i++ {
		if unsafe { table[i] } != 0 {
			return false
		}
	}
	return true
}

// Change the protection of a page that is mapped. One that is not is left
// alone: rewriting its empty entry would map physical page 0 in its place.
pub fn (mut pagemap Pagemap) flag_page(virt u64, flags u64) ? {
	pte_p := pagemap.virt2pte(virt, false) or { return none }
	if unsafe { *pte_p } & 1 == 0 {
		return none
	}

	pagemap.protect_file_page_unlocked(virt)
	old := unsafe { *pte_p }
	unsafe {
		*pte_p &= pte_flags_mask
	}
	unsafe {
		*pte_p |= flags | (old & (page_accessed | page_dirty | pte_file_dirty))
	}
	pagemap.account_resident(virt, old & pte_present != 0,
		flags & pte_present != 0)
	pagemap.invalidate(virt)
}

pub fn (mut pagemap Pagemap) map_page(virt u64, phys u64, flags u64) ? {
	pagemap.l.acquire()
	defer {
		pagemap.l.release()
	}
	pagemap.map_page_unlocked(virt, phys, flags)?
}

pub fn (mut pagemap Pagemap) map_page_unlocked(virt u64, phys u64, flags u64) ? {
	pml5_entry := (virt & (u64(0x1ff) << 48)) >> 48
	pml4_entry := (virt & (u64(0x1ff) << 39)) >> 39
	pml3_entry := (virt & (u64(0x1ff) << 30)) >> 30
	pml2_entry := (virt & (u64(0x1ff) << 21)) >> 21
	pml1_entry := (virt & (u64(0x1ff) << 12)) >> 12

	pml5 := pagemap.top_level
	pml4 := if !la57 {
		pagemap.top_level
	} else {
		get_next_level(pml5, pml5_entry, true) or { return none }
	}
	pml3 := get_next_level(pml4, pml4_entry, true) or { return none }
	pml2 := get_next_level(pml3, pml3_entry, true) or { return none }
	mut pml1 := get_next_level(pml2, pml2_entry, true) or { return none }

	entry := unsafe { &u64(u64(pml1) + higher_half + pml1_entry * 8) }

	old := unsafe { *entry }
	unsafe {
		*entry = phys | flags | (if old & pte_flags_mask == phys && old & pte_file_tracked != 0 { old & (page_dirty | pte_file_dirty) } else { u64(0) })
	}
	pagemap.account_resident(virt, old & pte_present != 0,
		flags & pte_present != 0)
	// Nothing caches an entry that was not present.
	if old & 1 != 0 {
		pagemap.invalidate(virt)
	}
}

@[_linker_section: '.requests']
@[cinit]
__global (
	volatile paging_mode_req = limine.LiminePagingModeRequest{
		response: unsafe { nil }
		revision: 1
		mode: limine.limine_paging_mode_x86_64_5lvl
		max_mode: limine.limine_paging_mode_x86_64_5lvl
		min_mode: limine.limine_paging_mode_x86_64_4lvl
	}
)

pub fn vmm_init() {
	// Enable NXE before the first Vinix-owned page table containing NX entries
	// becomes active. This removes a hidden dependency on Limine's EFER state.
	enable_nx()

	if paging_mode_req.response != unsafe { nil } {
		if paging_mode_req.response.mode == limine.limine_paging_mode_x86_64_5lvl {
			print('vmm: Using 5 level paging\n')
			la57 = true
		}
	}

	kernel_pagemap.top_level = pmm_alloc(1)
	if kernel_pagemap.top_level == 0 {
		panic('vmm_init() allocation failure')
	}

	// Since the higher half has to be shared amongst all address spaces,
	// we need to initialise every single higher half PML3 so they can be
	// shared.
	for i := u64(256); i < 512; i++ {
		// get_next_level will allocate the PML3s for us.
		get_next_level(kernel_pagemap.top_level, i, true) or { panic('vmm init failure') }
	}

	// Map kernel
	if kaddr_req.response == unsafe { nil } {
		panic('Kernel address bootloader response missing')
	}
	C.kprintf(c'vmm: Kernel physical base: 0x%llx\n', u64(kaddr_req.response.physical_base))
	C.kprintf(c'vmm: Kernel virtual base: 0x%llx\n', u64(kaddr_req.response.virtual_base))
	virtual_base := kaddr_req.response.virtual_base
	physical_base := kaddr_req.response.physical_base

	// Map kernel text
	text_virt := u64(voidptr(C.text_start))
	text_phys := (text_virt - virtual_base) + physical_base
	text_len := u64(voidptr(C.text_end)) - text_virt
	map_kernel_span(text_virt, text_phys, text_len, pte_present)

	// Map kernel rodata
	rodata_virt := u64(voidptr(C.rodata_start))
	rodata_phys := (rodata_virt - virtual_base) + physical_base
	rodata_len := u64(voidptr(C.rodata_end)) - rodata_virt
	map_kernel_span(rodata_virt, rodata_phys, rodata_len, pte_present | pte_noexec)

	// Map kernel data
	data_virt := u64(voidptr(C.data_start))
	data_phys := (data_virt - virtual_base) + physical_base
	data_len := u64(voidptr(C.data_end)) - data_virt
	map_kernel_span(data_virt, data_phys, data_len, pte_present | pte_noexec | pte_writable)

	for i := u64(0); i < 0x100000000; i += page_size {
		kernel_pagemap.map_page(i + higher_half, i, pte_present | pte_noexec | pte_writable) or {
			panic('vmm init failure')
		}
	}

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

	protect_kernel_image_alias(text_phys, u64(voidptr(C.rodata_end)) - text_virt)

	kernel_pagemap.switch_to()

	vmm_initialised = true

	$if vmap_selftest ? {
		vmap_selftest()
	}
}

// The last-level table that maps `virt`, as a kernel pointer, or nil and the
// first address past what the missing table above it would have covered -- 0
// when that is past the top of the address space. What lets a walk over a
// large reservation with little in it skip the holes: the program break is
// a 960 GiB reservation, and page by page, every fork of a program that had
// used brk() walked a quarter of a billion page table entries.
fn (pagemap &Pagemap) leaf_table(virt u64) (&u64, u64) {
	mut table := unsafe { &u64(u64(pagemap.top_level) + higher_half) }
	mut shift := if la57 { u64(48) } else { u64(39) }
	for shift > 12 {
		entry := unsafe { table[(virt >> shift) & 0x1ff] }
		if entry & 1 == 0 {
			return unsafe { nil }, (virt | ((u64(1) << shift) - 1)) + 1
		}
		table = unsafe { &u64((entry & pte_flags_mask) + higher_half) }
		shift -= 9
	}
	return table, 0
}

// Where the last-level table `virt` is in ends, or the top of the address
// space.
fn leaf_table_end(virt u64) u64 {
	next := (virt | 0x1fffff) + 1
	return if next > virt { next } else { u64(-1) }
}

// The bytes of [start, end) that are resident, each page counted as its share.
// The caller holds the pagemap lock.
pub fn (pagemap &Pagemap) resident_share(start u64, end u64) u64 {
	mut total := u64(0)
	mut virt := start & ~u64(0xfff)
	for virt < end {
		table, skip := pagemap.leaf_table(virt)
		if table == unsafe { nil } {
			if skip <= virt {
				break
			}
			virt = skip
			continue
		}
		table_end := leaf_table_end(virt)
		stop := if end < table_end { end } else { table_end }
		for virt < stop {
			pte := unsafe { table[(virt >> 12) & 0x1ff] }
			if pte & 1 != 0 {
				refs := pmm_refcount_unlocked(voidptr(pte & pte_flags_mask))
				total += if refs > 1 { page_size / refs } else { page_size }
			}
			virt += page_size
		}
	}
	return total
}

// resident_share() with the shared pages told apart, for /proc/<pid>/smaps.
// The caller holds the pagemap lock.
pub fn (pagemap &Pagemap) residency(start u64, end u64) Residency {
	mut counted := Residency{}
	mut virt := start & ~u64(0xfff)
	for virt < end {
		table, skip := pagemap.leaf_table(virt)
		if table == unsafe { nil } {
			if skip <= virt {
				break
			}
			virt = skip
			continue
		}
		table_end := leaf_table_end(virt)
		stop := if end < table_end { end } else { table_end }
		for virt < stop {
			pte := unsafe { table[(virt >> 12) & 0x1ff] }
			if pte & 1 != 0 {
				refs := pmm_refcount_unlocked(voidptr(pte & pte_flags_mask))
				counted.resident += page_size
				if refs > 1 {
					counted.shared += page_size
					counted.share += page_size / refs
				} else {
					counted.share += page_size
				}
			}
			virt += page_size
		}
	}
	return counted
}

// The first page at or after `start`, and before `end`, that is mapped, or
// `end` when none is. A missing table is skipped with all it would have
// covered, so walking a large reservation with little in it costs what it
// holds rather than its size. The caller holds the pagemap lock.
pub fn (pagemap &Pagemap) next_present(start u64, end u64) u64 {
	mut virt := start & ~u64(0xfff)
	for virt < end {
		table, skip := pagemap.leaf_table(virt)
		if table == unsafe { nil } {
			if skip <= virt {
				return end
			}
			virt = skip
			continue
		}
		table_end := leaf_table_end(virt)
		stop := if end < table_end { end } else { table_end }
		for virt < stop {
			if unsafe { table[(virt >> 12) & 0x1ff] } & 1 != 0 {
				return virt
			}
			virt += page_size
		}
	}
	return end
}

// The flush that follows tearing down a page map no CPU runs any more. Loading
// another CR3 dropped its translations on each of them already: user pages are
// not global, and there are no PCIDs.
pub fn flush_tlb_everywhere() {}

// No retained address-space tags on this architecture yet. Loading another
// CR3 on every former user of the map already dropped its translations.
pub fn (pagemap &Pagemap) prepare_tlb_teardown() {}

pub fn (mut pagemap Pagemap) release_tlb_tag() {}

// ── TLB shootdown ────────────────────────────────────────────────────────────
//
// x86 has no broadcast invalidation, as arm64's TLBI ...IS has: INVLPG drops a
// translation from this CPU's TLB only. Every other CPU running a thread of
// the same process kept the old one -- and went on using a page munmap had
// given back to be someone else's, writing a page fork had just shared with
// the child, and reading the old copy of one a copy-on-write fault had
// replaced. So a change to a present entry is shot down on every CPU that may
// hold it, through an IPI the scheduler sends and waits for.

const max_tlb_cpus = 256

__global (
	// The CR3 each CPU loaded last, as far as a shootdown needs to know: a
	// CPU whose entry is not a page map's has loaded another CR3 since, which
	// dropped that page map's translations.
	tlb_active_cr3 [max_tlb_cpus]u64
	tlb_shootdown  fn (u64, u64, bool)
)

@[inline]
fn full_fence() {
	asm volatile amd64 {
		mfence
		; ; ; memory
	}
}

pub fn register_tlb_shootdown(shootdown fn (u64, u64, bool)) {
	tlb_shootdown = shootdown
}

// Called on CPU `cpu_number` before it loads `cr3`. The fence pairs with the
// one after a page table change: either the shootdown sees this CPU's record,
// or this CPU's page walks see the change.
pub fn note_active_pagemap(cpu_number u64, cr3 u64) {
	if cpu_number < max_tlb_cpus {
		katomic.store(mut &tlb_active_cr3[cpu_number], cr3)
	}
	full_fence()
}

pub fn pagemap_may_be_active_on(cpu_number u64, cr3 u64) bool {
	return cpu_number >= max_tlb_cpus || katomic.load(&tlb_active_cr3[cpu_number]) == cr3
}

// Drop the translation of `virt` from every CPU that may hold one. A page map
// being torn down runs on no CPU. A change to the kernel's own mappings, which
// every page map shares, is dropped everywhere.
fn (pagemap &Pagemap) invalidate(virt u64) {
	if pagemap.dying {
		return
	}
	top_level := u64(pagemap.top_level)
	// A kernel mapping is cached whichever page map a CPU is on.
	everywhere := voidptr(pagemap) == voidptr(&kernel_pagemap)
	if everywhere || cpu.read_cr3() == top_level {
		cpu.invlpg(virt)
	}
	if tlb_shootdown != unsafe { nil } {
		full_fence()
		tlb_shootdown(top_level, virt, everywhere)
	}
}
