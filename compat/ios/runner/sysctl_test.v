// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#include <sys/sysctl.h>
}

fn C.sysctl(&i32, u32, voidptr, &usize, voidptr, usize) i32
fn C.sysctlbyname(&char, voidptr, &usize, voidptr, usize) i32

fn sysctl_test_buffer(id i32, key string, capacity usize, expected u64, width usize) {
	buffer := unsafe { &u8(C.__builtin_alloca(32)) }
	C.memset(buffer, 0xaa, 32)
	mut length := capacity
	mut mib := [i32(6), id]!
	darwin_set_errno(177)
	result := if key == '' {
		darwin_sysctl(unsafe { &mib[0] }, 2, unsafe { &buffer[8] }, unsafe { &length }, unsafe { nil }, 0)
	} else {
		darwin_sysctlbyname(unsafe { &char(key.str) }, unsafe { &buffer[8] }, unsafe { &length }, unsafe { nil }, 0)
	}
	result_errno := unsafe { *C.ios_errno_address() }
	$if macos {
		native := unsafe { &u8(C.__builtin_alloca(32)) }
		C.memset(native, 0xaa, 32)
		mut native_length := capacity
		darwin_set_errno(177)
		native_result := if key == '' {
			C.sysctl(unsafe { &mib[0] }, 2, unsafe { &native[8] }, unsafe { &native_length }, unsafe { nil }, 0)
		} else {
			C.sysctlbyname(unsafe { &char(key.str) }, unsafe { &native[8] }, unsafe { &native_length }, unsafe { nil }, 0)
		}
		assert result == native_result && result_errno == unsafe { *C.ios_errno_address() }
		assert length == native_length && C.memcmp(buffer, native, 32) == 0
	}
	if width == 8 && capacity == 4 && expected > 0xffffffff {
		assert result == -1 && result_errno == 34 && length == 4
		for index in 0 .. 32 {
			assert unsafe { buffer[index] } == 0xaa
		}
	} else {
		actual_width := if width == 8 && capacity == 4 { usize(4) } else { width }
		if capacity < actual_width {
			assert result == -1 && result_errno == 12 && length == 0
			for index in 0 .. 32 {
				assert unsafe { buffer[index] } == 0xaa
			}
		} else {
			assert result == 0 && result_errno == 177 && length == actual_width
			assert C.memcmp(unsafe { &buffer[8] }, unsafe { &expected }, actual_width) == 0
			for index in 0 .. 8 {
				assert unsafe { buffer[index] } == 0xaa
			}
			for index in 8 + actual_width .. 32 {
				assert unsafe { buffer[index] } == 0xaa
			}
		}
	}
}

fn sysctl_test_null_outputs(id i32, width usize) {
	mut mib := [i32(6), id]!
	mut length := usize(177)
	darwin_set_errno(177)
	assert darwin_sysctl(unsafe { &mib[0] }, 2, unsafe { nil }, unsafe { &length }, unsafe { nil }, 0) == 0
	assert length == width && unsafe { *C.ios_errno_address() } == 177
	assert darwin_sysctl(unsafe { &mib[0] }, 2, unsafe { nil }, unsafe { nil }, unsafe { nil }, 0) == 0
	assert unsafe { *C.ios_errno_address() } == 177
	mut value := u64(0xaaaaaaaaaaaaaaaa)
	assert darwin_sysctl(unsafe { &mib[0] }, 2, unsafe { &value }, unsafe { nil }, unsafe { nil }, 0) == -1
	assert unsafe { *C.ios_errno_address() } == 12 && value == 0xaaaaaaaaaaaaaaaa
	$if macos {
		darwin_set_errno(177)
		assert C.sysctl(unsafe { &mib[0] }, 2, unsafe { &value }, unsafe { nil }, unsafe { nil }, 0) == -1
		assert unsafe { *C.ios_errno_address() } == 12 && value == 0xaaaaaaaaaaaaaaaa
	}
}

fn sysctl_test_invalid() {
	mut mib := [13]i32{}
	mib[0] = 6
	mib[1] = 25
	for count in [u32(0), 1, 3, 12, 13] {
		mut length := usize(8)
		mut value := u64(0xaaaaaaaaaaaaaaaa)
		darwin_set_errno(177)
		result := darwin_sysctl(unsafe { &mib[0] }, count, unsafe { &value }, unsafe { &length }, unsafe { nil }, 0)
		result_errno := unsafe { *C.ios_errno_address() }
		assert result == -1 && result_errno == if count == 3 || count == 12 { 21 } else { 22 }
		assert length == 8 && value == 0xaaaaaaaaaaaaaaaa
		$if macos {
			darwin_set_errno(177)
			assert C.sysctl(unsafe { &mib[0] }, count, unsafe { &value }, unsafe { &length }, unsafe { nil }, 0) == result
			assert unsafe { *C.ios_errno_address() } == result_errno
			assert length == 8 && value == 0xaaaaaaaaaaaaaaaa
		}
	}
	for id in [i32(11), 999] {
		mib[1] = id
		mut length := usize(8)
		mut value := u64(0xaaaaaaaaaaaaaaaa)
		assert darwin_sysctl(unsafe { &mib[0] }, 2, unsafe { &value }, unsafe { &length }, unsafe { nil }, 0) == -1
		assert unsafe { *C.ios_errno_address() } == 2 && length == 8 && value == 0xaaaaaaaaaaaaaaaa
	}
	mut length := usize(8)
	mut value := u64(0xaaaaaaaaaaaaaaaa)
	assert darwin_sysctlbyname(c'hw.no_such_vinix_query', unsafe { &value }, unsafe { &length }, unsafe { nil }, 0) == -1
	assert unsafe { *C.ios_errno_address() } == 2 && length == 8 && value == 0xaaaaaaaaaaaaaaaa
	assert darwin_sysctl(unsafe { nil }, 2, unsafe { &value }, unsafe { &length }, unsafe { nil }, 0) == -1
	assert unsafe { *C.ios_errno_address() } == 14 && length == 8 && value == 0xaaaaaaaaaaaaaaaa
	assert darwin_sysctlbyname(unsafe { nil }, unsafe { &value }, unsafe { &length }, unsafe { nil }, 0) == -1
	assert unsafe { *C.ios_errno_address() } == 22 && length == 8 && value == 0xaaaaaaaaaaaaaaaa
	// A supported read-only leaf rejects writes before touching either output.
	mib[1] = 25
	mut new_value := i32(177)
	assert darwin_sysctl(unsafe { &mib[0] }, 2, unsafe { &value }, unsafe { &length }, unsafe { &new_value }, 4) == -1
	assert unsafe { *C.ios_errno_address() } == 1 && length == 8 && value == 0xaaaaaaaaaaaaaaaa
	$if macos {
		assert C.sysctl(unsafe { &mib[0] }, 2, unsafe { &value }, unsafe { &length }, unsafe { &new_value }, 4) == -1
		assert unsafe { *C.ios_errno_address() } == 1 && length == 8 && value == 0xaaaaaaaaaaaaaaaa
	}
	darwin_set_errno(177)
	assert darwin_sysctl(unsafe { &mib[0] }, 2, unsafe { &value }, unsafe { &length }, unsafe { &new_value }, 0) == 0
	assert unsafe { *C.ios_errno_address() } == 177 && length == 4 && new_value == 177
	length = 8
	assert darwin_sysctl(unsafe { &mib[0] }, 2, unsafe { &value }, unsafe { &length }, unsafe { nil }, 177) == 0
	assert unsafe { *C.ios_errno_address() } == 177 && length == 4
	// Non-hardware trees remain unavailable; no synthetic process data.
	mib[0] = 1
	mib[1] = 14
	length = 8
	assert darwin_sysctl(unsafe { &mib[0] }, 4, unsafe { &value }, unsafe { &length }, unsafe { nil }, 0) == -1
	assert unsafe { *C.ios_errno_address() } == 2 && length == 8
}

fn sysctl_test_worker() {
	mut mib := [i32(6), 25]!
	for _ in 0 .. 1000 {
		mut value := i32(0)
		mut length := usize(4)
		darwin_set_errno(177)
		assert darwin_sysctl(unsafe { &mib[0] }, 2, unsafe { &value }, unsafe { &length }, unsafe { nil }, 0) == 0
		assert value == C.sysconf(C._SC_NPROCESSORS_ONLN) && length == 4
		assert unsafe { *C.ios_errno_address() } == 177
		mut memory := u64(0)
		length = 8
		assert darwin_sysctlbyname(c'hw.memsize', unsafe { &memory }, unsafe { &length }, unsafe { nil }, 0) == 0
		assert memory == u64(C.sysconf(C._SC_PHYS_PAGES)) * u64(C.getpagesize()) && length == 8
		assert unsafe { *C.ios_errno_address() } == 177
	}
}

fn test_darwin_hardware_sysctl() {
	configured := u64(C.sysconf(C._SC_NPROCESSORS_CONF))
	active := u64(C.sysconf(C._SC_NPROCESSORS_ONLN))
	page_size := u64(C.getpagesize())
	memory := u64(C.sysconf(C._SC_PHYS_PAGES)) * page_size
	assert configured > 0 && active > 0 && memory > 0
	for id, expected in {
		i32(3):  configured
		i32(4):  u64(1234)
		i32(7):  page_size
		i32(24): memory
		i32(25): active
	} {
		width := if id == 24 { usize(8) } else { usize(4) }
		for capacity in [usize(0), 1, 2, 3, 4, 5, 7, 8, 16] {
			sysctl_test_buffer(id, '', capacity, expected, width)
		}
		sysctl_test_null_outputs(id, width)
	}
	for key, expected in {
		'hw.ncpu':                   configured
		'hw.activecpu':              active
		'hw.pagesize':               page_size
		'hw.memsize':                memory
		'hw.byteorder':              u64(1234)
		'hw.optional.arm64':         u64(1)
		'hw.optional.neon':          u64(1)
		'hw.optional.floatingpoint': u64(1)
	} {
		width := if key == 'hw.pagesize' || key == 'hw.memsize' { usize(8) } else { usize(4) }
		for capacity in [usize(0), 1, 2, 3, 4, 5, 7, 8, 16] {
			sysctl_test_buffer(0, key, capacity, expected, width)
		}
	}
	sysctl_test_invalid()
	for _ in 0 .. 2 {
		system_data_start()!
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn sysctl_test_worker() }
		workers.wait()
		system_data_stop()
	}
	assert libsystem_symbol('/usr/lib/libSystem.B.dylib', '_sysctl')! != 0
	println('IOS-SYSCTL: native CPU/page/memory values, numeric/name ABI, guarded widths, errno, writes and two teardowns')
}
