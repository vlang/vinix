@[has_globals]
module gem

import klock

__global live_objects = 0
__global higher_half = u64(0) // host fixtures address backing directly
__global next_created_handle = u32(100)
__global reject_create = false
__global create_calls = u64(0)
__global file_mmap_objects [32]&GemObject

pub fn live() int { return live_objects }
pub fn get_by_handle(_handle u32) ?&GemObject { return none }
pub fn fail_creates(reject bool) { reject_create = reject }
pub fn creates() u64 { return create_calls }

pub struct GemObject {
pub mut:
	references int = 1
	handle u32
	size u64 = 0x10000
	phys_addr u64 = 0x200000
	virt_addr u64
	mmap_offset u64
	mmap_device u64
	owned bool
	vm_private_identity u64
	pte_extra u64
	external bool
	file_scoped bool
	advice_dontneed bool
	prime_fences &PrimeFence = unsafe { nil }
	lock klock.Lock
}

@[params]
pub struct MmapRegistration {
pub:
	mmap_device u64
}

pub fn create_aligned_with_cache(size u64, alignment u64, identity u64, writeback bool, file_scoped bool, registration MmapRegistration) ?&GemObject {
	mut object := create_aligned(size, alignment) or { return none }
	object.vm_private_identity = identity
	object.pte_extra = if writeback { u64(0) } else { u64(0x10) }
	if file_scoped {
		object.handle = 0
		object.file_scoped = true
	}
	if file_scoped && registration.mmap_device != 0 {
		object.mmap_device = registration.mmap_device
		for index, entry in file_mmap_objects {
			if entry == unsafe { nil } {
				file_mmap_objects[index] = object
				return object
			}
		}
		panic('fixture mmap registry full')
	}
	return object
}

pub fn create_aligned(size u64, alignment u64) ?&GemObject {
	create_calls++
	if reject_create || size == 0 { return none }
	next_created_handle++
	mut object := create(next_created_handle)
	object.size = (size + alignment - 1) & ~(alignment - 1)
	return object
}

pub fn create_aligned_private(size u64, alignment u64, identity u64) ?&GemObject {
	if identity == 0 { return none }
	mut object := create_aligned(size, alignment) or { return none }
	object.vm_private_identity = identity
	return object
}

pub fn create(handle u32) &GemObject {
	mut object := unsafe { &GemObject(C.malloc(sizeof(GemObject))) }
	assert object != unsafe { nil }
	unsafe { *object = GemObject{ handle: handle, mmap_offset: u64(handle) * 0x10000, owned: true } }
	live_objects++
	return object
}

pub fn ref_obj(object &GemObject) {
	mut owned := unsafe { object }
	assert owned.references > 0
	owned.references++
}

pub fn unref(object &GemObject) {
	mut owned := unsafe { object }
	assert owned.references > 0
	owned.references--
	if owned.references == 0 && owned.owned {
		free_prime_fences(owned.prime_fences)
		if owned.mmap_device != 0 {
			for index, entry in file_mmap_objects {
				if voidptr(entry) == voidptr(owned) { file_mmap_objects[index] = unsafe { nil }; break }
			}
		}
		live_objects--
		unsafe { C.free(object) }
	}
}

pub fn file_mmap_offset_exists(device u64, offset u64, length u64) bool {
	for object in file_mmap_objects {
		if object != unsafe { nil } && object.mmap_device == device && object.mmap_offset == offset {
			return length != 0 && length <= object.size
		}
	}
	return false
}

pub fn create_mmap_offset(object &GemObject) u64 {
	return if object.mmap_offset != 0 { object.mmap_offset } else { u64(object.handle) * 0x10000 }
}
pub fn get_object_mmap_page(object &GemObject, page u64) ?voidptr {
	if page > ~u64(0) / 0x4000 { return none }
	address := page * 0x4000
	offset := create_mmap_offset(object)
	if address < offset || address - offset >= object.size { return none }
	return voidptr(object.phys_addr + address - offset)
}
