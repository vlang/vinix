@[has_globals]
module usercopy

__global start = u64(0)
__global input_size = u64(0)
__global fail = false
__global pub reads = 0
__global pub writes = 0
__global output_starts [4]u64
__global output_lengths [4]u64
__global output_count = 0
__global output_fault = u64(0)
__global after_output fn (u64, u64) = unsafe { nil }

pub fn allow(address u64, size u64) {
	start = address; input_size = size; fail = false; reads = 0; writes = 0
	output_count = 0; output_fault = 0; after_output = unsafe { nil }
}
pub fn inject_fault() { fail = true }

pub fn allow_output(address u64, size u64) {
	assert output_count < output_starts.len
	output_starts[output_count] = address; output_lengths[output_count] = size
	output_count++
}

pub fn fail_output_at(address u64) { output_fault = address }
pub fn after_next_output(callback fn (u64, u64)) { after_output = callback }

pub fn copy_to_user(output u64, input voidptr, size u64) bool {
	writes++
	mut allowed := false
	for index in 0 .. output_count {
		base := output_starts[index]
		span := output_lengths[index]
		if output != 0 && output >= base && output - base <= span && size <= span - (output - base) {
			allowed = true; break
		}
	}
	if !allowed { return false }
	mut copied := size
	if output_fault != 0 && output_fault >= output && output_fault - output < size {
		copied = output_fault - output
	}
	if copied != 0 { unsafe { C.memcpy(voidptr(output), input, copied) } }
	if after_output != unsafe { nil } {
		callback := after_output; after_output = unsafe { nil }; callback(output, copied)
	}
	return copied == size
}

pub fn copy_from_user(output voidptr, input u64, size u64) bool {
	reads++
	if fail || input == 0 || input < start || input - start > input_size
		|| size > input_size - (input - start) { return false }
	unsafe { C.memcpy(output, voidptr(input), size) }
	return true
}
