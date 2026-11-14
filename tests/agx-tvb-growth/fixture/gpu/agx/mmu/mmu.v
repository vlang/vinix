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
	active    bool = true
	allocated int
	released  int
	fail_at   int = -1
	pool      [32]UatBuffer
	check     fn () = unsafe { nil }
}

pub fn (mut context UatContext) alloc_driver_buffer_aligned(size u64, private bool, alignment u64) ?&UatBuffer {
	assert alignment == 0x8000
	if !private { assert size == 0x20000 }
	if context.check != unsafe { nil } { context.check() }
	if context.allocated == context.fail_at { return none }
	index := context.allocated
	context.allocated++
	storage := if private { unsafe { C.calloc(1, size) } } else { unsafe { nil } }
	if private { assert storage != unsafe { nil } }
	context.pool[index] = UatBuffer{ va: 0x100000 + u64(index) * 0x20000, size: size, phys: u64(storage) }
	return unsafe { &context.pool[index] }
}

pub fn (mut context UatContext) release_driver_buffer(buffer &UatBuffer) {
	if buffer == unsafe { nil } { return }
	mut owned := unsafe { buffer }
	assert !owned.released
	owned.released = true
	if owned.phys != 0 { unsafe { C.free(voidptr(owned.phys)) } }
	context.released++
}
