// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module memory

import lib
import klock
import katomic

// What big_alloc falls back to when there is no run of free pages as long as
// an allocation. A machine that has been busy for a while has its free memory
// in pieces: after a Firefox session 377 MiB was free, in runs of 40 pages at
// most, and the 146 pages /proc/<pid>/smaps wanted for its text stopped the
// kernel with "Out of memory after reclaim". Here the pages are taken one at a
// time and mapped side by side at kernel addresses nothing else uses.
//
// Each allocation is followed by a slot that is never mapped, so running off
// its end faults rather than writing into the next one.
const vmap_words = 8192
// One page_size slot per bit: 8 GiB of addresses on arm64's 16 KiB pages, 2 GiB
// on amd64's 4 KiB ones.
const vmap_slots = u64(vmap_words) * 64

__global (
	vmap_lock       klock.Lock
	// Slots taken, the guard after each allocation included.
	vmap_used       [8192]u64
	// The first slot of each live allocation, and the guard slot after it.
	// free() goes by these rather than by the allocation's own header, which
	// a stray write could have changed.
	vmap_heads      [8192]u64
	vmap_tails      [8192]u64
	// Guarded stacks have a second reserved, unmapped slot before their head.
	vmap_stack_heads [8192]u64
	// The region's page tables are its own, and change only under this lock
	// rather than kernel_pagemap.l. Nothing reclaims memory while it is held:
	// the page cache's reclaimer frees blocks that may live here, and would
	// come back for the lock on the same CPU.
	vmap_table_lock klock.Lock
)

// Read by ARM vector entry before it can touch an exhausted stack.
@[export: 'vinix_stack_guard_bitmap']
__global vmap_stack_guards [8192]u64

fn vmap_contains(addr u64) bool {
	return addr >= vmap_base && addr < vmap_base + vmap_slots * page_size
}

// The first of `count` free slots in a row, taken, or -1. Called with
// vmap_lock held.
fn vmap_take(count u64) i64 {
	mut run := u64(0)
	mut slot := u64(0)
	for slot < vmap_slots {
		word := vmap_used[slot / 64]
		if slot % 64 == 0 && word == u64(-1) {
			run = 0
			slot += 64
			continue
		}
		if slot % 64 == 0 && word == 0 && run + 64 < count {
			run += 64
			slot += 64
			continue
		}
		if word & (u64(1) << (slot % 64)) != 0 {
			run = 0
		} else {
			run++
			if run == count {
				first := slot + 1 - count
				for i := first; i <= slot; i++ {
					lib.bitset(unsafe { &vmap_used[0] }, i)
				}
				return i64(first)
			}
		}
		slot++
	}
	return -1
}

fn vmap_give_back(first u64, count u64) {
	vmap_lock.acquire()
	for i := first; i < first + count; i++ {
		lib.bitreset(unsafe { &vmap_used[0] }, i)
	}
	vmap_lock.release()
}

fn vmap_release_pages(base u64, count u64) {
	for i := u64(0); i < count; i++ {
		phys := vmap_remove(base + i * page_size)
		if phys != 0 {
			pmm_free(voidptr(phys), 1)
		}
	}
}

// `count` zeroed pages at consecutive kernel addresses, or nil if the
// addresses or the pages run out.
fn vmap_alloc(count u64) voidptr {
	return vmap_alloc_guarded(count, false)
}

fn vmap_alloc_guarded(count u64, stack bool) voidptr {
	guards := if stack { u64(2) } else { u64(1) }
	if !vmm_initialised || count == 0 || count > vmap_slots - guards {
		return unsafe { nil }
	}
	vmap_lock.acquire()
	taken := vmap_take(count + guards)
	vmap_lock.release()
	if taken < 0 {
		return unsafe { nil }
	}
	first := u64(taken) + if stack { u64(1) } else { u64(0) }
	base := vmap_base + first * page_size
	$if kernel_stack_selftest ? { stack_test_failure_base = base }
	for i := u64(0); i < count; i++ {
		mut inject_failure := false
		$if kernel_stack_selftest ? { inject_failure = stack && stack_test_fail_after == int(i) }
		phys := if inject_failure { u64(0) } else { u64(pmm_alloc_fallible(1)) }
		if phys != 0 && vmap_install(base + i * page_size, phys) {
			continue
		}
		if phys != 0 {
			// ARM may have installed only part of this native page. Drop and
			// invalidate every subentry before returning its physical storage.
			vmap_remove(base + i * page_size)
			pmm_free(voidptr(phys), 1)
		}
		vmap_release_pages(base, i)
		vmap_give_back(u64(taken), count + guards)
		return unsafe { nil }
	}
	vmap_lock.acquire()
	lib.bitset(unsafe { &vmap_heads[0] }, first)
	lib.bitset(unsafe { &vmap_tails[0] }, first + count)
	if stack {
		lib.bitset(unsafe { &vmap_stack_heads[0] }, first)
		lib.bitset(unsafe { &vmap_stack_guards[0] }, first - 1)
		lib.bitset(unsafe { &vmap_stack_guards[0] }, first + count)
	}
	vmap_lock.release()
	return voidptr(base)
}

// The independently owned geometry for a live allocation. A caller freeing
// or reallocating its own block uses it to validate writable header metadata.
fn vmap_allocation_pages(base u64) u64 {
	if !vmap_contains(base) || base & (page_size - 1) != 0 {
		return 0
	}
	first := (base - vmap_base) / page_size
	vmap_lock.acquire()
	defer { vmap_lock.release() }
	if !lib.bittest(unsafe { &vmap_heads[0] }, first) {
		return 0
	}
	mut guard := first + 1
	for guard < vmap_slots && !lib.bittest(unsafe { &vmap_tails[0] }, guard) {
		guard++
	}
	return if guard < vmap_slots { guard - first } else { u64(0) }
}

// Give back the allocation that starts at `base`, and say how many pages it
// had: 0 when nothing was allocated there, as for a second free.
fn vmap_free(base u64) u64 {
	if !vmap_contains(base) || base & (page_size - 1) != 0 {
		return 0
	}
	first := (base - vmap_base) / page_size
	vmap_lock.acquire()
	if !lib.bittest(unsafe { &vmap_heads[0] }, first) {
		vmap_lock.release()
		return 0
	}
	lib.bitreset(unsafe { &vmap_heads[0] }, first)
	stack := lib.bittest(unsafe { &vmap_stack_heads[0] }, first)
	if stack {
		lib.bitreset(unsafe { &vmap_stack_heads[0] }, first)
		lib.bitreset(unsafe { &vmap_stack_guards[0] }, first - 1)
	}
	mut guard := first + 1
	for guard < vmap_slots && !lib.bittest(unsafe { &vmap_tails[0] }, guard) {
		guard++
	}
	if guard < vmap_slots {
		lib.bitreset(unsafe { &vmap_tails[0] }, guard)
		if stack { lib.bitreset(unsafe { &vmap_stack_guards[0] }, guard) }
	}
	vmap_lock.release()
	if guard == vmap_slots {
		return 0
	}
	count := guard - first
	vmap_release_pages(base, count)
	vmap_give_back(if stack { first - 1 } else { first }, count + if stack { u64(2) } else { u64(1) })
	return count
}

// The caller owns this dedicated virtual mapping until its CPU has stopped
// using it. Physical direct-map aliases stay mapped; neither guard owns a
// physical page. Existing global invalidation completes before page release.
pub fn kernel_stack_alloc(size u64) voidptr {
	if size == 0 || size % page_size != 0 { return unsafe { nil } }
	return vmap_alloc_guarded(size / page_size, true)
}

pub fn kernel_stack_free(base u64) {
	vmap_free(base)
}

pub fn kernel_stack_guard(addr u64) bool {
	if !vmap_contains(addr) { return false }
	slot := (addr - vmap_base) / page_size
	// Fatal diagnosis must not acquire an allocator lock that the exhausted
	// frame might hold. Aligned word publication is atomic; an active stack's
	// own guard bits remain set until the last CPU leaves that mapping.
	return katomic.load(unsafe { &vmap_stack_guards[slot / 64] }) & (u64(1) << (slot % 64)) != 0
}

// The physical address behind a kernel pointer, whether it is in the direct
// map or in memory big_alloc mapped here. What maps a kernel buffer into a
// process, as a shared mapping of a devtmpfs file does, needs this rather than
// subtracting the direct map's offset.
pub fn kernel_virt2phys(addr u64) u64 {
	if !vmap_contains(addr) {
		return addr - higher_half
	}
	return vmap_translate(addr)
}

// With -d vmap_selftest, once the kernel's page tables are live: the fallback
// hands out zeroed, distinct pages, maps them where it says, and gives every
// one back, a second free included.
fn vmap_selftest() {
	// The region's first page tables stay once made; make them first.
	heap_test_require(vmap_free(u64(vmap_alloc(1))) == 1)
	baseline := free_bytes()
	count := u64(5)
	base := u64(vmap_alloc(count))
	heap_test_require(base != 0 && vmap_contains(base))
	heap_test_require(free_bytes() == baseline - count * page_size)
	for i := u64(0); i < count; i++ {
		page := base + i * page_size
		heap_test_bytes(voidptr(page), page_size, 0)
		unsafe { C.memset(voidptr(page), int(i + 1), page_size) }
		phys := kernel_virt2phys(page)
		heap_test_require(phys != 0 && phys % page_size == 0)
		// The direct map sees what was written through the new mapping.
		heap_test_bytes(voidptr(phys + higher_half), page_size, u8(i + 1))
		for j := u64(0); j < i; j++ {
			heap_test_require(kernel_virt2phys(base + j * page_size) != phys)
		}
	}
	// Not a live allocation: neither a page inside one nor its guard slot.
	heap_test_require(vmap_free(base + page_size) == 0)
	heap_test_require(vmap_free(base + count * page_size) == 0)
	heap_test_require(vmap_free(base) == count)
	heap_test_require(vmap_free(base) == 0)
	heap_test_require(kernel_virt2phys(base) == 0)
	heap_test_require(free_bytes() == baseline)

	// Through malloc, as big_alloc hands it out when no run is long enough.
	size := 3 * page_size + 100
	mapped := vmap_alloc(lib.div_roundup(size, page_size) + 1)
	heap_test_require(mapped != unsafe { nil })
	mut metadata := unsafe { &MallocMetadata(mapped) }
	update_big_metadata(mut metadata, lib.div_roundup(size, page_size), size)
	adjust_big_alloc_pages(i64(metadata.pages + 1))
	ptr := voidptr(u64(mapped) + page_size)
	unsafe { C.memset(ptr, 0x5a, size) }
	grown := realloc(ptr, size + 2 * page_size)
	heap_test_require(grown != unsafe { nil })
	heap_test_bytes(grown, size, 0x5a)
	free(grown)
	heap_test_require(free_bytes() == baseline)
	C.printf_panic(c'vmap: self-test passed\n')
}
