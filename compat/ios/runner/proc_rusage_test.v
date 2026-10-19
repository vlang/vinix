// SPDX-License-Identifier: GPL-2.0-or-later
module main

type UsageTestCall = fn (i32, i32, voidptr) i32

fn usage_test_word(output voidptr, index int) u64 {
	mut value := u64(0)
	unsafe { C.memcpy(voidptr(&value), voidptr(u64(output) + u64(index) * 8), 8) }
	return value
}

fn test_proc_rusage_parsers() {
	mut value := u64(83)
	text := '10 3 0 0 0 0 0\n'
	assert proc_rusage_resident(text.str, text.len, 4096, unsafe { &value }) && value == 12288
	for invalid in ['', '1 2', '1 -1 0 0 0 0 0', '1 x 0 0 0 0 0', '1 2 0 0 0 0 0 extra', '1 18446744073709551615 0 0 0 0 0']! {
		value = 83; assert !proc_rusage_resident(invalid.str, invalid.len, 4096, unsafe { &value }) && value == 83
	}
	stat := '12 (name ) with ( spaces)) S 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 123 456 789\n'
	assert proc_rusage_start(stat.str, stat.len, 100, unsafe { &value }) && value == 1230000000
	assert (proc_rusage_stat_field(stat.str, stat.len, 24) or { panic('RSS field') }) == 789
	for invalid in ['', '12 name S 1', '12 (name) S 1', stat.replace('123 456', '-1 456'), stat.replace('123 456', '18446744073709551615 456')]! {
		value = 83; assert !proc_rusage_start(invalid.str, invalid.len, 100, unsafe { &value }) && value == 83
	}
	mut values := [u64(83), 83, 83]!
	status := 'Name:\tquery\nVmLck:\t4 kB\nVmSwap:\t7 kB\n'
	assert proc_rusage_fields(status.str, status.len, true, unsafe { &values[0] }) && values == [u64(4096), 7168, 0]!
	io := 'wchar: 17\nread_bytes: 29\nwrite_bytes: 31\n'
	assert proc_rusage_fields(io.str, io.len, false, unsafe { &values[0] }) && values == [u64(29), 31, 17]!
	for invalid in ['VmLck: nope kB', 'VmLck: 1 bytes', 'VmLck: -1 kB', 'VmLck: 1 kB\nVmLck: 2 kB', 'VmSwap: 18446744073709551615 kB']! {
		values = [u64(83), 83, 83]!; assert !proc_rusage_fields(invalid.str, invalid.len, true, unsafe { &values[0] }) && values == [u64(83), 83, 83]!
	}
	assert (proc_rusage_time(C.timeval{tv_sec: 987, tv_usec: 123456}) or { panic('time conversion') }) == 987123456000
	for input in [C.timeval{tv_sec: ~u64(0)}, C.timeval{tv_usec: ~u64(0)}, C.timeval{tv_usec: 1000000}, C.timeval{tv_sec: 0x7fffffffffffffff}]! {
		if _ := proc_rusage_time(input) { assert false }
	}
	assert (proc_rusage_scale(37244, 125, 3) or { panic('scale') }) == 1551833
	for input in [[~u64(0), u64(2), 1]!, [u64(1), 1, 0]!, [u64(1), 0, 1]!]! { if _ := proc_rusage_scale(input[0], input[1], input[2]) { assert false } }
}

fn usage_test_profile(call UsageTestCall) {
	for flavor in 0 .. 7 {
		for shift in [0, 1, 3]! {
			mut bytes := [512]u8{}; C.memset(unsafe { voidptr(&bytes[0]) }, 0xa5, 512)
			offset := 8 + shift; pointer := unsafe { voidptr(&bytes[offset]) }
			darwin_set_errno(83)
			assert call(C.getpid(), i32(flavor), pointer) == 0 && unsafe { *C.ios_errno_address() } == 83
			for index in 0 .. offset { assert bytes[index] == 0xa5 }
			for index in offset + int(proc_rusage_sizes[flavor]) .. 512 { assert bytes[index] == 0xa5 }
			assert usage_test_word(pointer, 8) > 0 && usage_test_word(pointer, 9) > 0
			$if linux {
				assert usage_test_word(pointer, 9) >= usage_test_word(pointer, 8)
				assert usage_test_word(pointer, 0) == 0 && usage_test_word(pointer, 1) == 0
				assert usage_test_word(pointer, 10) <= darwin_mach_absolute_time()
				if flavor >= 4 { assert usage_test_word(pointer, 30) >= usage_test_word(pointer, 9) }
			}
		}
	}
	for sample in [[i32(-1), -1, 3]!, [i32(0), -1, 1]!, [i32(2147483647), -1, 3]!, [C.getpid(), -1, 22]!, [C.getpid(), 7, 22]!]! {
		mut bytes := [512]u8{}; C.memset(unsafe { voidptr(&bytes[0]) }, 0xa5, 512)
		assert call(sample[0], sample[1], unsafe { voidptr(&bytes[8]) }) == -1 && unsafe { *C.ios_errno_address() } == sample[2]
		for byte in bytes { assert byte == 0xa5 }
		assert call(sample[0], sample[1], unsafe { nil }) == -1 && unsafe { *C.ios_errno_address() } == sample[2]
	}
	assert call(C.getpid(), 5, unsafe { nil }) == -1 && unsafe { *C.ios_errno_address() } == 14
	mut before := C.rusage{}; mut after := C.rusage{}; mut words := [58]u64{}
	assert C.getrusage(0, unsafe { &before }) == 0
	assert call(C.getpid(), 5, unsafe { voidptr(&words[0]) }) == 0
	assert C.getrusage(0, unsafe { &after }) == 0
	lower := proc_rusage_time(before.ru_utime) or { panic('before usage') }
	upper := proc_rusage_time(after.ru_utime) or { panic('after usage') }
	assert words[2] + 1000000 >= lower && words[2] <= upper + 1000000
}

fn usage_test_memory(call UsageTestCall) {
	mut before := [58]u64{}; mut touched := [58]u64{}; mut released := [58]u64{}
	assert call(C.getpid(), 5, unsafe { voidptr(&before[0]) }) == 0
	length := usize(64 * 1024 * 1024)
	mapping := C.mmap(unsafe { nil }, length, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANON, -1, 0)
	assert u64(mapping) != ~u64(0)
	for offset := usize(0); offset < length; offset += usize(C.getpagesize()) { unsafe { *(&u8(u64(mapping) + u64(offset))) = 0x73 } }
	assert call(C.getpid(), 5, unsafe { voidptr(&touched[0]) }) == 0
	assert C.munmap(mapping, length) == 0
	assert call(C.getpid(), 5, unsafe { voidptr(&released[0]) }) == 0
	assert touched[9] >= before[9] + u64(length) / 2 && touched[9] >= released[9] + u64(length) / 2
}

fn usage_test_worker(context voidptr) voidptr {
	call := unsafe { UsageTestCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_proc_pid_rusage') or { panic(err) })) }
	for index in 0 .. 32 {
		mut words := [58]u64{}
		darwin_set_errno(i32(80 + u64(context)))
		result := call(C.getpid(), i32(index % 7), unsafe { voidptr(&words[0]) })
		failure := unsafe { *C.ios_errno_address() }
		assert result == 0, 'resource query errno=${failure} flavor=${index % 7}'
		assert failure == i32(80 + u64(context)), 'errno=${failure} caller=${u64(context)}'
		assert words[9] > 0, 'zero footprint flavor=${index % 7} resident=${words[8]}'
	}
	return unsafe { nil }
}

fn usage_test_fork(call UsageTestCall) {
	mut descriptors := [2]i32{}; assert C.pipe(unsafe { &descriptors[0] }) == 0
	image_atfork_start() or { panic(err) }
	child := C.ios_fork(); assert child >= 0
	if child == 0 {
		C.close(descriptors[1]); usage_test_profile(call)
		mut byte := u8(0); C.read(descriptors[0], unsafe { voidptr(&byte) }, 1); C._exit(0)
	}
	C.close(descriptors[0]); mut bytes := [512]u8{}; C.memset(unsafe { voidptr(&bytes[0]) }, 0xa5, 512)
	darwin_set_errno(83)
	$if macos { assert call(child, 5, unsafe { voidptr(&bytes[8]) }) == 0 && unsafe { *C.ios_errno_address() } == 83 }
	$if linux { assert call(child, 5, unsafe { voidptr(&bytes[8]) }) == -1 && unsafe { *C.ios_errno_address() } == 45; for byte in bytes { assert byte == 0xa5 } }
	C.close(descriptors[1]); mut status := i32(-1)
	assert C.ios_waitpid(child, unsafe { &status }, 0) == child && status == 0
	image_atfork_stop()
}

fn test_proc_rusage() {
	call := unsafe { UsageTestCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_proc_pid_rusage')!)) }
	for _ in 0 .. 2 {
		system_data_start()!
		usage_test_profile(call); usage_test_memory(call)
		first := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC, 0); assert first >= 0; assert C.close(first) == 0
		mut handles := [8]u64{}
		for index in 0 .. 8 { assert C.pthread_create(unsafe { voidptr(&handles[index]) }, unsafe { nil }, unsafe { voidptr(usage_test_worker) }, voidptr(u64(index + 1))) == 0 }
		for handle in handles { assert C.pthread_join(voidptr(handle), unsafe { nil }) == 0 }
		last := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC, 0); assert last == first; assert C.close(last) == 0
		usage_test_fork(call)
		mut rejected := false; runtime_symbol('/usr/lib/libobjc.A.dylib', '_proc_pid_rusage') or { rejected = true }; assert rejected
		system_data_stop()
	}
	println('IOS-PROC-RUSAGE: seven guarded layouts, unaligned outputs, native error order, real CPU/memory changes, bounded parsers, closed descriptors, eight callers, fork and two images passed')
}
