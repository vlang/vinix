// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

fn C.pipe(&i32) i32
fn C.pthread_kill(u64, i32) i32

type NativeThreadSignal = fn (u64, i32) i32

__global signal_test_pipe = [2]i32{}
__global signal_test_release = [2]i32{}
__global signal_test_hold = u64(0)

// The callback uses native signal-safe I/O and atomics, with no V allocation.
fn signal_test_callback(number i32) {
	mut payload := [u64(number), u64(0), u64(0)]!
	mut mask := [16]u64{}
	if C.sigprocmask(i32(C.SIG_SETMASK), unsafe { nil }, unsafe { voidptr(&mask[0]) }) != 0 {
		payload[0] = 0
	}
	payload[1] = mask[0]
	if C.ios_load_pointer(unsafe { &signal_test_hold }) != 0 {
		mut old := DarwinSignalAction{}
		// A callback must not relock a namespace it may have interrupted.
		payload[2] = u64(darwin_sigaction(number, unsafe { nil }, unsafe { &old }) == -1
			&& unsafe { *C.ios_errno_address() } == 11)
	}
	C.write(signal_test_pipe[1], unsafe { &payload[0] }, 24)
	if C.ios_load_pointer(unsafe { &signal_test_hold }) != 0 {
		mut byte := u8(0)
		C.read(signal_test_release[0], unsafe { &byte }, 1)
	}
}

fn signal_test_action(native bool, number i32, action &DarwinSignalAction, old &DarwinSignalAction) i32 {
	$if macos {
		if native { return signal_native_action(number, action, old) }
	}
	return darwin_sigaction(number, action, old)
}

fn signal_test_receive() [3]u64 {
	mut payload := [3]u64{}
	assert C.read(signal_test_pipe[0], unsafe { &payload[0] }, 24) == 24
	return payload
}

fn signal_test_shared(native bool) {
	for number in [i32(30), 31, 28] {
		mut original := DarwinSignalAction{}
		assert signal_test_action(native, number, unsafe { nil }, unsafe { &original }) == 0
		for flags in [i32(0), 1, 2, 3, 16, 17, 18, 19] {
			other := if number == 31 { i32(30) } else { i32(31) }
			mut action := DarwinSignalAction{
				handler: u64(unsafe { voidptr(signal_test_callback) })
				mask:    (u32(1) << 12) | (u32(1) << u32(other - 1))
				flags:   flags
			}
			mut guarded := [u64(0x1122334455667788), 0, 0, 0x8877665544332211]!
			darwin_set_errno(177)
			assert signal_test_action(native, number, unsafe { &action }, unsafe { &DarwinSignalAction(&guarded[1]) }) == 0
			assert unsafe { *C.ios_errno_address() } == 177
			assert guarded[0] == 0x1122334455667788 && guarded[3] == 0x8877665544332211
			mut output := DarwinSignalAction{}
			assert signal_test_action(native, number, unsafe { nil }, unsafe { &output }) == 0
			assert output.handler == action.handler && output.mask == action.mask && output.flags == flags
			$if macos {
				if native {
					assert C.kill(C.getpid(), number) == 0
				}
			}
			if !native {
				assert darwin_kill(C.getpid(), number) == 0
			}
			payload := signal_test_receive()
			assert payload[0] == u64(number)
			native_number := darwin_native_signal(number)
			assert payload[1] & (u64(1) << 12) != 0
			assert payload[1] & (u64(1) << u32(darwin_native_signal(other) - 1)) != 0
			assert (payload[1] & (u64(1) << u32(native_number - 1)) != 0) == (flags & 16 == 0)
		}
		assert signal_test_action(native, number, unsafe { &original }, unsafe { nil }) == 0
	}
	for number in [i32(-1), 0, 9, 17, 32] {
		mut guarded := [u64(0x1122334455667788), 0x12345678, 0x9abcdef0, 0x8877665544332211]!
		assert signal_test_action(native, number, unsafe { nil }, unsafe { &DarwinSignalAction(&guarded[1]) }) == -1
		assert unsafe { *C.ios_errno_address() } == 22
		assert guarded[1] == 0x12345678 && guarded[2] == 0x9abcdef0
	}
}

fn signal_test_self_delivery() {
	function := unsafe { NativeThreadSignal(voidptr(C.pthread_kill)) }
	assert function(u64(C.pthread_self()), darwin_native_signal(30)) == 0
}

fn signal_test_concurrent() {
	for _ in 0 .. 4 {
		mut jobs := []thread{}
		for _ in 0 .. 8 { jobs << spawn signal_test_self_delivery() }
		for _ in 0 .. 8 {
			assert signal_test_receive()[0] == 30
		}
		jobs.wait()
		assert C.ios_load_pointer(unsafe { &signal_slots[30].gate }) == signal_open
	}
}

fn signal_test_delayed_release() {
	time.sleep(30 * time.millisecond)
	mut denied := false
	signals_start() or { denied = true }
	assert denied
	mut byte := u8(1)
	assert C.write(signal_test_release[1], unsafe { &byte }, 1) == 1
}

fn signal_test_teardown_and_fork() ! {
	mut action := DarwinSignalAction{ handler: u64(unsafe { voidptr(signal_test_callback) }) }
	assert darwin_sigaction(30, unsafe { &action }, unsafe { nil }) == 0
	C.ios_store_pointer(unsafe { &signal_test_hold }, 1)
	worker := spawn signal_test_self_delivery()
	payload := signal_test_receive()
	assert payload[0] == 30 && payload[2] == 1
	assert C.ios_load_pointer(unsafe { &signal_slots[30].gate }) & 0xffffffff == 1
	// A real fork discards vanished threads' call pins in the child. The
	// parent's blocked callback remains pinned and can finish independently.
	image_atfork_start()!
	child := C.ios_fork()
	assert child >= 0
	if child == 0 {
		if C.ios_load_pointer(unsafe { &signal_slots[30].gate }) != signal_open { C._exit(1) }
		signals_stop()
		C._exit(0)
	}
	mut status := i32(-1)
	assert C.ios_waitpid(child, unsafe { &status }, 0) == child && status == 0
	image_atfork_stop()
	release := spawn signal_test_delayed_release()
	start := time.sys_mono_now()
	signals_stop()
	assert time.sys_mono_now() - start >= 15000000
	worker.wait()
	release.wait()
	C.ios_store_pointer(unsafe { &signal_test_hold }, 0)
	for number in 1 .. 32 {
		assert C.ios_load_pointer(unsafe { &signal_slots[number].gate }) == 0
		assert C.ios_load_pointer(unsafe { &signal_slots[number].handler }) == 0
	}
	mut old := DarwinSignalAction{}
	assert darwin_sigaction(30, unsafe { nil }, unsafe { &old }) == -1
	assert unsafe { *C.ios_errno_address() } == 22
}

fn test_signals() {
	assert sizeof(DarwinSignalAction) == 16
	assert C.pipe(unsafe { &signal_test_pipe[0] }) == 0
	assert C.pipe(unsafe { &signal_test_release[0] }) == 0
	for round in 0 .. 2 {
		// Native libc may add its own restorer and leave padding unspecified.
		// Compare the public handler/mask/flags after restoring the disposition.
		mut original := [24]u64{}
		assert signal_native_action(darwin_native_signal(30), unsafe { nil }, unsafe { &original[0] }) == 0
		original_action := signal_decode(30, unsafe { &C.sigaction(&original[0]) }) or { panic('native action cannot be decoded') }
		system_data_start()!
		$if macos {
			if round == 0 { signal_test_shared(true) }
		}
		signal_test_shared(false)
		mut action := DarwinSignalAction{ handler: 1, mask: 1, flags: 2 }
		mut old := DarwinSignalAction{}
		for flags in [i32(4), 8, 32, 64, -1] {
			action.flags = flags
			assert darwin_sigaction(30, unsafe { &action }, unsafe { &old }) == -1
			assert unsafe { *C.ios_errno_address() } == 45 && old.handler == 0
		}
		action.flags = 2
		// The same record can be input and output without losing its request.
		assert darwin_sigaction(30, unsafe { &action }, unsafe { &action }) == 0
		assert darwin_sigaction(30, unsafe { nil }, unsafe { &old }) == 0 && old.handler == 1 && old.mask == 1 && old.flags == 2
		assert u64(darwin_signal(30, unsafe { voidptr(signal_test_callback) })) == 1
		assert darwin_sigaction(30, unsafe { nil }, unsafe { &old }) == 0 && old.flags == 2 && old.mask == 0
		signal_test_concurrent()
		$if linux {
			for number in [i32(7), 29] {
				assert darwin_sigaction(number, unsafe { nil }, unsafe { &old }) == -1
				assert unsafe { *C.ios_errno_address() } == 45
			}
			action = DarwinSignalAction{ handler: 1, mask: u32(1) << 6 }
			assert darwin_sigaction(30, unsafe { &action }, unsafe { nil }) == -1
			assert unsafe { *C.ios_errno_address() } == 45
		}
		signal_test_teardown_and_fork()!
		system_data_stop()
		mut restored := [24]u64{}
		assert signal_native_action(darwin_native_signal(30), unsafe { nil }, unsafe { &restored[0] }) == 0
		restored_action := signal_decode(30, unsafe { &C.sigaction(&restored[0]) }) or { panic('restored action cannot be decoded') }
		assert original_action == restored_action
		$if linux {
			println('IOS-SIGNALS: native restore flags 0x${u32(original[17]):x} -> 0x${u32(restored[17]):x}; public disposition preserved')
		}
		assert (signals_symbol('_sigaction') or { u64(0) }) != 0
	}
	for fd in [signal_test_pipe[0], signal_test_pipe[1], signal_test_release[0],
		signal_test_release[1]] {
		assert C.close(fd) == 0
	}
	println('IOS-SIGNALS: Darwin layout, native delivery/masks, restart/nodefer, guards, drain, fork and two teardowns')
}
