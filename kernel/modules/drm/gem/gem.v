@[has_globals]
module gem

// GEM (Graphics Execution Manager) buffer object management.
// Allocates physically-contiguous pages and maps them into the
// kernel higher-half direct map so both the CPU and (via IOMMU)
// the GPU can access them.

import klock
import katomic
import memory
import lib

pub struct GemObject {
pub mut:
	handle      u32
	size        u64
	refcount    u64
	phys_addr   u64        // physical base address
	virt_addr   u64        // kernel virtual address (higher half)
	lock        klock.Lock
	mmap_offset u64
	name        string
}

const gem_max_handles = u32(4096)

__global (
	next_mmap_offset = u64(0x10000000) // start mmap offsets above 256 MiB
	gem_objects_lock klock.Lock
	gem_objects      [4096]&GemObject
)

// Create a new GEM object of the given size.
// Allocates physical pages and maps them to the higher half.
pub fn create(size u64) ?&GemObject {
	if size == 0 {
		return none
	}

	// Overflow-checked page alignment.
	if size > u64(-1) - (page_size - 1) {
		return none
	}
	aligned_size := lib.align_up(size, page_size)
	pages := aligned_size / page_size

	// Everything below runs under the table lock so handle selection, the
	// mmap-offset counter, and the physical allocation cannot race with other
	// creators. Handles are recycled by scanning for a free slot rather than
	// consuming a monotonic counter, and exhaustion is detected BEFORE any
	// physical memory is allocated.
	gem_objects_lock.acquire()
	defer {
		gem_objects_lock.release()
	}

	mut handle := u32(0)
	for i := u32(1); i < gem_max_handles; i++ {
		if gem_objects[i] == unsafe { nil } {
			handle = i
			break
		}
	}
	if handle == 0 {
		return none // handle table exhausted
	}

	// Fallible allocation: a user-sized request must never panic the kernel.
	phys := memory.pmm_alloc_fallible(pages)
	if phys == unsafe { nil } {
		return none
	}

	mmap_off := next_mmap_offset
	next_mmap_offset += aligned_size

	mut obj := &GemObject{
		handle:      handle
		size:        aligned_size
		refcount:    1
		phys_addr:   u64(phys)
		virt_addr:   u64(phys) + higher_half
		mmap_offset: mmap_off
	}

	gem_objects[handle] = obj

	return obj
}

// Destroy a GEM object: unmap from higher half and free physical pages.
pub fn destroy(obj &GemObject) {
	if obj == unsafe { nil } {
		return
	}

	gem_objects_lock.acquire()
	if obj.handle < gem_max_handles {
		gem_objects[obj.handle] = unsafe { nil }
	}
	gem_objects_lock.release()

	if obj.phys_addr != 0 {
		pages := obj.size / page_size
		memory.pmm_free(voidptr(obj.phys_addr), pages)
	}
}

// Look up a GEM object by its handle.
pub fn get_by_handle(handle u32) ?&GemObject {
	if handle == 0 || handle >= gem_max_handles {
		return none
	}

	gem_objects_lock.acquire()
	obj := gem_objects[handle]
	gem_objects_lock.release()

	if obj == unsafe { nil } {
		return none
	}
	return obj
}

// Increment the reference count of a GEM object.
pub fn ref_obj(obj &GemObject) {
	if obj == unsafe { nil } {
		return
	}
	mut rc := unsafe { &obj.refcount }
	katomic.inc(mut rc)
}

// Decrement the reference count. If it reaches zero the object is destroyed.
pub fn unref(obj &GemObject) {
	if obj == unsafe { nil } {
		return
	}
	mut rc := unsafe { &obj.refcount }
	if !katomic.dec(mut rc) {
		// refcount reached zero
		destroy(obj)
	}
}

// Return (or lazily create) the mmap offset for user-space mapping.
pub fn create_mmap_offset(obj &GemObject) u64 {
	if obj == unsafe { nil } {
		return 0
	}
	return obj.mmap_offset
}
