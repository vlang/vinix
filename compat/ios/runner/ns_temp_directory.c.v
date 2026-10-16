// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct NSTempDirectoryFailure {}
fn (_ &NSTempDirectoryFailure) msg() string { return 'iOS: unsupported application temporary directory' }
fn (_ &NSTempDirectoryFailure) code() int { return 1 }
__global ns_temp_directory_failure_value = NSTempDirectoryFailure{}
fn ns_temp_directory_failure() IError { return unsafe { &ns_temp_directory_failure_value } }

// Native Foundation returns a +0 NSString ending in a separator and does not
// follow changes to TMPDIR. Use tmp inside the same application container as
// Documents, provisioning it through the existing file-manager directory path.
fn ns_temp_directory_checked() !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return ns_temp_directory_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	documents := ns_home_documents_checked()!
	parent := ns_home_parent_checked(if documents.len != 0 { documents } else { ios_runtime.bundle })!
	scratch := u64(C.__builtin_alloca(1024))
	mut length := 0
	for byte in parent {
		if byte == `/` && length > 0 && unsafe { *(&u8(scratch + u64(length - 1))) } == `/` { continue }
		unsafe { *(&u8(scratch + u64(length))) = byte }
		length++
	}
	if length > 1 { unsafe { *(&u8(scratch + u64(length))) = `/` }; length++ }
	if length + 4 > 1023 { return ns_temp_directory_failure() }
	unsafe { C.memcpy(voidptr(scratch + u64(length)), c'tmp/', 4) }
	result := owned_string(unsafe { tos(&u8(scratch), length + 4) })
	// Package launch prepares this private directory before entering unveil.
	// Reuse it directly: recursive creation probes/mkdirs its host ancestors,
	// which are outside the app's data grant even when the final path exists.
	path := string_text(result)
	mut directory := u8(0)
	exists := ns_file_manager_directory(unsafe { &char(path.str) }, &directory) == 0 && directory != 0
	if !exists && !ns_file_manager_create(result, true, 0, 0) {
		objc_release(result)
		return ns_temp_directory_failure()
	}
	return objc_autorelease(result)
}
fn ns_temp_directory() u64 { return ns_temp_directory_checked() or { panic(err) } }
