@[has_globals]
module memory

__global live_nodes = 0
__global fail_node = false
__global fail_allocation_at = -1
__global allocation_calls = 0
__global object_metadata [2048]voidptr
__global chain_metadata [16384]voidptr
__global chain_live = 0

// Exact production-site injection distinguishes retained chain metadata from
// pending job buffers. Reservations still consume the same failure sequence;
// tests account for their separate allocation/free totals explicitly.
pub fn malloc_chain_fallible(size u64) voidptr {
	ptr := malloc_packed_fallible(size)
	if ptr == unsafe { nil } { return ptr }
	live_nodes--
	for index in 0 .. chain_metadata.len {
		if chain_metadata[index] == unsafe { nil } {
			chain_metadata[index] = ptr; chain_live++; return ptr
		}
	}
	panic('fixture chain metadata table exhausted')
}

pub fn outstanding_chains() int { return chain_live }

// Submission fault positions/counters cover job storage. Published syncobj
// metadata has its own lifetime; CREATE's allocation failures are exercised
// by the dedicated DRM fixture against the same production constructor.
pub fn malloc_syncobj_fallible(size u64) voidptr {
	ptr := unsafe { C.malloc(size) }
	if ptr == unsafe { nil } { return ptr }
	for index in 0 .. object_metadata.len {
		if object_metadata[index] == unsafe { nil } { object_metadata[index] = ptr; return ptr }
	}
	panic('fixture object metadata table exhausted')
}

pub fn outstanding() int { return live_nodes }
pub fn attempts() int { return allocation_calls }

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
	for index in 0 .. chain_metadata.len {
		if chain_metadata[index] == ptr && ptr != unsafe { nil } {
			chain_metadata[index] = unsafe { nil }; chain_live--; unsafe { C.free(ptr) }; return
		}
	}
	for index in 0 .. object_metadata.len {
		if object_metadata[index] == ptr && ptr != unsafe { nil } {
			object_metadata[index] = unsafe { nil }; unsafe { C.free(ptr) }; return
		}
	}
	assert live_nodes > 0
	live_nodes--
	unsafe { C.free(ptr) }
}
