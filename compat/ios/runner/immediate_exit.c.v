// SPDX-License-Identifier: GPL-2.0-or-later
module main

// C11 _Exit is independent of image initialization. The native libc backend
// terminates the entire process, including other threads, without flushing
// stdio or invoking native/image exit handlers or TLS destructors. Keep the
// Darwin int argument explicitly 32 bits at the guest entry point.
@[noreturn]
fn darwin_c11_exit(status i32) {
	C._Exit(status)
	for {}
}
