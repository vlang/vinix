@[has_globals]
module memory

__global reject_metadata = false
__global live_metadata = 0
__global remaining_allocations = -1

pub fn fail_next(fail bool) { reject_metadata = fail }

pub fn fail_after(count int) { remaining_allocations = count }

pub fn outstanding() int { return live_metadata }

pub fn malloc_packed_fallible(size u64) voidptr {
	if reject_metadata || remaining_allocations == 0 { return unsafe { nil } }
	if remaining_allocations > 0 { remaining_allocations-- }
	result := unsafe { C.malloc(size) }
	if result != unsafe { nil } { live_metadata++ }
	return result
}

pub fn free(data voidptr) {
	assert live_metadata > 0
	live_metadata--
	unsafe { C.free(data) }
}
