module alloc

// GPU memory allocators for the Apple AGX driver.
// HeapAllocator: a best-fit virtual address heap with deferred collection
// of released allocation records.
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
	hole_order u64 // Recency rank of the following hole; zero if none
	release_order u64 // Deferred FIFO rank; zero while live
}

// --- GPU virtual-address heap allocator ---
// Allocation records stay in VA order. Best-fit placement can reuse gaps;
// `top` tracks the highest reservation end, including deferred releases.
// `release()` marks an allocation as unused. GC destroys every released record
// and reclaims the address suffix above the highest remaining live allocation.

pub struct HeapAllocator {
pub mut:
	name        string
	start       u64 // Start of managed VA range (inclusive)
	end         u64 // End of managed VA range (exclusive)
	top         u64 // Current allocation frontier (grows upward)
	allocations []&Allocation
	head_hole_order u64 // Recency rank of the hole before the first record
	hole_count u64 // Active hole ranks are exactly 1..hole_count
	garbage_count u64 // Deferred releases, ordered 1..garbage_count
	garbage_bytes u64 // Rounded reservation bytes awaiting collection
	lock        klock.Lock
mut:
	keep_garbage bool = true // Fixed at construction; private heaps defer reuse
}

// Create a new heap allocator managing the VA range [start, end).
pub fn new_heap(name string, start u64, end u64) HeapAllocator {
	mut heap := HeapAllocator{
		name: name
		start: start
		end: end
		top: start
		head_hole_order: if start < end { u64(1) } else { u64(0) }
		hole_count: if start < end { u64(1) } else { u64(0) }
	}
	// This table never escapes or has slices. All access holds the heap lock,
	// so capacity growth can immediately free its previous pointer buffer.
	heap.allocations.flags |= .noslices
	return heap
}

// Shared firmware heaps do not retain garbage in Asahi. Keep the ordinary
// constructor deferred for existing private heaps and select policy explicitly
// for classes whose release point already follows unmap/invalidation.
pub fn new_heap_with_garbage(name string, start u64, end u64, keep_garbage bool) HeapAllocator {
	mut heap := new_heap(name, start, end)
	heap.keep_garbage = keep_garbage
	return heap
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

// Caller holds the heap lock. Pending released records still occupy their
// ranges until GC unlinks them. Rank complete holes before alignment padding;
// equal-size holes use the newest eligible hole, as DRM MM's size tree does.
fn (h &HeapAllocator) find_address_locked(end u64, size u64, alignment u64) ?u64 {
	if h.start > end { return none }
	mut cursor := h.start
	mut best_address := u64(0)
	mut best_span := ~u64(0)
	mut best_order := u64(0)
	mut found := false
	for index := 0; index <= h.allocations.len; index++ {
		gap_end := if index < h.allocations.len && h.allocations[index].va < end {
			h.allocations[index].va
		} else { end }
		if address := heap_allocation_address(cursor, gap_end, size, alignment) {
			span := gap_end - cursor
			order := if index == 0 { h.head_hole_order } else { h.allocations[index - 1].hole_order }
			if !found || span < best_span || (span == best_span && order > best_order) {
				best_address = address
				best_span = span
				best_order = order
				found = true
			}
		}
		if index < h.allocations.len {
			record := h.allocations[index]
			cursor = record.va + record.size
		}
	}
	if !found { return none }
	return best_address
}

// Keep recency bounded by the number of current holes, rather than a lifetime
// sequence counter that could wrap. No hole owns another allocation record.
fn (mut h HeapAllocator) retire_hole_order_locked(order u64) {
	if order == 0 { return }
	if h.head_hole_order > order { h.head_hole_order-- }
	for mut record in h.allocations {
		if record.hole_order > order { record.hole_order-- }
	}
	h.hole_count--
}

fn (mut h HeapAllocator) newest_hole_order_locked() u64 {
	h.hole_count++
	return h.hole_count
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
	va := h.find_address_locked(h.end, aligned_size, actual_align) or {
		// Collect deferred releases only after the first placement attempt.
		// Retry the same checked range after GC makes its holes available.
		h.gc_locked()
		h.find_address_locked(h.end, aligned_size, actual_align) or {
			available := if h.top < h.end { h.end - h.top } else { u64(0) }
			C.printf(c'gpu alloc %s: out of VA space (need 0x%llx, avail 0x%llx)\n', h.name.str, aligned_size, available)
			return none
		}
	}
	if va + aligned_size > h.top { h.top = va + aligned_size }
	mut insertion := 0
	for insertion < h.allocations.len && h.allocations[insertion].va < va { insertion++ }
	gap_start := if insertion == 0 { h.start } else {
		previous := h.allocations[insertion - 1]
		previous.va + previous.size
	}
	gap_end := if insertion == h.allocations.len { h.end } else { h.allocations[insertion].va }
	old_order := if insertion == 0 { h.head_hole_order } else { h.allocations[insertion - 1].hole_order }
	h.retire_hole_order_locked(old_order)
	// DRM MM removes the selected hole, then inserts the leading remainder
	// before the trailing remainder. Preserve that order even when both fit.
	leading_order := if va > gap_start { h.newest_hole_order_locked() } else { u64(0) }
	if insertion == 0 { h.head_hole_order = leading_order } else {
		h.allocations[insertion - 1].hole_order = leading_order
	}
	trailing_order := if va + aligned_size < gap_end { h.newest_hole_order_locked() } else { u64(0) }

	a := &Allocation{
		va: va
		size: aligned_size
		in_use: true
		hole_order: trailing_order
	} @[freed]
	h.allocations << a
	// Append retains one explicit owner; rotating pointers avoids an insert
	// temporary and leaves every separately allocated record at its address.
	mut index := h.allocations.len - 1
	for index > 0 && h.allocations[index - 1].va > va {
		h.allocations[index] = h.allocations[index - 1]
		index--
	}
	h.allocations[index] = a

	return va
}

// Release the allocation at va. Deferred heaps reserve it until collection;
// immediate heaps retire this record before returning. Their pending count
// is zero on entry, so the one-item collection cannot retire a different owner.
pub fn (mut h HeapAllocator) release(va u64) {
	h.lock.acquire()
	defer {
		h.lock.release()
	}

	for mut a in h.allocations {
		if a.va == va && a.in_use {
			unsafe {
				a.in_use = false
				h.garbage_count++
				a.release_order = h.garbage_count
				h.garbage_bytes += a.size
			}
			if !h.keep_garbage { h.collect_garbage_locked(1) }
			return
		}
	}
}

// Collect every released record, including below a live allocation. Metadata
// is no longer needed once released. The removed intervals become reusable
// holes while all live record addresses stay fixed.
pub fn (mut h HeapAllocator) gc() {
	h.lock.acquire()
	defer {
		h.lock.release()
	}

	h.gc_locked()
}

// Internal GC implementation (caller must hold the lock).
fn (mut h HeapAllocator) gc_locked() {
	h.collect_garbage_locked(h.garbage_count)
}

// Return the count and rounded bytes of released but not yet reusable ranges.
pub fn (mut h HeapAllocator) garbage() (u64, u64) {
	h.lock.acquire()
	defer { h.lock.release() }
	return h.garbage_count, h.garbage_bytes
}

// Collect at most count deferred releases, oldest first. Other pending ranges
// remain reserved. The manager's gc() entry point still collects all of them.
pub fn (mut h HeapAllocator) collect_garbage(count u64) {
	h.lock.acquire()
	defer { h.lock.release() }
	h.collect_garbage_locked(count)
}

fn (mut h HeapAllocator) collect_garbage_locked(count u64) {
	mut collect_left := if count < h.garbage_count { count } else { h.garbage_count }
	for collect_left > 0 {
		mut idx := 0
		for idx < h.allocations.len {
			a := h.allocations[idx]
			if !a.in_use && a.release_order == 1 { break }
			idx++
		}
		if idx == h.allocations.len { return }
		mut a := h.allocations[idx]
		h.retire_hole_order_locked(a.hole_order)
		a.hole_order = 0
		// Removing a reservation reinserts its coalesced predecessor hole.
		if idx == 0 {
			h.retire_hole_order_locked(h.head_hole_order)
			h.head_hole_order = h.newest_hole_order_locked()
		} else {
			mut previous := h.allocations[idx - 1]
			h.retire_hole_order_locked(previous.hole_order)
			previous.hole_order = h.newest_hole_order_locked()
		}
		if a.va + a.size == h.top {
			// Alignment padding belongs to this reservation too. Restore
			// its original frontier so GC can reach the preceding record.
			h.top = if idx == 0 { h.start } else {
				previous := h.allocations[idx - 1]
				previous.va + previous.size
			}
		}
		h.garbage_count--
		h.garbage_bytes -= a.size
		// Compact FIFO ranks instead of using a sequence that can wrap.
		for mut pending in h.allocations {
			if pending.release_order > 1 { pending.release_order-- }
		}
		h.allocations.delete(idx)
		// The lock excludes every metadata reader. Unlink before freeing;
		// live records keep their addresses even when this is an interior.
		unsafe { free(a) }
		collect_left--
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
