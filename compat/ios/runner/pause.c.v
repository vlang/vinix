// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <unistd.h>

fn C.pause() i32

fn darwin_pause() i32 {
	previous := unsafe { *C.ios_errno_address() }
	// Native pause waits with the calling thread's current signal mask. It
	// returns EINTR after a caught signal, including SA_RESTART handlers.
	// Keep it outside the runtime namespace so handlers can enter the bridge.
	return darwin_process_result(C.pause(), previous)
}
