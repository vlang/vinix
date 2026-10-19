// SPDX-License-Identifier: GPL-2.0-or-later
module main

type RlimitTestCall = fn (i32, voidptr) i32

fn rlimit_test_resource(resource i32) i32 {
	$if macos { return resource & 0xfff }
	return match resource & 0xfff { 5 { i32(C.RLIMIT_AS) } 6 { i32(C.RLIMIT_MEMLOCK) } 7 { i32(C.RLIMIT_NPROC) } 8 { i32(C.RLIMIT_NOFILE) } else { resource & 0xfff } }
}

fn rlimit_test_query(resource i32) [2]u64 {
	mut words := [2]u64{}
	assert C.getrlimit(rlimit_test_resource(resource), unsafe { voidptr(&words[0]) }) == 0
	return words
}

fn rlimit_test_guest(native [2]u64) [2]u64 {
	mut words := native
	for index in 0 .. 2 { if words[index] == u64(C.RLIM_INFINITY) { words[index] = darwin_rlim_infinity } }
	return words
}

fn rlimit_test_call(call RlimitTestCall, resource i32, words [2]u64, expected i32, failure i32) {
	for shift in [0, 1, 3]! {
		mut bytes := [48]u8{}; C.memset(unsafe { voidptr(&bytes[0]) }, 0xa5, 48)
		unsafe { C.memcpy(voidptr(&bytes[8 + shift]), voidptr(&words[0]), 16) }
		before := bytes
		darwin_set_errno(83); result := call(resource, unsafe { voidptr(&bytes[8 + shift]) }); saved := unsafe { *C.ios_errno_address() }
		assert result == expected && saved == failure, 'resource=${resource} result=${result} errno=${saved}'
		assert bytes == before
	}
}

fn rlimit_test_errors(call RlimitTestCall) {
	before := rlimit_test_query(4)
	for resource in [i32(-2147483647), -1, 9, 10, 0x2004, 2147483647]! {
		rlimit_test_call(call, resource, [u64(0), 0]!, -1, 22)
		darwin_set_errno(83); assert call(resource, unsafe { nil }) == -1 && unsafe { *C.ios_errno_address() } == 14
	}
	for resource in [i32(4), 0x1004, 8, 0x1008]! {
		rlimit_test_call(call, resource, [u64(1), 0]!, -1, 22)
		assert call(resource, unsafe { nil }) == -1 && unsafe { *C.ios_errno_address() } == 14
	}
	$if linux { rlimit_test_call(call, 4, [~u64(0), ~u64(0)]!, -1, 45) }
	assert rlimit_test_query(4) == before
}

fn rlimit_test_child(call RlimitTestCall, resource i32) {
	original := rlimit_test_query(resource)
	mut words := rlimit_test_guest(original)
	$if macos { if resource == 7 { words[1] = words[0] } }
	rlimit_test_call(call, resource, words, 0, 83)
	actual := rlimit_test_query(resource)
	assert actual[0] == original[0]
	$if macos { if resource == 7 { assert actual[1] <= original[1] } else { assert actual[1] == original[1] } }
	$if linux { assert actual[1] == original[1] }
	assert rlimit_native_resource(i32(resource)) == rlimit_test_resource(resource)
	assert rlimit_native_resource(i32(resource | 0x1000)) == if os_is_macos() { resource | 0x1000 } else { rlimit_test_resource(resource) }
	if resource == 4 {
		// The native kernel decides whether this caller can raise a hard limit.
		rlimit_test_call(call, 4, [u64(0), 0]!, 0, 83)
		mut wanted := [u64(0), 1]!
		darwin_set_errno(83); expected := C.setrlimit(i32(C.RLIMIT_CORE), unsafe { voidptr(&wanted[0]) }); native_failure := unsafe { *C.ios_errno_address() }
		mut zero := [2]u64{}; assert C.setrlimit(i32(C.RLIMIT_CORE), unsafe { voidptr(&zero[0]) }) == 0
		// One attempt: a successful hard-limit raise changes subsequent checks.
		darwin_set_errno(83); result := call(4, unsafe { voidptr(&wanted[0]) }); saved := unsafe { *C.ios_errno_address() }
		assert result == expected && saved == if expected == 0 { i32(83) } else { i32(darwin_native_error(native_failure)) }
	}
	if resource == 8 {
		// The actual Fortnite initializer requests NOFILE={10240,infinity}.
		// Linux may reject that hard limit; preserve its real native failure.
		mut native_request := [u64(10240), u64(C.RLIM_INFINITY)]!
		darwin_set_errno(83); expected := C.setrlimit(i32(C.RLIMIT_NOFILE), unsafe { voidptr(&native_request[0]) }); native_failure := unsafe { *C.ios_errno_address() }
		rlimit_test_call(call, 8, [u64(10240), darwin_rlim_infinity]!, expected, if expected == 0 { i32(83) } else { i32(darwin_native_error(native_failure)) })
		mut reduced := words; reduced[0] = 16; assert reduced[1] >= 16
		rlimit_test_call(call, 8 | 0x1000, reduced, 0, 83)
		assert rlimit_test_query(8)[0] == 16
		mut descriptors := [64]i32{}; mut count := 0
		for count < descriptors.len {
			fd := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC, 0)
			if fd < 0 { assert unsafe { *C.ios_errno_address() } == C.EMFILE; break }
			descriptors[count] = fd; count++
		}
		assert count > 0 && count <= 16
		for index in 0 .. count { assert C.close(descriptors[index]) == 0 }
	}
}

fn os_is_macos() bool { $if macos { return true }; return false }

fn rlimit_test_isolated(call RlimitTestCall, resource i32) {
	before := rlimit_test_query(resource)
	image_atfork_start() or { panic(err) }; child := C.ios_fork(); assert child >= 0
	if child == 0 { rlimit_test_child(call, resource); C._exit(0) }
	mut status := i32(-1); assert C.ios_waitpid(child, unsafe { &status }, 0) == child && status == 0
	image_atfork_stop(); assert rlimit_test_query(resource) == before
}

fn rlimit_test_worker(context voidptr) voidptr {
	call := unsafe { RlimitTestCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_setrlimit') or { panic(err) })) }
	words := rlimit_test_guest(rlimit_test_query(4))
	for _ in 0 .. 32 {
		darwin_set_errno(i32(80 + u64(context))); result := call(4, unsafe { voidptr(&words[0]) }); saved := unsafe { *C.ios_errno_address() }
		assert result == 0 && saved == i32(80 + u64(context))
	}
	return unsafe { nil }
}

fn rlimit_test_inherit(call RlimitTestCall) {
	original := rlimit_test_query(4); mut words := rlimit_test_guest(original)
	words[0] = if words[1] >= 128 { u64(128) } else { u64(0) }
	rlimit_test_call(call, 4, words, 0, 83)
	image_atfork_start() or { panic(err) }; child := C.ios_fork(); assert child >= 0
	if child == 0 { assert rlimit_test_query(4)[0] == words[0]; C._exit(0) }
	mut status := i32(-1); assert C.ios_waitpid(child, unsafe { &status }, 0) == child && status == 0
	image_atfork_stop()
	assert C.setrlimit(i32(C.RLIMIT_CORE), unsafe { voidptr(&original[0]) }) == 0
	assert rlimit_test_query(4) == original
}

fn test_setrlimit() {
	call := unsafe { RlimitTestCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_setrlimit')!)) }
	for _ in 0 .. 2 {
		system_data_start()!
		$if macos { native := unsafe { RlimitTestCall(voidptr(C.setrlimit)) }; rlimit_test_errors(native); for resource in 0 .. 9 { rlimit_test_isolated(native, i32(resource)) }; rlimit_test_inherit(native); println('NATIVE-SETRLIMIT: nine resources, guarded inputs, error priority, hard-limit permissions, descriptor enforcement and fork inheritance passed') }
		rlimit_test_errors(call)
		for resource in 0 .. 9 { rlimit_test_isolated(call, i32(resource)) }
		rlimit_test_inherit(call)
		mut handles := [8]u64{}
		for index in 0 .. 8 { assert C.pthread_create(unsafe { voidptr(&handles[index]) }, unsafe { nil }, unsafe { voidptr(rlimit_test_worker) }, voidptr(u64(index + 1))) == 0 }
		for handle in handles { assert C.pthread_join(voidptr(handle), unsafe { nil }) == 0 }
		mut rejected := false; runtime_symbol('/usr/lib/libobjc.A.dylib', '_setrlimit') or { rejected = true }; assert rejected
		system_data_stop()
	}
	println('IOS-SETRLIMIT: nine resources, infinity translation, guarded/unaligned inputs, native errors/permissions, descriptor enforcement, fork inheritance, eight callers and two images passed')
}
