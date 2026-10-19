// SPDX-License-Identifier: GPL-2.0-or-later
module main

type UnameCall = fn (voidptr) i32

struct UnameLayout {
	sysname [256]char
	nodename [256]char
	release [256]char
	version [256]char
	machine [256]char
}

fn uname_expected(output voidptr, native &C.utsname) usize {
	fields := [unsafe { &native.sysname[0] }, unsafe { &native.nodename[0] },
		unsafe { &native.release[0] }, unsafe { &native.version[0] },
		unsafe { &native.machine[0] }]!
	mut end := usize(0)
	for index, field in fields {
		length := C.strlen(field) + 1
		assert length > 1 && length <= 256
		unsafe { C.memcpy(voidptr(usize(output) + usize(index) * 256), field, length) }
		end = usize(index) * 256 + length
	}
	return end
}

fn uname_records(client UnameCall, marker i32) {
	mut native := C.utsname{}
	assert C.uname(unsafe { &native }) == 0
	for alignment in [0, 1, 7]! {
		mut actual := [1328]u8{init: 0xa5}
		mut expected := [1328]u8{init: 0xa5}
		uname_expected(unsafe { &expected[16 + alignment] }, unsafe { &native })
		darwin_set_errno(marker)
		assert client(unsafe { &actual[16 + alignment] }) == 0
		assert unsafe { *C.ios_errno_address() } == marker
		assert C.memcmp(unsafe { &actual[0] }, unsafe { &expected[0] }, sizeof(actual)) == 0
	}
	// Fortnite passes sp+8 in a 1296-byte frame, then reads machine at +1024.
	mut frame := [1296]u8{init: 0xa5}
	darwin_set_errno(marker)
	assert client(unsafe { &frame[8] }) == 0 && unsafe { *C.ios_errno_address() } == marker
	assert C.strcmp(unsafe { &char(&frame[1032]) }, unsafe { &native.machine[0] }) == 0
	for index in 0 .. 8 { assert frame[index] == 0xa5 && frame[1288 + index] == 0xa5 }
}

fn uname_guards(client UnameCall) {
	page := usize(C.getpagesize())
	mut native := C.utsname{}
	assert C.uname(unsafe { &native }) == 0
	mut record := [1280]u8{init: 0xa5}
	end := uname_expected(unsafe { &record[0] }, unsafe { &native })
	for capacity in [usize(0), 1, 255, 256, 512, 1024, 1025, 1028, 1279, 1280]! {
		actual := C.mmap(unsafe { nil }, page * 2, 3, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		assert actual != voidptr(~usize(0))
		C.memset(actual, 0xa5, page)
		assert C.mprotect(voidptr(usize(actual) + page), page, 0) == 0
		output := voidptr(usize(actual) + page - capacity)
		darwin_set_errno(177)
		result := client(output)
		saved := unsafe { *C.ios_errno_address() }
		assert result == if capacity >= end { i32(0) } else { i32(-1) }
		assert saved == if result == 0 { i32(177) } else { i32(14) }
		assert C.memcmp(output, unsafe { &record[0] }, capacity) == 0
		for index in usize(0) .. page - capacity { assert unsafe { (&u8(actual))[index] } == 0xa5 }
		$if macos {
			reference := C.mmap(unsafe { nil }, page * 2, 3, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
			assert reference != voidptr(~usize(0))
			C.memset(reference, 0xa5, page)
			assert C.mprotect(voidptr(usize(reference) + page), page, 0) == 0
			darwin_set_errno(177)
			assert C.uname(&C.utsname(usize(reference) + page - capacity)) == result
			assert unsafe { *C.ios_errno_address() } == saved && C.memcmp(actual, reference, page) == 0
			assert C.munmap(reference, page * 2) == 0
		}
		assert C.munmap(actual, page * 2) == 0
	}
	readonly := C.mmap(unsafe { nil }, page, 3, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert readonly != voidptr(~usize(0))
	C.memset(readonly, 0xa5, page)
	assert C.mprotect(readonly, page, 1) == 0
	darwin_set_errno(177)
	assert client(readonly) == -1 && unsafe { *C.ios_errno_address() } == 14
	for index in usize(0) .. page { assert unsafe { (&u8(readonly))[index] } == 0xa5 }
	assert C.munmap(readonly, page) == 0
	for output in [voidptr(0), voidptr(1), voidptr(~usize(0))]! {
		darwin_set_errno(177)
		assert client(output) == -1 && unsafe { *C.ios_errno_address() } == 14
	}
}

fn uname_worker(context voidptr) voidptr {
	client := unsafe { UnameCall(context) }
	for _ in 0 .. 40 { uname_records(client, 83) }
	return unsafe { nil }
}

fn test_uname() {
	assert sizeof(UnameLayout) == 1280
	layout := UnameLayout{}
	assert usize(unsafe { &layout.machine[0] }) - usize(unsafe { &layout.sysname[0] }) == 1024
	client := unsafe { UnameCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_uname')!)) }
	uname_records(client, 177)
	uname_guards(client)
	for _ in 0 .. 2 {
		system_data_start()!
		mut handles := [8]u64{}
		for index in 0 .. 8 {
			assert darwin_pthread_create(unsafe { &handles[index] }, unsafe { nil },
				unsafe { voidptr(uname_worker) }, unsafe { voidptr(client) }) == 0
		}
		for handle in handles { assert darwin_pthread_join(handle, unsafe { nil }) == 0 }
		image_atfork_start()!
		child := C.ios_fork()
		assert child >= 0
		if child == 0 { uname_records(client, 99); C._exit(0) }
		mut status := i32(-1)
		assert C.ios_waitpid(child, unsafe { &status }, 0) == child && status == 0
		image_atfork_stop()
		system_data_stop()
	}
	mut rejected := false
	runtime_symbol('/usr/lib/libobjc.A.dylib', '_uname') or { rejected = true }
	assert rejected
	println('IOS-UNAME: actual native identity in five 256-byte Darwin fields, untouched tails, aligned/unaligned Fortnite frame, guarded partial copyout and EFAULT, errno, eight concurrent workers, fork and two runtime lifetimes')
}
