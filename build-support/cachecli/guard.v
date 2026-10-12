// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module cachecli

#include <signal.h>

fn C.signal(i32, voidptr) voidptr
fn C.__atomic_load_n(&i32, i32) i32
fn C.__atomic_store_n(&i32, i32, i32)

__global (
	pending_signal i32
)

fn cachecli_signal_received(signal i32) {
	unsafe { C.__atomic_store_n(&pending_signal, signal, C.__ATOMIC_RELAXED) }
}

pub fn cancelled() bool {
	return unsafe { C.__atomic_load_n(&pending_signal, C.__ATOMIC_RELAXED) } != 0
}

pub fn interrupt_status() int {
	return 128 + int(unsafe { C.__atomic_load_n(&pending_signal, C.__ATOMIC_RELAXED) })
}

pub fn checkpoint() ! {
	if cancelled() { return error_with_code('Native build interrupted', interrupt_status()) }
}

pub struct Guard {
	interrupt voidptr
	terminate voidptr
	pipe      voidptr
}

pub fn own_commands() Guard {
	unsafe { C.__atomic_store_n(&pending_signal, 0, C.__ATOMIC_RELAXED) }
	return Guard{unsafe { C.signal(C.SIGINT, voidptr(cachecli_signal_received)) }, unsafe { C.signal(C.SIGTERM, voidptr(cachecli_signal_received)) }, unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }}
}

pub fn (guard Guard) close() {
	unsafe {
		C.signal(C.SIGINT, guard.interrupt)
		C.signal(C.SIGTERM, guard.terminate)
		C.signal(C.SIGPIPE, guard.pipe)
	}
}
