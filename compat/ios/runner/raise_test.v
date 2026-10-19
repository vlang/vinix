// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <sys/resource.h>

fn C.sigpending(voidptr) i32
fn C.setrlimit(i32, voidptr) i32

type RaiseTestCall = fn (i32) i32

__global raise_test_pipe = [2]i32{}
__global raise_test_nested = u64(0)
__global raise_test_nested_result = i32(-1)
__global raise_test_nested_errno = i32(-1)
__global raise_test_call = RaiseTestCall(unsafe { nil })

struct RaiseTestState {
	call RaiseTestCall = unsafe { nil }
	seed i32
mut:
	identity u64
}

// Keep callbacks signal-safe. The bounded pipe record identifies the actual
// receiving thread and its errno before deliberately changing that errno.
fn raise_test_callback(number i32) {
	previous := unsafe { *C.ios_errno_address() }
	mut payload := [u64(number), u64(C.pthread_self()), u64(previous)]!
	if C.write(raise_test_pipe[1], unsafe { voidptr(&payload[0]) }, 24) != 24 { C._exit(91) }
	if number == 30 && C.ios_load_pointer(unsafe { &raise_test_nested }) != 0 {
		C.ios_store_pointer(unsafe { &raise_test_nested }, 0)
		raise_test_nested_result = raise_test_call(31)
		raise_test_nested_errno = unsafe { *C.ios_errno_address() }
	}
	darwin_set_errno(71)
}

fn raise_test_receive(number i32, identity u64, previous i32) {
	mut payload := [3]u64{}
	assert C.read(raise_test_pipe[0], unsafe { voidptr(&payload[0]) }, 24) == 24
	assert payload == [u64(number), identity, u64(previous)]!
}

fn raise_test_action(native bool, number i32, action &DarwinSignalAction, output &DarwinSignalAction) i32 {
	$if macos { if native { return signal_native_action(number, action, output) } }
	return darwin_sigaction(number, action, output)
}

fn raise_test_worker(context voidptr) voidptr {
	mut state := unsafe { &RaiseTestState(context) }
	state.identity = u64(C.pthread_self())
	for number in [i32(30), 31, 10, 12]! {
		darwin_set_errno(state.seed)
		result := state.call(number); failure := unsafe { *C.ios_errno_address() }
		assert result == 0 && failure == 71
	}
	return unsafe { nil }
}

fn raise_test_profile(call RaiseTestCall, native bool, flags i32) {
	numbers := [i32(30), 31, 10, 12, 28]!
	mut originals := [5][24]u64{}
	mut bits := u64(0)
	for index, number in numbers {
		assert signal_native_action(darwin_native_signal(number), unsafe { nil }, unsafe { voidptr(&originals[index][0]) }) == 0
		mut action := DarwinSignalAction{handler: if number == 28 { u64(1) } else { u64(unsafe { voidptr(raise_test_callback) }) }, flags: flags}
		assert raise_test_action(native, number, unsafe { &action }, unsafe { nil }) == 0
		bits |= u64(1) << u32(darwin_native_signal(number) - 1)
	}
	// Sanitizers own SA_SIGINFO fault handlers outside the guest action subset.
	// Restore their complete native records after this profile.
	defer { for index, number in numbers { assert signal_native_action(darwin_native_signal(number), unsafe { voidptr(&originals[index][0]) }, unsafe { nil }) == 0 } }
	mut original_mask := [16]u64{}; mut mask := [16]u64{}
	assert C.sigprocmask(i32(C.SIG_SETMASK), unsafe { nil }, unsafe { voidptr(&original_mask[0]) }) == 0
	C.memcpy(unsafe { voidptr(&mask[0]) }, unsafe { voidptr(&original_mask[0]) }, usize(sizeof(mask)))
	mask[0] &= ~bits
	assert C.sigprocmask(i32(C.SIG_SETMASK), unsafe { voidptr(&mask[0]) }, unsafe { nil }) == 0
	defer { assert C.sigprocmask(i32(C.SIG_SETMASK), unsafe { voidptr(&original_mask[0]) }, unsafe { nil }) == 0 }
	for number in [i32(-2147483647), -1, 32, 64, 2147483647]! {
		darwin_set_errno(83); result := call(number); failure := unsafe { *C.ios_errno_address() }
		assert result == -1 && failure == 22
	}
	for number in [i32(0), 28]! {
		darwin_set_errno(83); result := call(number); failure := unsafe { *C.ios_errno_address() }
		assert result == 0 && failure == 83
	}
	$if linux {
		for number in [i32(7), 29]! { darwin_set_errno(83); assert call(number) == -1 && unsafe { *C.ios_errno_address() } == 45 }
	}
	identity := u64(C.pthread_self())
	for number in [i32(30), 31, 10, 12]! {
		darwin_set_errno(83); result := call(number); failure := unsafe { *C.ios_errno_address() }
		assert result == 0 && failure == 71
		raise_test_receive(number, identity, 83)
	}
	// A blocked self-directed signal remains pending on this thread. Raising
	// it must return without invoking the callback or altering the mask.
	blocked := u64(1) << u32(darwin_native_signal(31) - 1)
	mask[0] |= blocked
	assert C.sigprocmask(i32(C.SIG_SETMASK), unsafe { voidptr(&mask[0]) }, unsafe { nil }) == 0
	darwin_set_errno(83); result := call(31); failure := unsafe { *C.ios_errno_address() }
	assert result == 0 && failure == 83
	mut pending := [16]u64{}; mut after := [16]u64{}
	assert C.sigpending(unsafe { voidptr(&pending[0]) }) == 0 && pending[0] & blocked != 0
	assert C.sigprocmask(i32(C.SIG_SETMASK), unsafe { nil }, unsafe { voidptr(&after[0]) }) == 0 && after[0] == mask[0]
	mask[0] &= ~blocked; darwin_set_errno(83)
	assert C.sigprocmask(i32(C.SIG_SETMASK), unsafe { voidptr(&mask[0]) }, unsafe { nil }) == 0
	raise_test_receive(31, identity, 83)
	assert C.sigpending(unsafe { voidptr(&pending[0]) }) == 0 && pending[0] & blocked == 0
	// A handler can raise a second signal without a runtime registry lock.
	raise_test_call = call; C.ios_store_pointer(unsafe { &raise_test_nested }, 1)
	darwin_set_errno(83); assert call(30) == 0 && unsafe { *C.ios_errno_address() } == 71
	raise_test_receive(30, identity, 83); raise_test_receive(31, identity, 83)
	assert raise_test_nested_result == 0 && raise_test_nested_errno == 71
	mut states := [8]RaiseTestState{}; mut handles := [8]u64{}
	for index in 0 .. 8 {
		states[index] = RaiseTestState{call: call, seed: i32(90 + index)}
		assert C.pthread_create(unsafe { voidptr(&handles[index]) }, unsafe { nil }, unsafe { voidptr(raise_test_worker) }, unsafe { voidptr(&states[index]) }) == 0
	}
	for handle in handles { assert C.pthread_join(voidptr(handle), unsafe { nil }) == 0 }
	mut seen := [8]u32{}
	for _ in 0 .. 32 {
		mut payload := [3]u64{}; assert C.read(raise_test_pipe[0], unsafe { voidptr(&payload[0]) }, 24) == 24
		index := int(payload[2]) - 90; assert index >= 0 && index < 8
		assert payload[1] == states[index].identity
		mut bit := u32(0)
		for position, number in [u64(30), 31, 10, 12]! { if payload[0] == number { bit = u32(1) << position } }
		assert bit != 0 && seen[index] & bit == 0; seen[index] |= bit
	}
	for value in seen { assert value == 15 }
	assert C.sigprocmask(i32(C.SIG_SETMASK), unsafe { nil }, unsafe { voidptr(&after[0]) }) == 0 && after[0] == mask[0]
	if native { println('NATIVE-RAISE: flags='+flags.str()+' same-thread synchronous delivery, handler errno, zero/invalid/ignored, blocked/pending, nested and eight callers passed') }
}

fn raise_test_fatal(call RaiseTestCall, native bool) {
	for number in [i32(6), 10, 12, 9]! {
		image_atfork_start() or { panic(err) }
		child := C.ios_fork(); assert child >= 0
		if child == 0 {
			mut limit := [u64(0), 0]!; assert C.setrlimit(i32(C.RLIMIT_CORE), unsafe { voidptr(&limit[0]) }) == 0
			if number != 9 { mut action := DarwinSignalAction{}; assert raise_test_action(native, number, unsafe { &action }, unsafe { nil }) == 0 }
			mut mask := [16]u64{}; mask[0] = u64(1) << u32(darwin_native_signal(number) - 1)
			assert C.sigprocmask(i32(C.SIG_UNBLOCK), unsafe { voidptr(&mask[0]) }, unsafe { nil }) == 0
			call(number); C._exit(92)
		}
		mut status := i32(-1); assert C.ios_waitpid(child, unsafe { &status }, 0) == child
		mut fields := [3]i32{}; C.ios_wait_status(status, unsafe { &fields[0] })
		assert fields[0] == 2 && wait_signal_darwin(fields[1]) == number
		image_atfork_stop()
	}
	if native { println('NATIVE-RAISE: default ABRT/BUS/SYS/KILL dispositions terminate isolated fork children') }
}

fn test_raise() {
	call := unsafe { RaiseTestCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_raise')!)) }
	assert C.pipe(unsafe { &raise_test_pipe[0] }) == 0
	for round in 0 .. 2 {
		system_data_start()!
		for flags in [i32(0), 2]! {
			$if macos { raise_test_profile(C.raise, true, flags) }
			raise_test_profile(call, false, flags)
		}
		$if macos { if round == 0 { raise_test_fatal(C.raise, true) } }
		raise_test_fatal(call, false)
		mut rejected := false; runtime_symbol('/usr/lib/libobjc.A.dylib', '_raise') or { rejected = true }; assert rejected
		system_data_stop()
	}
	for fd in raise_test_pipe { assert C.close(fd) == 0 }
	println('IOS-RAISE: synchronous same-thread delivery, handler errno, zero/invalid/ignored, masks/pending, nested callbacks, eight callers, fatal fork children and two images passed')
}
