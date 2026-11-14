module memory

fn C.malloc(usize) voidptr
fn C.free(voidptr)

pub fn malloc_packed_fallible(n u64) voidptr { return unsafe { C.malloc(usize(n)) } }

pub fn free(p voidptr) {
	unsafe { C.free(p) }
}
