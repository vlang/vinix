// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The main image path is configured before binding and image initializers.
// It stays owned by ImageRuntime until all image activity has drained.
// Darwin leaves the caller's 32-bit capacity untouched on success and includes
// the NUL byte in the required size reported for an insufficient buffer.
fn darwin_ns_get_executable_path(buffer &char, size &u32) i32 {
	if image_runtime == unsafe { nil } || image_runtime.path.len == 0 {
		panic('iOS: executable path requires a configured main image')
	}
	if size == unsafe { nil } { panic('iOS: executable path requires a size pointer') }
	path := image_runtime.path
	required := u64(path.len) + 1
	if required > 0xffffffff { panic('iOS: executable path exceeds the 32-bit buffer size') }
	if unsafe { *size } < u32(required) {
		unsafe { *size = u32(required) }
		return -1
	}
	if buffer == unsafe { nil } {
		panic('iOS: executable path requires a sufficient output buffer')
	}
	unsafe {
		C.memcpy(buffer, path.str, usize(path.len))
		buffer[path.len] = 0
	}
	return 0
}
