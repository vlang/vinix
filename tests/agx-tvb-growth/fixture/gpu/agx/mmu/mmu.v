module mmu

pub struct UatBuffer {
pub mut:
	va       u64
	phys     u64
	size     u64
	released bool
}

pub fn (buffer &UatBuffer) cpu_address() voidptr { return voidptr(buffer.phys) }

pub struct UatContext {
pub mut:
	id        u32 = 1
	allocated int
	released  int
	fail_at   int = -1
	pool      [32]UatBuffer
	check     fn () = unsafe { nil }
}

pub fn (mut context UatContext) alloc_driver_buffer_aligned(size u64, private bool, alignment u64) ?&UatBuffer {
	assert !private && size == 0x20000 && alignment == 0x8000
	if context.check != unsafe { nil } { context.check() }
	if context.allocated == context.fail_at { return none }
	index := context.allocated
	context.allocated++
	context.pool[index] = UatBuffer{ va: 0x100000 + u64(index) * 0x20000, size: size }
	return unsafe { &context.pool[index] }
}

pub fn (mut context UatContext) release_driver_buffer(buffer &UatBuffer) {
	mut owned := unsafe { buffer }
	assert !owned.released
	owned.released = true
	context.released++
}
