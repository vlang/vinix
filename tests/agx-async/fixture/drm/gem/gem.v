module gem

pub struct GemObject {
pub mut:
	size       u64
	virt_addr  u64
	references int = 1
}

pub fn ref_obj(object &GemObject) {
	unsafe { object.references++ }
}

pub fn unref(object &GemObject) {
	assert object.references > 0
	unsafe { object.references-- }
}
