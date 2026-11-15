@[has_globals]
module usercopy

__global start = u64(0)
__global length = u64(0)
__global fail = false
__global pub reads = 0

pub fn allow(address u64, size u64) { start = address; length = size; fail = false; reads = 0 }
pub fn inject_fault() { fail = true }

pub fn copy_from_user(output voidptr, input u64, size u64) bool {
	reads++
	if fail || input == 0 || input < start || input - start > length
		|| size > length - (input - start) { return false }
	unsafe { C.memcpy(output, voidptr(input), size) }
	return true
}
