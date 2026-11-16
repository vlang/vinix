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

// --- GPU page size (must match pgtable.uat_pgsz) ---
pub const gpu_page_size = u64(16384)

// --- Pre-defined allocator region boundaries ---
pub const gpu_private_start = u64(0x4000)
pub const gpu_private_end = u64(0x100000000) // 4 GB
pub const gpu_shared_start = u64(0x100000000)
pub const gpu_shared_end = u64(0x200000000) // 8 GB cumulative
pub const gpu_readonly_start = u64(0x200000000)
pub const gpu_readonly_end = u64(0x400000000) // 16 GB cumulative

// G13 firmware addresses are sign-extended 39-bit IOVAs. Keep its allocator
// classes in the exact disjoint ranges expected by the v12.3 firmware ABI.
pub const g13_private_start = u64(0xffffffa000000000)
pub const g13_private_end = u64(0xffffffa600000000)
pub const g13_gpu_readonly_start = u64(0xffffffa600000000)
pub const g13_gpu_readonly_end = u64(0xffffffa800000000)
pub const g13_shared_start = u64(0xffffffa800000000)
pub const g13_shared_end = u64(0xffffffaa00000000)
pub const g13_readonly_start = u64(0xffffffaa00000000)
pub const g13_readonly_end = u64(0xffffffac00000000)
// RTKit system endpoints allocate crash/log/report buffers from this dedicated
// 256 MiB kernel-UAT range. It must not overlap regular firmware structures.
pub const g13_rtkit_start = u64(0xffffffae00000000)
pub const g13_rtkit_end = u64(0xffffffae10000000)
pub const g13_timestamp_start = u64(0xffffffae10000000)
pub const g13_timestamp_end = u64(0xffffffae14000000)

// --- Individual allocation record ---

pub struct Allocation {
pub mut:
	va     u64 // GPU virtual address of the allocation
	size   u64 // Size in bytes (always 16KB-aligned)
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
		name: name
		start: start
		end: end
		top: start
	}
}

// Checked rounding is local to GPU allocation. A wrapped size or address must
// never become a successful reservation in the sign-extended firmware ranges.
fn checked_heap_align_up(value u64, alignment u64) ?u64 {
	if alignment == 0 || (alignment & (alignment - 1)) != 0 { return none }
	mask := alignment - 1
	if value > ~u64(0) - mask { return none }
	return (value + mask) & ~mask
}

fn heap_allocation_address(top u64, end u64, size u64, alignment u64) ?u64 {
	address := checked_heap_align_up(top, alignment) or { return none }
	if address > end || size > end - address { return none }
	return address
}

// Zero alignment selects the page minimum. Nonzero alignments must be powers
// of two, as in Asahi. The size and complete aligned interval must fit.
pub fn (mut h HeapAllocator) alloc(size u64, align u64) ?u64 {
	h.lock.acquire()
	defer {
		h.lock.release()
	}

	if size == 0 || (align != 0 && (align & (align - 1)) != 0) { return none }
	actual_align := if align < gpu_page_size { gpu_page_size } else { align }
	aligned_size := checked_heap_align_up(size, actual_align) or { return none }
	va := heap_allocation_address(h.top, h.end, aligned_size, actual_align) or {
		// A completed suffix can make room, including after address-rounding
		// overflow. Re-run the same checked bounds after GC changes the top.
		h.gc_locked()
		heap_allocation_address(h.top, h.end, aligned_size, actual_align) or {
			available := if h.top < h.end { h.end - h.top } else { u64(0) }
			C.printf(c'gpu alloc %s: out of VA space (need 0x%llx, avail 0x%llx)\n', h.name.str, aligned_size, available)
			return none
		}
	}
	h.top = va + aligned_size

	a := &Allocation{
		va: va
		size: aligned_size
		in_use: true
	} @[freed]
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
// the heap is grow-only -- we cannot move live allocations. Free records
// below a live allocation must remain tracked: once the allocations above
// them are released, they may become part of the reclaimable top suffix.
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
				// The heap lock excludes every metadata reader. Unlink before
				// freeing; interior records remain owned until GC reaches them.
				unsafe { free(a) }
				progress = true
				idx--
				continue
			}
			break
		}
	}
}

// Return the total number of bytes currently in use (allocated and not freed).
pub fn (mut h HeapAllocator) used() u64 {
	h.lock.acquire()
	defer { h.lock.release() }
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
pub fn (mut h HeapAllocator) available() u64 {
	h.lock.acquire()
	defer { h.lock.release() }
	if h.top >= h.end {
		return 0
	}
	return h.end - h.top
}
