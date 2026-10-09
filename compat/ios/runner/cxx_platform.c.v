// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.ios_cxx_verbose_abort()

// Apple's random_device has four bytes of unused storage. Its constructor
// accepts every token and neither opens a file nor stores a descriptor, unlike
// musl libc++. Keep that object ABI and obtain each result from native entropy.
fn cxx_random_init(_object u64, _token u64) {}
fn cxx_random_destroy(_object u64) {}
fn cxx_random_entropy(_object u64) f64 { return 32.0 }
fn cxx_random_value(_object u64) u32 {
	mut value := u32(0)
	if C.getentropy(&value, sizeof(value)) != 0 {
		panic('iOS: C++ random_device native entropy source failed')
	}
	return value
}

// The assembly entry converts Darwin ARM64's stack-only variadic arguments
// to a fixed V signature. Use the existing host va_list bridge and preserve
// libc++'s diagnostic followed by SIGABRT.
@[export: 'ios_cxx_verbose_abort_stack']
fn cxx_verbose_abort(format &char, stack voidptr) {
	stream := C.ios_host_stdio(2)
	C.ios_vfprintf(stream, format, stack)
	C.fflush(stream)
	C.abort()
}
