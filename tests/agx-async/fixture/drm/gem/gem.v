@[has_globals]
module gem

__global higher_half = u64(0) // host fixtures address backing directly

pub struct GemObject {
pub mut:
	size       u64
	virt_addr  u64
	phys_addr  u64
	external   bool
	references int = 1
}

pub fn ref_obj(object &GemObject) {
	unsafe { object.references++ }
}

pub fn unref(object &GemObject) {
	assert object.references > 0
	unsafe { object.references-- }
}
