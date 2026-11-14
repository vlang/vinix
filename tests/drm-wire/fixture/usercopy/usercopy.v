@[has_globals]
module usercopy

__global fail_address = u64(0)

pub fn fail_at(address u64) { fail_address = address }

pub fn copy_from_user(output voidptr, input u64, size u64) bool {
	if size != 0 && input == 0 { return false }
	if fail_address != 0 && fail_address >= input && fail_address - input < size { return false }
	unsafe { C.memcpy(output, voidptr(input), size) }
	return true
}

pub fn copy_to_user(output u64, input voidptr, size u64) bool {
	if size != 0 && output == 0 { return false }
	if fail_address != 0 && fail_address >= output && fail_address - output < size { return false }
	unsafe { C.memcpy(voidptr(output), input, size) }
	return true
}
