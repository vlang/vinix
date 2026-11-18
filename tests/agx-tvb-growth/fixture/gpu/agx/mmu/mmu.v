module mmu

pub struct UatBuffer {
pub mut:
	va       u64
	phys     u64
	size     u64
	released bool
	mapped bool
	cache_flush_pending bool
	uncached bool
}

pub fn (buffer &UatBuffer) cpu_address() voidptr { return voidptr(buffer.phys) }
pub fn (buffer &UatBuffer) needs_cache_flush() bool { return buffer.cache_flush_pending }

pub struct UatContext {
pub mut:
	id        u32 = 1
	active    bool = true
	bound     bool = true
	allocated int
	released  int
	fail_at   int = -1
	fail_map_at int = -1
	map_failures int
	pool      [32]UatBuffer
	check     fn () = unsafe { nil }
}

pub struct UatManager {
pub mut:
	current bool
	available bool = true
}

pub fn (mut mgr UatManager) g13_cache_flush_required(context &UatContext, slot u32) ?bool {
	assert slot == 1 && context.bound_slot() == slot
	if !mgr.available { return none }
	return mgr.current
}

pub fn (context &UatContext) bound_slot() u32 {
	return if context.bound { u32(1) } else { u32(0) }
}

pub fn (mut context UatContext) reprotect_driver_buffer_uncached(buffer &UatBuffer) bool {
	mut owned := unsafe { buffer }
	if owned.mapped { owned.uncached = true }
	return true
}

pub fn (mut context UatContext) complete_driver_buffer_cache_flush(buffer &UatBuffer) bool {
	mut owned := unsafe { buffer }
	if !owned.mapped || !owned.uncached { return false }
	owned.cache_flush_pending = false
	return true
}

pub fn (mut context UatContext) unmap_driver_buffer(buffer &UatBuffer) bool {
	mut owned := unsafe { buffer }
	owned.mapped = false
	return true
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
	if index == context.fail_map_at {
		unsafe { C.free(storage) }
		context.released++
		context.map_failures++
		return none
	}
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
