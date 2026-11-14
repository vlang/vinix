module gem

pub struct GemObject {
pub mut:
	references int = 1
}

pub fn unref(object &GemObject) {
	mut owned := unsafe { object }
	assert owned.references > 0
	owned.references--
}
