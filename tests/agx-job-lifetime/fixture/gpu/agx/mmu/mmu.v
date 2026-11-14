module mmu

pub struct UatBuffer {
pub mut:
	released bool
}

pub struct UatContext {
pub mut:
	active   bool = true
	id       u32  = 1
	releases int
}

pub fn (mut context UatContext) release_driver_buffer(buffer &UatBuffer) {
	if buffer == unsafe { nil } { return }
	mut owned := unsafe { buffer }
	assert !owned.released, 'driver buffer released twice'
	owned.released = true
	context.releases++
}
