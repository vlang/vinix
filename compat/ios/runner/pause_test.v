// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

fn C.sigpending(voidptr) i32
fn C.pthread_kill(u64, i32) i32

type PauseTestCall = fn () i32
type PauseTestSend = fn (u64, i32) i32

__global pause_test_caught = i64(0)
__global pause_test_wrong = u64(0)

struct PauseTestState {
	call PauseTestCall = unsafe { nil }
mut:
	ready u64
	done u64
	result i32
	saved_error i32
	before u64
	after u64
	pending u64
}

// A signal callback must not allocate, take a runtime mutex or leave errno
// changed when another signal arrives just after the pause call has returned.
fn pause_test_callback(number i32) {
	previous := unsafe { *C.ios_errno_address() }
	if number == 30 { C.ios_ref_change(unsafe { &pause_test_caught }, 1) }
	else { C.ios_store_pointer(unsafe { &pause_test_wrong }, 1) }
	darwin_set_errno(previous)
}

fn pause_test_action(native bool, number i32, action &DarwinSignalAction, output &DarwinSignalAction) i32 {
	$if macos {
		if native { return signal_native_action(number, action, output) }
	}
	return darwin_sigaction(number, action, output)
}

fn pause_test_worker(context voidptr) voidptr {
	mut state := unsafe { &PauseTestState(context) }
	mut mask := [16]u64{}
	assert C.sigprocmask(i32(C.SIG_SETMASK), unsafe { nil }, unsafe { voidptr(&mask[0]) }) == 0
	state.before = mask[0]
	darwin_set_errno(83)
	C.ios_store_pointer(unsafe { &state.ready }, 1)
	state.result = state.call()
	state.saved_error = unsafe { *C.ios_errno_address() }
	assert C.sigprocmask(i32(C.SIG_SETMASK), unsafe { nil }, unsafe { voidptr(&mask[0]) }) == 0
	state.after = mask[0]
	mut pending := [16]u64{}
	assert C.sigpending(unsafe { voidptr(&pending[0]) }) == 0
	state.pending = pending[0]
	C.ios_store_pointer(unsafe { &state.done }, 1)
	return unsafe { nil }
}

fn pause_test_profile(call PauseTestCall, native bool, flags i32) {
	mut originals := [3]DarwinSignalAction{}
	numbers := [i32(30), 31, 28]!
	for index, number in numbers {
		mut action := DarwinSignalAction{
			handler: if number == 28 { u64(1) } else { u64(unsafe { voidptr(pause_test_callback) }) }
			flags: if number == 30 { flags } else { i32(0) }
		}
		assert pause_test_action(native, number, unsafe { &action }, unsafe { &originals[index] }) == 0
	}
	defer { for index, number in numbers { assert pause_test_action(native, number, unsafe { &originals[index] }, unsafe { nil }) == 0 } }
	mut mask := [16]u64{}
	mask[0] = u64(1) << u32(darwin_native_signal(31) - 1)
	mut original_mask := [16]u64{}
	assert C.sigprocmask(i32(C.SIG_BLOCK), unsafe { voidptr(&mask[0]) }, unsafe { voidptr(&original_mask[0]) }) == 0
	defer { assert C.sigprocmask(i32(C.SIG_SETMASK), unsafe { voidptr(&original_mask[0]) }, unsafe { nil }) == 0 }
	mut handles := [8]u64{}
	mut states := [8]PauseTestState{}
	start_count := C.ios_load_pointer(unsafe { &u64(&pause_test_caught) })
	for index in 0 .. 8 {
		states[index] = PauseTestState{call: call}
		assert C.pthread_create(unsafe { voidptr(&handles[index]) }, unsafe { nil }, unsafe { voidptr(pause_test_worker) }, unsafe { voidptr(&states[index]) }) == 0
	}
	deadline := time.sys_mono_now() + 5000000000
	for index in 0 .. 8 {
		for C.ios_load_pointer(unsafe { &states[index].ready }) == 0 { assert time.sys_mono_now() < deadline; time.sleep(time.millisecond) }
	}
	send := unsafe { PauseTestSend(voidptr(C.pthread_kill)) }
	for handle in handles { assert send(handle, darwin_native_signal(28)) == 0 }
	time.sleep(10 * time.millisecond)
	for index in 0 .. 8 { assert C.ios_load_pointer(unsafe { &states[index].done }) == 0 }
	for handle in handles { assert send(handle, darwin_native_signal(31)) == 0 }
	time.sleep(10 * time.millisecond)
	for index in 0 .. 8 { assert C.ios_load_pointer(unsafe { &states[index].done }) == 0 }
	assert C.ios_load_pointer(unsafe { &pause_test_wrong }) == 0
	// Readiness precedes entering libc: repeat delivery until completion so a
	// signal in that allowed pause-entry window cannot hang the test itself.
	for {
		mut remaining := 0
		for index in 0 .. 8 {
			if C.ios_load_pointer(unsafe { &states[index].done }) != 0 { continue }
			remaining++
			result := send(handles[index], darwin_native_signal(30))
			assert result == 0 || C.ios_load_pointer(unsafe { &states[index].done }) == 1
		}
		if remaining == 0 { break }
		assert time.sys_mono_now() < deadline
		time.sleep(time.millisecond)
	}
	for handle in handles { assert C.pthread_join(voidptr(handle), unsafe { nil }) == 0 }
	for state in states {
		assert state.result == -1 && state.saved_error == 4
		assert state.before == state.after && state.pending & mask[0] != 0
	}
	assert C.ios_load_pointer(unsafe { &u64(&pause_test_caught) }) >= start_count + 8
	assert C.ios_load_pointer(unsafe { &pause_test_wrong }) == 0
	if native { println('NATIVE-PAUSE: flags='+flags.str()+' eight callers return -1/EINTR, ignored/blocked signals retain the wait and pending mask is preserved') }
}

fn test_pause() {
	call := unsafe { PauseTestCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_pause')!)) }
	for _ in 0 .. 2 {
		system_data_start()!
		for flags in [i32(0), 2]! {
			$if macos { pause_test_profile(C.pause, true, flags) }
			pause_test_profile(call, false, flags)
		}
		image_atfork_start()!
		child := C.ios_fork(); assert child >= 0
		if child == 0 { pause_test_profile(call, false, 2); C._exit(0) }
		mut status := i32(-1)
		assert C.ios_waitpid(child, unsafe { &status }, 0) == child && status == 0
		image_atfork_stop()
		mut rejected := false; runtime_symbol('/usr/lib/libobjc.A.dylib', '_pause') or { rejected = true }; assert rejected
		system_data_stop()
	}
	println('IOS-PAUSE: native signal wait, EINTR with/without SA_RESTART, ignored/blocked delivery, pending signals, unchanged masks, eight callers, fork and two images passed')
}
