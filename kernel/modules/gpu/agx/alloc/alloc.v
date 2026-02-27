module alloc

// GPU memory allocators for the Apple AGX driver.
// HeapAllocator: a simple grow-only virtual address heap with garbage
// collection of freed allocations at the top.
//
// Three pre-defined VA regions partition the 39-bit GPU address space:
//   Private  : 0x4000          .. 0x1_0000_0000  (  ~4 GB, GPU-private)
//   Shared   : 0x1_0000_0000   .. 0x2_0000_0000  (   4 GB, CPU+GPU shared)
//   ReadOnly : 0x2_0000_0000   .. 0x4_0000_0000  (   8 GB, GPU read-only)
//
// Translated from the Asahi Linux alloc.rs allocator code.

import klock
import lib

// --- GPU page size (must match pgtable.uat_pgsz) ---
pub const gpu_page_size = u64(16384)

// --- Pre-defined allocator region boundaries ---
pub const gpu_private_start = u64(0x4000)
pub const gpu_private_end = u64(0x100000000) // 4 GB
pub const gpu_shared_start = u64(0x100000000)
pub const gpu_shared_end = u64(0x200000000) // 8 GB cumulative
pub const gpu_readonly_start = u64(0x200000000)
pub const gpu_readonly_end = u64(0x400000000) // 16 GB cumulative

// --- Individual allocation record ---

pub struct Allocation {
pub mut:
	va     u64  // GPU virtual address of the allocation
	size   u64  // Size in bytes (always 16KB-aligned)
	in_use bool // false once freed; eligible for GC
}

// --- Grow-only heap allocator ---
// Allocations are served from `top`, which only moves upward.
// `free()` marks an allocation as unused.  `gc()` can reclaim
// contiguous free allocations at the top of the heap.

pub struct HeapAllocator {
pub mut:
	name        string
	start       u64 // Start of managed VA range (inclusive)
	end         u64 // End of managed VA range (exclusive)
	top         u64 // Current allocation frontier (grows upward)
	allocations []&Allocation
	lock        klock.Lock
}

// Create a new heap allocator managing the VA range [start, end).
pub fn new_heap(name string, start u64, end u64) HeapAllocator {
	return HeapAllocator{
		name:  name
		start: start
		end:   end
		top:   start
	}
}

// Allocate `size` bytes aligned to `align` from the heap.
// Returns the GPU virtual address of the allocation, or none on failure.
// Both `size` and the returned address are rounded/aligned to `align`
// (which itself must be a power of two and >= gpu_page_size).
pub fn (mut h HeapAllocator) alloc(size u64, align u64) ?u64 {
	h.lock.acquire()
	defer {
		h.lock.release()
	}

	// Ensure minimum page-size alignment
	actual_align := if align < gpu_page_size { gpu_page_size } else { align }
	aligned_size := lib.align_up(size, actual_align)

	if aligned_size == 0 {
		return none
	}

	// Align the current top pointer upward
	aligned_top := lib.align_up(h.top, actual_align)

	// Check if there is enough room
	if aligned_top + aligned_size > h.end {
		// Try garbage-collecting first, then re-check
		h.gc_locked()
		aligned_top2 := lib.align_up(h.top, actual_align)
		if aligned_top2 + aligned_size > h.end {
			C.printf(c'gpu alloc %s: out of VA space (need 0x%llx, avail 0x%llx)\n',
				h.name.str, aligned_size, h.end - aligned_top2)
			return none
		}
		// Use the post-GC pointer
		va := aligned_top2
		h.top = va + aligned_size

		a := &Allocation{
			va:     va
			size:   aligned_size
			in_use: true
		}
		h.allocations << a
		return va
	}

	va := aligned_top
	h.top = va + aligned_size

	a := &Allocation{
		va:     va
		size:   aligned_size
		in_use: true
	}
	h.allocations << a

	return va
}

// Mark the allocation at `va` as free. The VA region is not immediately
// reused; call `gc()` to compact free space at the top.
pub fn (mut h HeapAllocator) release(va u64) {
	h.lock.acquire()
	defer {
		h.lock.release()
	}

	for mut a in h.allocations {
		if a.va == va && a.in_use {
			unsafe {
				a.in_use = false
			}
			return
		}
	}
}

// Compact free allocations at the top of the heap.
// Only contiguous free entries ending at `top` can be reclaimed because
// the heap is grow-only -- we cannot move live allocations.
pub fn (mut h HeapAllocator) gc() {
	h.lock.acquire()
	defer {
		h.lock.release()
	}

	h.gc_locked()
}

// Internal GC implementation (caller must hold the lock).
fn (mut h HeapAllocator) gc_locked() {
	// Repeatedly trim the topmost allocation if it is free
	mut progress := true
	for progress {
		progress = false
		if h.allocations.len == 0 {
			break
		}

		mut idx := h.allocations.len - 1
		for idx >= 0 {
			a := h.allocations[idx]
			// Check if this allocation sits at the top
			if a.va + a.size == h.top && !a.in_use {
				h.top = a.va
				h.allocations.delete(idx)
				progress = true
				idx--
				continue
			}
			break
		}
	}

	// Remove any remaining non-in_use entries from the list that
	// are not at the top (cannot reclaim VA but can free bookkeeping).
	mut new_allocs := []&Allocation{}
	for a in h.allocations {
		if a.in_use {
			new_allocs << a
		}
	}
	unsafe { h.allocations.free() }
	h.allocations = new_allocs
}

// Return the total number of bytes currently in use (allocated and not freed).
pub fn (h &HeapAllocator) used() u64 {
	mut total := u64(0)
	for a in h.allocations {
		if a.in_use {
			total += a.size
		}
	}
	return total
}

// Return the number of bytes remaining between the allocation frontier
// and the end of the managed region.
pub fn (h &HeapAllocator) available() u64 {
	if h.top >= h.end {
		return 0
	}
	return h.end - h.top
}
