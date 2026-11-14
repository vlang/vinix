@[has_globals]
module memory

__global reject_metadata = false
__global live_metadata = 0

pub fn fail_next(fail bool) { reject_metadata = fail }

pub fn outstanding() int { return live_metadata }

pub fn malloc_packed_fallible(size u64) voidptr {
	if reject_metadata { return unsafe { nil } }
	result := unsafe { C.malloc(size) }
	if result != unsafe { nil } { live_metadata++ }
	return result
}

pub fn free(data voidptr) {
	assert live_metadata > 0
	live_metadata--
	unsafe { C.free(data) }
}
