// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.__builtin_frame_address(i32) voidptr

type AltstackTestCall = fn (voidptr, voidptr) i32

__global altstack_test_key = u64(0)

struct AltstackTestState {
	call AltstackTestCall = unsafe { nil }
mut:
	frame u64
	query_result i32
	query_errno i32
	query [3]u64
	results [6][5]u64
	seen bool
}

// No assertion/formatting, allocation or runtime mutex in a signal callback.
fn altstack_test_callback(_number i32) {
	mut state := unsafe { &AltstackTestState(C.pthread_getspecific(altstack_test_key)) }
	state.frame = u64(C.__builtin_frame_address(0))
	darwin_set_errno(83)
	state.query_result = state.call(unsafe { nil }, unsafe { voidptr(&state.query[0]) })
	state.query_errno = unsafe { *C.ios_errno_address() }
	state.query[2] = u64(u32(state.query[2]))
	for index, flags in [u32(0), 1, 2, 4, ~u32(0), 0]! {
		mut input := [u64(0), if index == 5 { u64(0) } else { u64(65536) }, u64(flags)]!
		mut output := [u64(0xa5a5a5a5a5a5a5a5), 0xa5a5a5a5a5a5a5a5, 0xa5a5a5a5a5a5a5a5]!
		darwin_set_errno(83)
		result := state.call(unsafe { voidptr(&input[0]) }, unsafe { voidptr(&output[0]) }); failure := unsafe { *C.ios_errno_address() }
		state.results[index] = [u64(i64(result)), u64(failure), output[0], output[1], output[2]]!
	}
	state.seen = true
	darwin_set_errno(83)
}

fn altstack_test_query(call AltstackTestCall) [3]u64 {
	mut words := [3]u64{}
	for shift in [0, 1, 3]! {
		offset := 8 + shift; tail_start := offset + 24
		mut bytes := [48]u8{}; C.memset(unsafe { voidptr(&bytes[0]) }, 0xa5, 48)
		darwin_set_errno(83); result := call(unsafe { nil }, unsafe { voidptr(&bytes[offset]) }); failure := unsafe { *C.ios_errno_address() }
		assert result == 0 && failure == 83
		for index in 0 .. offset { assert bytes[index] == 0xa5 }
		for index in tail_start .. bytes.len { assert bytes[index] == 0xa5 }
		unsafe { C.memcpy(voidptr(&words[0]), voidptr(&bytes[offset]), 24) }
		words[2] = u64(u32(words[2])) // Native padding is unspecified.
	}
	return words
}

fn altstack_test_errors(call AltstackTestCall, pointer u64, length u64) {
	before := altstack_test_query(call)
	for flags in [u32(0), 1, 2, 4, 5, 8, ~u32(0)]! {
		for size in [u64(0), 1, 32767, 65536]! {
			if size >= 32768 && flags in [u32(0), 4]! { continue }
			mut input := [pointer, size, u64(flags)]!
			mut output := [u64(0x1122334455667788), 0xa5a5a5a5a5a5a5a5, 0xa5a5a5a5a5a5a5a5, 0xa5a5a5a5a5a5a5a5, 0x8877665544332211]!
			darwin_set_errno(83); result := call(unsafe { voidptr(&input[0]) }, unsafe { voidptr(&output[1]) }); failure := unsafe { *C.ios_errno_address() }
			assert result == -1 && failure == if size < 32768 { i32(12) } else { i32(22) }
			assert output[0] == 0x1122334455667788 && output[4] == 0x8877665544332211
			if size < 32768 { assert output[1] == 0xa5a5a5a5a5a5a5a5 && output[2] == 0xa5a5a5a5a5a5a5a5 && output[3] == 0xa5a5a5a5a5a5a5a5 }
			else { assert output[1] == before[0] && output[2] == before[1] && u32(output[3]) == u32(before[2]) }
			assert input == [pointer, size, u64(flags)]!
		}
	}
	assert altstack_test_query(call) == [pointer, length, u64(0)]!
}

fn altstack_test_delivery(state &AltstackTestState, pointer u64, length u64) {
	assert C.pthread_setspecific(altstack_test_key, voidptr(state)) == 0
	darwin_set_errno(83); result := C.raise(darwin_native_signal(30)); failure := unsafe { *C.ios_errno_address() }
	assert result == 0 && failure == 83 && state.seen
	assert state.frame >= pointer && state.frame < pointer + length
	assert state.query_result == 0 && state.query_errno == 83 && state.query == [pointer, length, u64(1)]!
	for index, sample in state.results {
		assert i64(sample[0]) == -1 && sample[1] == if index == 0 { u64(1) } else if index == 5 { u64(12) } else { u64(22) }
		if index == 5 { assert sample[2] == 0xa5a5a5a5a5a5a5a5 && sample[3] == 0xa5a5a5a5a5a5a5a5 && sample[4] == 0xa5a5a5a5a5a5a5a5 }
		else { assert sample[2] == pointer && sample[3] == length && u32(sample[4]) == 1 }
	}
}

fn altstack_test_thread(call AltstackTestCall, fork_check bool) {
	mut original := C.stack_t{}
	assert C.sigaltstack(unsafe { nil }, unsafe { voidptr(&original) }) == 0
	length := u64(512 * 1024); page := u64(C.getpagesize())
	mapping := C.mmap(unsafe { nil }, usize(length + page * 2), C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANON, -1, 0)
	assert u64(mapping) != ~u64(0)
	pointer := u64(mapping) + page
	assert C.mprotect(voidptr(pointer), usize(length), C.PROT_READ | C.PROT_WRITE) == 0
	mut request := [pointer, length, u64(0)]!
	for shift in [0, 1, 3]! {
		mut bytes := [48]u8{}; C.memset(unsafe { voidptr(&bytes[0]) }, 0xa5, 48)
		unsafe { C.memcpy(voidptr(&bytes[8 + shift]), voidptr(&request[0]), 24) }
		before := bytes; darwin_set_errno(83)
		assert call(unsafe { voidptr(&bytes[8 + shift]) }, unsafe { nil }) == 0 && unsafe { *C.ios_errno_address() } == 83
		assert bytes == before
		assert altstack_test_query(call) == request
	}
	altstack_test_errors(call, pointer, length)
	// old_ss is written first on Darwin: an aliased request becomes the old
	// descriptor, rather than the originally supplied replacement.
	mut alias := [pointer + page, u64(32768), u64(0)]!
	assert call(unsafe { voidptr(&alias[0]) }, unsafe { voidptr(&alias[0]) }) == 0
	assert alias[0] == pointer && alias[1] == length && u32(alias[2]) == 0
	assert altstack_test_query(call) == request
	mut state := AltstackTestState{call: call}
	altstack_test_delivery(unsafe { &state }, pointer, length)
	assert altstack_test_query(call) == request
	if fork_check {
		image_atfork_start() or { panic(err) }; child := C.ios_fork(); assert child >= 0
		if child == 0 {
			// The measured native fork path clears the alternate stack.
			assert altstack_test_query(call) == [u64(0), 0, 4]!
			assert call(unsafe { voidptr(&request[0]) }, unsafe { nil }) == 0
			altstack_test_delivery(unsafe { &state }, pointer, length); C._exit(0)
		}
		mut status := i32(-1); assert C.ios_waitpid(child, unsafe { &status }, 0) == child && status == 0
		image_atfork_stop(); assert altstack_test_query(call) == request
	}
	request[2] = 4; assert call(unsafe { voidptr(&request[0]) }, unsafe { nil }) == 0
	assert altstack_test_query(call) == request
	alias = [pointer + page, u64(32768), u64(0)]!
	assert call(unsafe { voidptr(&alias[0]) }, unsafe { voidptr(&alias[0]) }) == 0
	assert altstack_test_query(call) == request
	// Stack memory is caller-owned. Restore/disable native delivery before
	// unmapping it; a disabled descriptor may retain its historical address.
	if original.ss_flags & i32(C.SS_DISABLE) != 0 && original.ss_size < 32768 { original.ss_size = 32768 }
	assert C.sigaltstack(unsafe { voidptr(&original) }, unsafe { nil }) == 0
	mut restored := C.stack_t{}; assert C.sigaltstack(unsafe { nil }, unsafe { voidptr(&restored) }) == 0
	assert restored.ss_flags == original.ss_flags
	if original.ss_flags & i32(C.SS_DISABLE) == 0 { assert restored.ss_sp == original.ss_sp && restored.ss_size == original.ss_size }
	assert C.pthread_setspecific(altstack_test_key, unsafe { nil }) == 0
	assert C.munmap(mapping, usize(length + page * 2)) == 0
}

fn altstack_test_worker(context voidptr) voidptr {
	call := unsafe { AltstackTestCall(context) }
	altstack_test_thread(call, false)
	return unsafe { nil }
}

fn altstack_test_profile(call AltstackTestCall, native bool, flags i32) {
	mut original := [24]u64{}
	assert signal_native_action(darwin_native_signal(30), unsafe { nil }, unsafe { voidptr(&original[0]) }) == 0
	mut action := DarwinSignalAction{handler: u64(unsafe { voidptr(altstack_test_callback) }), flags: flags}
	$if macos { if native { assert signal_native_action(30, unsafe { voidptr(&action) }, unsafe { nil }) == 0 } }
	if !native { assert darwin_sigaction(30, unsafe { &action }, unsafe { nil }) == 0 }
	altstack_test_thread(call, true)
	mut handles := [8]u64{}
	for index in 0 .. 8 { assert C.pthread_create(unsafe { voidptr(&handles[index]) }, unsafe { nil }, unsafe { voidptr(altstack_test_worker) }, unsafe { voidptr(call) }) == 0 }
	for handle in handles { assert C.pthread_join(voidptr(handle), unsafe { nil }) == 0 }
	assert signal_native_action(darwin_native_signal(30), unsafe { voidptr(&original[0]) }, unsafe { nil }) == 0
	if native { println('NATIVE-SIGALTSTACK: flags='+flags.str()+' guarded layouts, 32KiB validation/output priority, aliasing, disabled history, real alternate-stack callbacks, on-stack errors, eight threads, fork and restored memory passed') }
}

fn test_sigaltstack() {
	assert C.pthread_key_create(unsafe { voidptr(&altstack_test_key) }, unsafe { nil }) == 0
	call := unsafe { AltstackTestCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_sigaltstack')!)) }
	mut mask := [16]u64{}; mut original := [16]u64{}; mask[0] = u64(1) << u32(darwin_native_signal(30) - 1)
	assert C.sigprocmask(i32(C.SIG_UNBLOCK), unsafe { voidptr(&mask[0]) }, unsafe { voidptr(&original[0]) }) == 0
	for _ in 0 .. 2 {
		system_data_start()!
		for flags in [i32(1), 3]! {
			$if macos { native := unsafe { AltstackTestCall(voidptr(C.sigaltstack)) }; altstack_test_profile(native, true, flags) }
			altstack_test_profile(call, false, flags)
		}
		mut rejected := false; runtime_symbol('/usr/lib/libobjc.A.dylib', '_sigaltstack') or { rejected = true }; assert rejected
		system_data_stop()
	}
	assert C.sigprocmask(i32(C.SIG_SETMASK), unsafe { voidptr(&original[0]) }, unsafe { nil }) == 0
	assert C.pthread_key_delete(altstack_test_key) == 0
	println('IOS-SIGALTSTACK: guarded/unaligned layouts, native error/output/alias semantics, disabled history, SA_ONSTACK delivery, eight threads, fork, restore before unmap and two images passed')
}
