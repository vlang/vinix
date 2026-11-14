@[has_globals]
module memory

__global fail_metadata = false

pub fn fail_next(fail bool) { fail_metadata = fail }

pub fn malloc_packed_fallible(size u64) voidptr {
	if fail_metadata { return unsafe { nil } }
	return unsafe { C.malloc(size) }
}
