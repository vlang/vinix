@[has_globals]
module memory

__global live_nodes = 0
__global fail_node = false
__global fail_allocation_at = -1
__global allocation_calls = 0

pub fn outstanding() int { return live_nodes }

pub fn fail_next(value bool) { fail_node = value }

pub fn fail_at(index int) {
	fail_allocation_at = index
	allocation_calls = 0
}

pub fn malloc_packed_fallible(size u64) voidptr {
	if fail_node { return unsafe { nil } }
	index := allocation_calls
	allocation_calls++
	if index == fail_allocation_at { return unsafe { nil } }
	ptr := unsafe { C.malloc(size) }
	assert ptr != unsafe { nil }
	live_nodes++
	return ptr
}

pub fn free(ptr voidptr) {
	assert live_nodes > 0
	live_nodes--
	unsafe { C.free(ptr) }
}
