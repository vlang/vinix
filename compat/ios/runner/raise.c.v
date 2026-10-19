// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <signal.h>

fn C.raise(i32) i32

fn darwin_raise(number i32) i32 {
	if number < 0 || number > 31 { darwin_set_errno(22); return -1 }
	native := darwin_native_signal(number)
	if native < 0 { darwin_set_errno(45); return -1 }
	// Native raise targets this thread and retains its signal mask. A caught
	// handler can change errno: keep that observable change on success.
	result := C.raise(native)
	if result < 0 { darwin_set_errno(darwin_native_error(unsafe { *C.ios_errno_address() })) }
	return result
}
