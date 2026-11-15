@[has_globals]
module usercopy

__global reject_copy = false

pub fn reject(value bool) { reject_copy = value }

pub fn copy_from_user(target voidptr, source u64, size u64) bool {
	if reject_copy { return false }
	unsafe { C.memcpy(target, voidptr(source), size) }
	return true
}
