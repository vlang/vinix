module memory

pub fn malloc_packed_fallible(n u64) voidptr { return unsafe { malloc(int(n)) } }

pub fn free(p voidptr) {
	unsafe { free(p) }
}
