module c

fn C.memcpy(dest voidptr, src voidptr, count u64) voidptr
pub fn memcpy(dest voidptr, src voidptr, count u64) voidptr {
	return C.memcpy(dest, src, count)
}
