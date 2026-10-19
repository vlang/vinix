// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

fn C.dup2(i32, i32) i32

type UnfairTestCall = fn (&u32)
type UnfairTestTry = fn (&u32) bool
type UnfairTestFlags = fn (&u32, u32)

struct UnfairTestApi {
	acquire UnfairTestCall
	try_acquire UnfairTestTry
	release UnfairTestCall
	flags UnfairTestFlags
	owner UnfairTestCall
	not_owner UnfairTestCall
}

struct UnfairTestState {
	api UnfairTestApi
mut:
	guards [3]u32 = [u32(0x12345678), 0, 0x76543210]!
	attempted u64
	entered u64
	counter u64
	publication u64
}

fn unfair_test_api() UnfairTestApi {
	return UnfairTestApi{
		acquire: unsafe { UnfairTestCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_os_unfair_lock_lock') or { panic(err) })) }
		try_acquire: unsafe { UnfairTestTry(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_os_unfair_lock_trylock') or { panic(err) })) }
		release: unsafe { UnfairTestCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_os_unfair_lock_unlock') or { panic(err) })) }
		flags: unsafe { UnfairTestFlags(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_os_unfair_lock_lock_with_flags') or { panic(err) })) }
		owner: unsafe { UnfairTestCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_os_unfair_lock_assert_owner') or { panic(err) })) }
		not_owner: unsafe { UnfairTestCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_os_unfair_lock_assert_not_owner') or { panic(err) })) }
	}
}

fn unfair_test_blocked(context voidptr) voidptr {
	mut state := unsafe { &UnfairTestState(context) }
	pointer := unsafe { &state.guards[1] }
	darwin_set_errno(73)
	assert !state.api.try_acquire(pointer)
	state.api.not_owner(pointer)
	C.ios_store_pointer(unsafe { &state.attempted }, 1)
	state.api.acquire(pointer)
	assert unsafe { *C.ios_errno_address() } == 73
	assert state.publication == 0x17395b
	C.ios_store_pointer(unsafe { &state.entered }, 1)
	state.api.release(pointer)
	assert unsafe { *C.ios_errno_address() } == 73
	return unsafe { nil }
}

fn unfair_test_worker(context voidptr) voidptr {
	mut state := unsafe { &UnfairTestState(context) }
	pointer := unsafe { &state.guards[1] }
	for index in 0 .. 1000 {
		darwin_set_errno(81)
		if index % 3 == 0 { state.api.flags(pointer, 0x40000) }
		else if index % 3 == 1 { if !state.api.try_acquire(pointer) { state.api.acquire(pointer) } }
		else { state.api.flags(pointer, 0) }
		state.api.owner(pointer)
		assert state.publication == state.counter ^ u64(0x8db90ac371)
		state.counter++
		state.publication = state.counter ^ u64(0x8db90ac371)
		state.api.release(pointer)
		assert unsafe { *C.ios_errno_address() } == 81
	}
	return unsafe { nil }
}

fn unfair_test_fork(api UnfairTestApi) {
	mut words := [u32(0), 0]!
	api.acquire(unsafe { &words[0] })
	parent_owner := words[0]
	image_atfork_start() or { panic(err) }
	child := C.ios_fork(); assert child >= 0
	if child == 0 {
		assert !api.try_acquire(unsafe { &words[0] })
		api.not_owner(unsafe { &words[0] })
		api.acquire(unsafe { &words[1] })
		assert words[1] != 0 && words[1] != parent_owner
		api.owner(unsafe { &words[1] }); api.release(unsafe { &words[1] })
		C._exit(0)
	}
	mut status := i32(-1)
	assert C.ios_waitpid(child, unsafe { &status }, 0) == child && status == 0
	image_atfork_stop()
	assert words[0] == parent_owner && words[1] == 0
	api.release(unsafe { &words[0] })
}

fn unfair_test_rejections(api UnfairTestApi) {
	for operation in 0 .. 9 {
		mut words := [u32(0), 0]!
		if operation == 4 { api.acquire(unsafe { &words[0] }) }
		mut descriptors := [2]i32{}
		assert C.pipe(unsafe { &descriptors[0] }) == 0
		child := C.ios_fork(); assert child >= 0
		if child == 0 {
			C.close(descriptors[0]); assert C.dup2(descriptors[1], 2) == 2; C.close(descriptors[1])
			pointer := unsafe { &words[0] }
			match operation {
				0 { api.release(pointer) }
				1 { api.owner(pointer) }
				2 { api.acquire(pointer); api.not_owner(pointer) }
				3 { api.acquire(pointer); api.acquire(pointer) }
				4 { api.release(pointer) }
				5 { api.acquire(unsafe { nil }) }
				6 { api.acquire(unsafe { &u32(u64(pointer) + 1) }) }
				7 { api.flags(pointer, 1) }
				else { api.try_acquire(unsafe { nil }) }
			}
			C._exit(0)
		}
		C.close(descriptors[1]); mut bytes := [16384]u8{}; mut length := 0
		for {
			assert length < bytes.len
			count := C.read(descriptors[0], unsafe { &bytes[length] }, usize(bytes.len - length))
			if count == 0 { break }
			if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			assert count > 0; length += int(count)
		}
		C.close(descriptors[0]); mut status := i32(-1)
		assert C.ios_waitpid(child, unsafe { &status }, 0) == child && status == 256
		output := unsafe { tos(&bytes[0], length) }
		expected := ['unlock requires its owner', 'not owned by this thread', 'owned by this thread', 'recursive unfair-lock', 'unlock requires its owner', 'aligned four-byte', 'aligned four-byte', 'unsupported unfair-lock flags', 'aligned four-byte']![operation]
		assert output.contains(expected) && !output.contains('runtime error:') && !output.contains('AddressSanitizer')
		if operation == 4 { api.release(unsafe { &words[0] }) }
	}
}

fn test_unfair_lock() {
	assert sizeof(u32) == 4
	api := unfair_test_api()
	for _ in 0 .. 2 {
		system_data_start()!
		mut state := UnfairTestState{ api: api }
		pointer := unsafe { &state.guards[1] }
		darwin_set_errno(83)
		api.not_owner(pointer); assert api.try_acquire(pointer); api.owner(pointer)
		assert state.guards[1] != 0 && !api.try_acquire(pointer)
		api.release(pointer); assert state.guards[1] == 0
		assert unsafe { *C.ios_errno_address() } == 83
		api.acquire(pointer)
		mut handle := u64(0)
		assert C.pthread_create(unsafe { voidptr(&handle) }, unsafe { nil }, unsafe { voidptr(unfair_test_blocked) }, unsafe { voidptr(&state) }) == 0
		for C.ios_load_pointer(unsafe { &state.attempted }) == 0 { time.sleep(time.millisecond) }
		time.sleep(10 * time.millisecond); unfair_wake(pointer)
		time.sleep(10 * time.millisecond); assert C.ios_load_pointer(unsafe { &state.entered }) == 0
		state.publication = 0x17395b; api.release(pointer)
		assert C.pthread_join(voidptr(handle), unsafe { nil }) == 0
		assert C.ios_load_pointer(unsafe { &state.entered }) == 1
		state.publication = 0x8db90ac371
		mut handles := [8]u64{}
		for index in 0 .. 8 { assert C.pthread_create(unsafe { voidptr(&handles[index]) }, unsafe { nil }, unsafe { voidptr(unfair_test_worker) }, unsafe { voidptr(&state) }) == 0 }
		for worker in handles { assert C.pthread_join(voidptr(worker), unsafe { nil }) == 0 }
		assert state.counter == 8000 && state.guards == [u32(0x12345678), 0, 0x76543210]!
		unfair_test_fork(api); unfair_test_rejections(api)
		mut rejected := false; runtime_symbol('/usr/lib/libobjc.A.dylib', '_os_unfair_lock_lock') or { rejected = true }; assert rejected
		system_data_stop()
	}
	println('IOS-UNFAIR-LOCK: guarded four-byte layout, ownership, flags, errno, blocked and spurious wakeups, publication, eight callers, fork, misuse rejection and two images passed')
}
