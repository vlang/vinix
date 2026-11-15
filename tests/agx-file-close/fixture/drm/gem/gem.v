@[has_globals]
module gem

__global live_objects = 0

pub fn live() int { return live_objects }

pub struct GemObject {
pub mut:
	references int = 1
	handle u32
	size u64 = 0x10000
	phys_addr u64 = 0x200000
	owned bool
}

pub fn create(handle u32) &GemObject {
	mut object := unsafe { &GemObject(C.malloc(sizeof(GemObject))) }
	assert object != unsafe { nil }
	unsafe { *object = GemObject{ handle: handle, owned: true } }
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
		live_objects--
		unsafe { C.free(object) }
	}
}

pub fn create_mmap_offset(object &GemObject) u64 { return u64(object.handle) * 0x10000 }
pub fn get_object_mmap_page(object &GemObject, page u64) ?voidptr { return none }
