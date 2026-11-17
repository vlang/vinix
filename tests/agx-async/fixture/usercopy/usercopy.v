@[has_globals]
module usercopy

__global reject_copy = false
__global copy_reads = 0
__global reject_read = -1
__global before_copy fn () = unsafe { nil }

pub fn reject(value bool) { reject_copy = value }
pub fn reset_reads() { copy_reads = 0 }
pub fn reads() int { return copy_reads }
pub fn reject_at(index int) { reject_read = index; copy_reads = 0 }
pub fn before_once(callback fn ()) {
	assert before_copy == unsafe { nil }
	before_copy = callback
}

pub fn copy_from_user(target voidptr, source u64, size u64) bool {
	copy_reads++
	if reject_read == copy_reads - 1 { return false }
	if before_copy != unsafe { nil } {
		callback := before_copy
		before_copy = unsafe { nil }
		callback()
	}
	if reject_copy { return false }
	unsafe { C.memcpy(target, voidptr(source), size) }
	return true
}
