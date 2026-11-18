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

pub struct PrimeFence {
pub:
	source voidptr // published DmaFence metadata, retained by syncobj
pub mut:
	write bool
	next &PrimeFence = unsafe { nil }
}

pub fn free_prime_fences(head &PrimeFence) {
	mut current := unsafe { head }
	for current != unsafe { nil } {
		next := current.next
		memory.free(voidptr(current))
		current = next
	}
}

@[heap]
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
	pte_extra   u64 // identical cache attributes for kernel and user aliases
	external    bool // host-visible aperture; never returned to the PMM
	advice_dontneed bool // private BO advice; resident backing is not yet purgeable
	prime_fences &PrimeFence = unsafe { nil } // protected by lock
pub:
	vm_private_identity u64 // zero: shareable; otherwise immutable owning VM identity
	file_scoped bool // excluded from the global handle table
mut:
	mmap_device u64
	mmap_previous &GemObject = unsafe { nil }
	mmap_next &GemObject = unsafe { nil }
}

@[params]
pub struct MmapRegistration {
pub:
	mmap_device u64 // opaque DRM registration identity
}

const gem_max_handles = u32(4096)

__global (
	next_mmap_offset = u64(0x10000000) // start mmap offsets above 256 MiB
	gem_objects_lock klock.Lock
	gem_objects      [4096]&GemObject
	file_mmap_objects &GemObject = unsafe { nil }
)

// Create a new GEM object of the given size.
// Allocates physical pages and maps them to the higher half.
pub fn create(size u64) ?&GemObject {
	return create_aligned(size, page_size)
}

// Create a GEM object with a physical and size alignment suitable for the
// target device. AGX callers require 16 KiB alignment on either kernel granule.
pub fn create_aligned(size u64, alignment u64) ?&GemObject {
	return create_object(size, alignment, false, 0, 0, false, 0)
}

// Set the private reservation identity before the object becomes visible in
// any handle table. Only its owning VM may bind it, and PRIME cannot export it.
pub fn create_aligned_private(size u64, alignment u64, identity u64) ?&GemObject {
	if identity == 0 { return none }
	return create_object(size, alignment, false, identity, 0, false, 0)
}

// AGX CPU mappings are Normal Non-Cacheable unless WRITEBACK was requested.
// Select both the direct-map and future userspace attributes before publishing
// the object. Other GEM constructors retain their existing cacheable policy.
pub fn create_aligned_with_cache(size u64, alignment u64, identity u64, writeback bool, file_scoped bool, registration MmapRegistration) ?&GemObject {
	$if !arm64 { if !writeback { return none } }
	return create_object(size, alignment, false, identity, if writeback { u64(0) } else { memory.pte_uncached }, file_scoped, registration.mmap_device)
}

// Metadata for a host-owned resource. The driver installs its physical
// aperture after RESOURCE_MAP_BLOB succeeds; the PMM never owns those pages.
pub fn create_external(size u64) ?&GemObject {
	return create_object(size, page_size, true, 0, 0, false, 0)
}

fn create_object(size u64, alignment u64, external bool, private_identity u64, pte_extra u64, file_scoped bool, mmap_device u64) ?&GemObject {
	if size == 0 {
		return none
	}
	if alignment < page_size || alignment & (alignment - 1) != 0 || alignment % page_size != 0 {
		return none
	}

	// Overflow-checked device alignment. AGX buffers must retain their 16 KiB
	// size and physical-address alignment while remaining fallible.
	if size > u64(-1) - (alignment - 1) {
		return none
	}
	aligned_size := lib.align_up(size, alignment)
	pages := aligned_size / page_size

	// Serialize the mmap-offset counter and, for globally named objects,
	// keep the chosen handle available until the object is published.
	gem_objects_lock.acquire()
	defer {
		gem_objects_lock.release()
	}

	mut handle := u32(0)
	if !file_scoped {
		for i := u32(1); i < gem_max_handles; i++ {
			if gem_objects[i] == unsafe { nil } {
				handle = i
				break
			}
		}
		if handle == 0 { return none }
	}
	if aligned_size > u64(-1) - next_mmap_offset {
		return none
	}

	// Reserve the unpublished metadata before allocating or retagging backing.
	storage := memory.malloc_packed_fallible(sizeof(GemObject))
	if storage == unsafe { nil } { return none }
	phys := if external || !memory.user_room(pages) { unsafe { nil } } else { memory.pmm_alloc_aligned_fallible(pages, alignment / page_size) }
	if !external && phys == unsafe { nil } {
		memory.free(storage)
		return none
	}
	$if arm64 {
		if pte_extra & memory.pte_uncached != 0 {
			if !memory.set_ram_direct_map_uncached(u64(phys), aligned_size, true) {
				memory.pmm_free(phys, pages)
				memory.free(storage)
				return none
			}
		}
	}

	mmap_off := next_mmap_offset
	next_mmap_offset += aligned_size

	mut obj := unsafe { &GemObject(storage) }
	unsafe {
		*obj = GemObject{
			handle:      handle
			external:    external
			pte_extra:   pte_extra
			vm_private_identity: private_identity
			file_scoped: file_scoped
			size:        aligned_size
			refcount:    1
			phys_addr:   u64(phys)
			virt_addr:   u64(phys) + higher_half
			mmap_offset: mmap_off
		}
	}

	if !file_scoped { gem_objects[handle] = obj }
	if file_scoped && mmap_device != 0 {
		obj.mmap_device = mmap_device
		obj.mmap_next = unsafe { file_mmap_objects }
		if file_mmap_objects != unsafe { nil } { file_mmap_objects.mmap_previous = obj }
		file_mmap_objects = obj
	}

	return obj
}

// Destroy a GEM object: unmap from higher half and free physical pages.
pub fn destroy(obj &GemObject) {
	if obj == unsafe { nil } {
		return
	}
	free_prime_fences(obj.prime_fences)
	if !obj.file_scoped && obj.handle < gem_max_handles {
		gem_objects_lock.acquire()
		gem_objects[obj.handle] = unsafe { nil }
		gem_objects_lock.release()
	}
	if obj.mmap_device != 0 {
		gem_objects_lock.acquire()
		mut previous := unsafe { obj.mmap_previous }
		mut next := unsafe { obj.mmap_next }
		if previous == unsafe { nil } { file_mmap_objects = next }
		else { previous.mmap_next = next }
		if next != unsafe { nil } { next.mmap_previous = unsafe { previous } }
		gem_objects_lock.release()
	}
	$if arm64 {
		if obj.phys_addr != 0 && !obj.external && obj.pte_extra & memory.pte_uncached != 0 {
			if !memory.set_ram_direct_map_uncached(obj.phys_addr, obj.size, false) {
				panic('GEM direct-map cache policy could not be restored')
			}
		}
	}

	if obj.phys_addr != 0 && !obj.external {
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
		if obj.external || obj.file_scoped { memory.free(voidptr(obj)) }
	}
}

// Return (or lazily create) the mmap offset for user-space mapping.
pub fn create_mmap_offset(obj &GemObject) u64 {
	if obj == unsafe { nil } {
		return 0
	}
	return obj.mmap_offset
}

// Classify a missing file handle without granting access to another file's
// BO. The list owns no references and final release unlinks under this lock.
pub fn file_mmap_offset_exists(device u64, offset u64, length u64) bool {
	if device == 0 || length == 0 { return false }
	gem_objects_lock.acquire()
	defer { gem_objects_lock.release() }
	mut object := unsafe { file_mmap_objects }
	for object != unsafe { nil } && object.mmap_offset >= offset {
		if object.mmap_offset == offset {
			return object.mmap_device == device && length <= object.size && katomic.load(unsafe { &object.refcount }) != 0
		}
		object = unsafe { object.mmap_next }
	}
	return false
}

// Resolve a fake DRM mmap page only within one already-authorized object.
// The caller owns a reference to obj for the full mapping lifetime.
pub fn get_object_mmap_page(obj &GemObject, page u64) ?voidptr {
	if obj == unsafe { nil } || page > u64(0xffff_ffff_ffff_ffff) / page_size
		|| (obj.external && obj.phys_addr == 0) {
		return none
	}
	byte_offset := page * page_size
	if byte_offset < obj.mmap_offset || byte_offset - obj.mmap_offset >= obj.size {
		return none
	}
	return voidptr(obj.phys_addr + byte_offset - obj.mmap_offset)
}
