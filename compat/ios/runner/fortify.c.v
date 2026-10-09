// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.ios_fortify_trap()

fn darwin_fortify_fail() {
	stream := C.ios_host_stdio(2)
	C.fputs(c'iOS: fortified operation exceeds destination\n', stream)
	C.fflush(stream)
	C.ios_fortify_trap()
}

fn darwin_memcpy_checked(destination voidptr, source voidptr, size usize, capacity usize) voidptr {
	if size > capacity { darwin_fortify_fail() }
	return C.memcpy(destination, source, size)
}

fn darwin_memmove_checked(destination voidptr, source voidptr, size usize, capacity usize) voidptr {
	if size > capacity { darwin_fortify_fail() }
	return C.memmove(destination, source, size)
}

fn darwin_memset_checked(destination voidptr, value i32, size usize, capacity usize) voidptr {
	if size > capacity { darwin_fortify_fail() }
	return C.memset(destination, value, size)
}

fn darwin_strncpy_checked(destination &char, source &char, size usize, capacity usize) &char {
	// strncpy pads the entire requested count, even when the source is shorter.
	if size > capacity { darwin_fortify_fail() }
	return C.strncpy(destination, source, size)
}

fn darwin_strcat_checked(destination &char, source &char, capacity usize) &char {
	// SIZE_MAX denotes an unknown object size in compiler-generated calls.
	if capacity == ~usize(0) { return C.strcat(destination, source) }
	length := C.strnlen(destination, capacity)
	if length == capacity { darwin_fortify_fail() }
	remaining := capacity - length
	count := C.strnlen(source, remaining)
	if count == remaining { darwin_fortify_fail() }
	unsafe { C.memcpy(voidptr(usize(destination) + length), source, count + 1) }
	return destination
}

fn C.ios_current_stack_bounds(&u64) i32

fn darwin_check_fd_set_overflow(descriptor i32, set voidptr, unlimited i32) i32 {
	// Darwin's FD_SET/FD_CLR/FD_ISSET use this predicate before touching the
	// caller's 32-bit bitmap. Only a complete 128-byte object on the current
	// thread's stack is limited to 1024. Heap/global/unlimited storage remains
	// caller-owned; this helper does not dereference or size its allocation.
	if descriptor < 0 { return 0 }
	if descriptor < 1024 || unlimited != 0 { return 1 }
	start := u64(set)
	if start > ~u64(0) - 128 { return 0 }
	mut bounds := [2]u64{}
	if C.ios_current_stack_bounds(unsafe { &bounds[0] }) != 0 {
		panic('iOS: cannot determine native stack bounds for FD_SET')
	}
	return if start >= bounds[0] && start + 128 <= bounds[1] { 0 } else { 1 }
}
