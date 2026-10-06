// SPDX-License-Identifier: BSD-2-Clause
// Independent OS inputs for the frozen signal tests and V translation.
@[translated]
@[has_globals]
module signaloracle

#include <signal-oracle-native-abi.h>

@[c_extern]
__global C.errno i32

__global (
	qemu_signal_fork_fail i32
	qemu_signal_fork_calls i32
)

fn C.assert(bool)
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.open(&char, i32, ...) i32
fn C.dup2(i32, i32) i32
fn C.close(i32) i32
fn C.pause() i32
fn C.fork() i32
fn C.original_reap_ok(i32) i32
fn C.original_test_default_terminating_signals() i32
fn C.original_test_signals_reach_a_busy_loop() i32
fn C.test_default_terminating_signals() i32
fn C.test_signals_reach_a_busy_loop() i32

@[export: 'vqs_host_fork']
pub fn fork_input() i32 {
	unsafe {
		qemu_signal_fork_calls++
		if qemu_signal_fork_fail == qemu_signal_fork_calls {
			C.errno = C.EAGAIN
			return -1
		}
		return C.fork()
	}
}

// The unchanged original status helper is shared by the scoped host/native
// comparison, matching the retained helper in the maintained feature driver.
@[export: 'reap_ok']
pub fn reap_input(child i32) i32 {
	return C.original_reap_ok(child)
}

fn run_case(original bool, busy bool, failure i32) i32 {
	unsafe {
		qemu_signal_fork_fail = failure
		qemu_signal_fork_calls = 0
		C.errno = C.E2BIG
		return if busy {
			if original { C.original_test_signals_reach_a_busy_loop() } else { C.test_signals_reach_a_busy_loop() }
		} else {
			if original { C.original_test_default_terminating_signals() } else { C.test_default_terminating_signals() }
		}
	}
}

@[export: 'main']
pub fn main_entry() i32 {
	unsafe {
		$if signal_guest ? {
			mut console := C.open(c'/dev/com1', C.O_WRONLY | C.O_NOCTTY)
			if console < 0 { console = C.open(c'/dev/console', C.O_WRONLY | C.O_NOCTTY) }
			if console >= 0 {
				C.dup2(console, 1)
				C.dup2(console, 2)
				C.close(console)
			}
		}
		for busy in [false, true]! {
			for failure in i32(0) .. 3 {
				original := run_case(true, busy, failure)
				original_calls := qemu_signal_fork_calls
				original_errno := C.errno
				ported := run_case(false, busy, failure)
				C.assert(ported == original && qemu_signal_fork_calls == original_calls && C.errno == original_errno)
				C.assert(ported == if failure == 0 { 0 } else { 1 })
			}
		}
		C.puts(c'QEMU CORE SIGNAL DIFFERENTIAL PASS: 6 native signal/fork cases')
		$if signal_guest ? {
			C.fflush(nil)
			for { C.pause() }
		}
		return 0
	}
}
