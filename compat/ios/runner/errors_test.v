// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if ios_error_asan ? {
	#include <sanitizer/asan_interface.h>
}

fn C.strerror_r(i32, &char, usize) i32
fn C.__asan_address_is_poisoned(voidptr) i32

__global error_test_ready = i64(0)
__global error_test_release = u64(0)

fn error_test_case(number i32, capacity usize) {
	buffer := unsafe { &u8(C.__builtin_alloca(144)) }
	C.memset(buffer, 0xaa, 144)
	darwin_set_errno(177)
	result := darwin_strerror_r(number, unsafe { &char(&buffer[8]) }, capacity)
	assert unsafe { *C.ios_errno_address() } == 177
	for i in 0 .. 8 {
		assert unsafe { buffer[i] == 0xaa && buffer[136 + i] == 0xaa }
	}
	if capacity != 0 {
		for i in capacity .. 128 {
			assert unsafe { buffer[8 + i] == 0xaa }
		}
	}
	$if macos {
		native := unsafe { &u8(C.__builtin_alloca(144)) }
		C.memset(native, 0xaa, 144)
		darwin_set_errno(177)
		expected := C.strerror_r(number, unsafe { &char(&native[8]) }, capacity)
		assert unsafe { *C.ios_errno_address() } == 177
		assert result == expected && C.memcmp(buffer, native, 144) == 0
		darwin_set_errno(177)
		expected_message := C.strerror(number)
		expected_errno := unsafe { *C.ios_errno_address() }
		darwin_set_errno(177)
		message := darwin_strerror(number)
		assert message != unsafe { nil }
		assert darwin_strcmp(message, expected_message) == 0
		assert unsafe { *C.ios_errno_address() } == expected_errno
	}
}

fn error_test_worker(index i32) u64 {
	expected := 'Unknown error: ${-1000 - index}'
	pointer := darwin_strerror(-1000 - index)
	assert pointer != unsafe { nil }
	C.ios_ref_change(unsafe { &error_test_ready }, 1)
	for C.ios_load_pointer(unsafe { &error_test_release }) == 0 { C.sched_yield() }
	// Other threads used their buffers while this thread kept its result.
	assert darwin_strcmp(pointer, unsafe { &char(expected.str) }) == 0
	for _ in 0 .. 1000 {
		darwin_set_errno(177)
		assert darwin_strerror(35) == pointer
		assert unsafe { *C.ios_errno_address() } == 177
		assert darwin_strcmp(pointer, c'Resource temporarily unavailable') == 0
		assert darwin_strerror(-1000 - index) == pointer
		assert unsafe { *C.ios_errno_address() } == 22
		assert darwin_strcmp(pointer, unsafe { &char(expected.str) }) == 0
	}
	return u64(pointer)
}

fn error_test_threads() {
	for _ in 0 .. 4 {
		error_test_ready = 0
		C.ios_store_pointer(unsafe { &error_test_release }, 0)
		mut workers := []thread u64{}
		for index in 0 .. 8 { workers << spawn error_test_worker(i32(index)) }
		for C.ios_ref_change(unsafe { &error_test_ready }, 0) != 8 { C.sched_yield() }
		own := darwin_strerror(0)
		assert darwin_strcmp(own, c'Undefined error: 0') == 0
		C.ios_store_pointer(unsafe { &error_test_release }, 1)
		pointers := workers.wait()
		assert darwin_strcmp(own, c'Undefined error: 0') == 0
		for index, pointer in pointers {
			assert pointer != u64(own)
			for earlier in 0 .. index {
				assert pointers[earlier] != pointer
			}
			$if ios_error_asan ? {
				// Native pthread cleanup must have called the resident free().
				assert C.__asan_address_is_poisoned(unsafe { voidptr(pointer) }) != 0
			}
		}
	}
}

fn test_darwin_error_messages() {
	for number in 0 .. 109 {
		for capacity in [usize(0), 1, 2, 7, 20, 64, 128] { error_test_case(i32(number), capacity) }
	}
	for number in [i32(-1), -1000, 2147483647, -2147483648] {
		for capacity in [usize(0), 1, 2, 7, 20, 64, 128] { error_test_case(number, capacity) }
	}
	for number, expected in {
		i32(0):           'Undefined error: 0'
		i32(11):          'Resource deadlock avoided'
		i32(35):          'Resource temporarily unavailable'
		i32(45):          'Operation not supported'
		i32(57):          'Socket is not connected'
		i32(-2147483648): 'Unknown error: -2147483648'
		i32(2147483647):  'Unknown error: 2147483647'
	} {
		darwin_set_errno(177)
		assert darwin_strcmp(darwin_strerror(number), unsafe { &char(expected.str) }) == 0
		assert unsafe { *C.ios_errno_address() } == if number < 0 || number > 107 {
			22
		} else {
			177
		}
		buffer := unsafe { &char(C.__builtin_alloca(128)) }
		darwin_set_errno(177)
		assert darwin_strerror_r(number, buffer, 128) == if number < 0 || number > 107 {
			22
		} else {
			0
		}
		assert darwin_strcmp(buffer, unsafe { &char(expected.str) }) == 0 && unsafe { *C.ios_errno_address() } == 177
	}
	darwin_set_errno(177)
	assert darwin_strerror_r(35, unsafe { nil }, 0) == 34
	assert darwin_strerror_r(-1, unsafe { nil }, 0) == 22
	assert darwin_strerror_r(35, unsafe { nil }, 1) == 22
	assert unsafe { *C.ios_errno_address() } == 177
	own := darwin_strerror(0)
	for _ in 0 .. 2 {
		system_data_start()!
		error_test_threads()
		system_data_stop()
		assert darwin_strerror(0) == own
	}
	assert (errors_symbol('_strerror') or { u64(0) }) != 0
	assert (errors_symbol('_strerror_r') or { u64(0) }) != 0
	println('IOS-ERRORS: Darwin messages, truncation/guards, errno, INT_MIN, thread buffers and two teardowns')
}
