// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module usercopy

__global region_start = u64(0)
__global region_size = u64(0)
__global fail_after = int(-1)
__global write_calls = 0
__global last_bytes = u64(0)
__global last_address = u64(0)
__global read_fault = u64(0)
__global read_calls = 0
__global next_read fn () = unsafe { nil }

pub fn fail_read_at(address u64) { read_fault = address; read_calls = 0 }
pub fn before_next_read(callback fn ()) { next_read = callback }
pub fn reads() int { return read_calls }
pub fn copy_from_user(target voidptr, source u64, size u64) bool {
	read_calls++
	if next_read != unsafe { nil } {
		callback := next_read
		next_read = unsafe { nil }
		callback()
	}
	if size != 0 && (source == 0 || size - 1 > ~source) { return false }
	if read_fault != 0 && read_fault >= source && read_fault - source < size { return false }
	unsafe { C.memcpy(target, voidptr(source), size) }
	return true
}

pub fn configure(start u64, size u64, fault_after int) {
	region_start = start; region_size = size; fail_after = fault_after
	write_calls = 0; last_bytes = 0; last_address = 0
}

pub fn calls() int { return write_calls }
pub fn bytes() u64 { return last_bytes }
pub fn address() u64 { return last_address }

pub fn copy_to_user(destination u64, source voidptr, length u64) bool {
	write_calls++; last_bytes = length; last_address = destination
	if length == 0 { return true }
	if destination < region_start || destination - region_start >= region_size { return false }
	remaining := region_size - (destination - region_start)
	mut copied := if length < remaining { length } else { remaining }
	if fail_after >= 0 && u64(fail_after) < copied { copied = u64(fail_after) }
	if copied != 0 { unsafe { C.memcpy(voidptr(destination), source, copied) } }
	return copied == length
}
