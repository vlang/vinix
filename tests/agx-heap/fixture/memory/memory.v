module memory

pub fn malloc_packed_fallible(size u64) voidptr {
	return unsafe { C.malloc(size) }
}
