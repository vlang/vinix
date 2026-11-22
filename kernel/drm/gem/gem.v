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

pub const dma_buf_name_capacity = 32

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
	phys_addr   u64        // physical base address; 0 when scattered
	virt_addr   u64        // kernel virtual address (higher half); 0 when scattered
	pages       &u64 = unsafe { nil } // one physical page address per page when scattered
	lock        klock.Lock
	mmap_offset u64
	pte_extra   u64 // identical cache attributes for kernel and user aliases
	external    bool // host-visible aperture; never returned to the PMM
	advice_dontneed bool // private BO advice; resident backing is not yet purgeable
	prime_fences &PrimeFence = unsafe { nil } // protected by lock
	// The lock protects the shared DMA-BUF name. Length includes the NUL.
	prime_name [dma_buf_name_capacity]u8
	prime_name_len u8
	// Serial of the DRM client that created this user object, for its fdinfo
	// totals; zero for kernel and imported objects. Set once, before the
	// creator publishes the handle.
	creator u64
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
	// Bytes of live user objects, counted once against their creator: what
	// Asahi's gpu_memory calls user_committed.
	gem_user_committed = u64(0)
)

// Tag `obj` as created by the DRM client `creator`, and count it in the device
// total until it is destroyed. Called once, before the creator publishes the
// handle, so no other client can see the object yet.
pub fn set_creator(obj &GemObject, creator u64) {
	if obj == unsafe { nil } || creator == 0 || obj.creator != 0 { return }
	mut owned := unsafe { obj }
	owned.creator = creator
	adjust_user_committed(obj.size, true)
}

pub fn user_committed() u64 {
	return katomic.load(&gem_user_committed)
}

fn adjust_user_committed(size u64, add bool) {
	gem_objects_lock.acquire()
	gem_user_committed = if add {
		gem_user_committed + size
	} else if gem_user_committed >= size {
		gem_user_committed - size
	} else {
		u64(0)
	}
	gem_objects_lock.release()
}

// Create a new GEM object of the given size.
// Allocates physical pages and maps them to the higher half.
pub fn create(size u64) ?&GemObject {
	return create_aligned(size, page_size)
}

// Create a GEM object with a physical and size alignment suitable for the
// target device. AGX callers require 16 KiB alignment on either kernel granule.
pub fn create_aligned(size u64, alignment u64) ?&GemObject {
	return create_object(size, alignment, false, 0, 0, false, 0, false)
}

// Set the private reservation identity before the object becomes visible in
// any handle table. Only its owning VM may bind it, and PRIME cannot export it.
pub fn create_aligned_private(size u64, alignment u64, identity u64) ?&GemObject {
	if identity == 0 { return none }
	return create_object(size, alignment, false, identity, 0, false, 0, false)
}

// AGX CPU mappings are Normal Non-Cacheable unless WRITEBACK was requested.
// Select both the direct-map and future userspace attributes before publishing
// the object. Other GEM constructors retain their existing cacheable policy.
pub fn create_aligned_with_cache(size u64, alignment u64, identity u64, writeback bool, file_scoped bool, registration MmapRegistration) ?&GemObject {
	$if !arm64 { if !writeback { return none } }
	return create_object(size, alignment, false, identity, if writeback { u64(0) } else { memory.pte_uncached }, file_scoped, registration.mmap_device, true)
}

// Metadata for a host-owned resource. The driver installs its physical
// aperture after RESOURCE_MAP_BLOB succeeds; the PMM never owns those pages.
pub fn create_external(size u64) ?&GemObject {
	return create_object(size, page_size, true, 0, 0, false, 0, false)
}

fn create_object(size u64, alignment u64, external bool, private_identity u64, pte_extra u64, file_scoped bool, mmap_device u64, scatter bool) ?&GemObject {
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

	// Allocate the unpublished metadata and backing before taking the registry
	// lock: page allocation can reclaim, the lock masks interrupts, and nothing
	// else can see either until publication.
	storage := memory.malloc_packed_fallible(sizeof(GemObject))
	if storage == unsafe { nil } { return none }
	room := external || memory.user_room(pages)
	phys := if external || !room { unsafe { nil } } else { memory.pmm_alloc_aligned_fallible(pages, alignment / page_size) }
	mut page_list := unsafe { &u64(nil) }
	if !external && phys == unsafe { nil } {
		// A fragmented PMM can lack one run this long while plenty of pages are
		// free. Objects that allow it are backed by single pages instead; a
		// one-page object has nothing to split.
		if room && scatter && alignment == page_size && pages > 1 {
			page_list = alloc_scattered_pages(pages, pte_extra) or { unsafe { nil } }
		}
		if page_list == unsafe { nil } {
			memory.free(storage)
			return none
		}
	}
	$if arm64 {
		if phys != unsafe { nil } && pte_extra & memory.pte_uncached != 0 {
			if !memory.set_ram_direct_map_uncached(u64(phys), aligned_size, true) {
				memory.pmm_free(phys, pages)
				memory.free(storage)
				return none
			}
		}
	}

	// Serialize the mmap-offset counter and, for globally named objects,
	// keep the chosen handle available until the object is published.
	gem_objects_lock.acquire()
	mut handle := u32(0)
	mut publishable := true
	if !file_scoped {
		for i := u32(1); i < gem_max_handles; i++ {
			if gem_objects[i] == unsafe { nil } {
				handle = i
				break
			}
		}
		if handle == 0 { publishable = false }
	}
	if publishable && aligned_size > u64(-1) - next_mmap_offset { publishable = false }
	if !publishable {
		gem_objects_lock.release()
		release_unpublished_backing(phys, page_list, pages, pte_extra)
		memory.free(storage)
		return none
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
			virt_addr:   if page_list != unsafe { nil } { u64(0) } else { u64(phys) + higher_half }
			pages:       page_list
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
	gem_objects_lock.release()
	return obj
}

// Free backing that was never published: the object never reached a table.
fn release_unpublished_backing(phys voidptr, list &u64, page_count u64, pte_extra u64) {
	if list != unsafe { nil } {
		free_scattered_pages(list, page_count, pte_extra)
		return
	}
	if phys == unsafe { nil } { return }
	$if arm64 {
		if pte_extra & memory.pte_uncached != 0
			&& !memory.set_ram_direct_map_uncached(u64(phys), page_count * page_size, false) {
			panic('GEM direct-map cache policy could not be restored')
		}
	}
	memory.pmm_free(phys, page_count)
}

// Destroy a GEM object: unmap from higher half and free physical pages.
pub fn destroy(obj &GemObject) {
	if obj == unsafe { nil } {
		return
	}
	if obj.creator != 0 { adjust_user_committed(obj.size, false) }
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
	if obj.pages != unsafe { nil } {
		free_scattered_pages(obj.pages, obj.size / page_size, obj.pte_extra)
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

// Allocate `page_count` single pages for an object that no contiguous run could
// hold, each with the object's direct-map cache policy. All or nothing.
fn alloc_scattered_pages(page_count u64, pte_extra u64) ?&u64 {
	if page_count == 0 || page_count > u64(-1) / sizeof(u64) { return none }
	list := unsafe { &u64(memory.malloc_packed_fallible(page_count * sizeof(u64))) }
	if list == unsafe { nil } { return none }
	for index := u64(0); index < page_count; index++ {
		page := memory.pmm_alloc_fallible(1)
		if page == unsafe { nil } {
			free_scattered_pages(list, index, pte_extra)
			return none
		}
		$if arm64 {
			if pte_extra & memory.pte_uncached != 0
				&& !memory.set_ram_direct_map_uncached(u64(page), page_size, true) {
				memory.pmm_free(page, 1)
				free_scattered_pages(list, index, pte_extra)
				return none
			}
		}
		unsafe { list[index] = u64(page) }
	}
	return list
}

// Release the first `page_count` pages of a scattered list and the list itself,
// restoring each page's cacheable direct mapping before the PMM reuses it.
fn free_scattered_pages(list &u64, page_count u64, pte_extra u64) {
	for index := u64(0); index < page_count; index++ {
		page := unsafe { list[index] }
		$if arm64 {
			if pte_extra & memory.pte_uncached != 0
				&& !memory.set_ram_direct_map_uncached(page, page_size, false) {
				panic('GEM direct-map cache policy could not be restored')
			}
		}
		memory.pmm_free(voidptr(page), 1)
	}
	memory.free(voidptr(list))
}

// Look up a global handle and take a reference for the caller to release.
pub fn lookup_referenced(handle u32) ?&GemObject {
	if handle == 0 || handle >= gem_max_handles {
		return none
	}

	gem_objects_lock.acquire()
	defer { gem_objects_lock.release() }
	obj := gem_objects[handle]

	if obj == unsafe { nil } {
		return none
	}
	mut refs_now := katomic.load(unsafe { &obj.refcount })
	// A final put can reach zero before it acquires the registry lock to
	// unlink the object. The lock keeps its storage live during the lookup.
	for refs_now != 0 && refs_now != ~u64(0) {
		if katomic.cas(mut unsafe { &obj.refcount }, refs_now, refs_now + 1) { return obj }
		refs_now = katomic.load(unsafe { &obj.refcount })
	}
	return none
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
		memory.free(voidptr(obj))
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
	return voidptr(obj.page_phys(byte_offset - obj.mmap_offset) or { return none })
}
