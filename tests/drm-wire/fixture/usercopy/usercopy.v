@[has_globals]
module usercopy

__global fail_address = u64(0)

pub fn fail_at(address u64) { fail_address = address }

pub fn copy_from_user(output voidptr, input u64, size u64) bool {
	if input == fail_address && size != 0 { return false }
	unsafe { C.memcpy(output, voidptr(input), size) }
	return true
}

pub fn copy_to_user(output u64, input voidptr, size u64) bool {
	if output == fail_address && size != 0 { return false }
	unsafe { C.memcpy(voidptr(output), input, size) }
	return true
}
