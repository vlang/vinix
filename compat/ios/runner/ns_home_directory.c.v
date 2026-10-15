// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8

struct NSHomeDirectoryFailure {}
fn (_ &NSHomeDirectoryFailure) msg() string { return 'iOS: unsupported application home directory' }
fn (_ &NSHomeDirectoryFailure) code() int { return 1 }
__global ns_home_directory_failure_value = NSHomeDirectoryFailure{}
fn ns_home_directory_failure() IError { return unsafe { &ns_home_directory_failure_value } }

// Borrow a parent prefix without assuming there is a NUL after it. App paths
// use the existing bounded POSIX profile. Do not resolve symlinks, create
// directories or silently interpret relative paths as a host user's home.
fn ns_home_parent_checked(path string) !string {
	if path.len == 0 || path.len > 1023 || path[0] != `/` || !utf8.validate_str(path) { return ns_home_directory_failure() }
	mut start := 1
	for i in 1 .. path.len + 1 {
		if i < path.len && path[i] == 0 { return ns_home_directory_failure() }
		if i < path.len && path[i] != `/` { continue }
		length := i - start
		if (length == 1 && path[start] == `.`) || (length == 2 && path[start] == `.` && path[start + 1] == `.`) { return ns_home_directory_failure() }
		start = i + 1
	}
	mut end := path.len
	for end > 1 && path[end - 1] == `/` { end-- }
	for end > 1 && path[end - 1] != `/` { end-- }
	for end > 1 && path[end - 1] == `/` { end-- }
	return unsafe { tos(path.str, end) }
}

// Configuration is established before image initializers and worker threads.
// Read at most 1024 C-string bytes, avoiding an unbounded getenv clone on a
// repeated query. The caller holds the runtime lock through the result copy.
fn ns_home_documents_checked() !string {
	value := C.getenv(c'VINIX_IOS_DOCUMENTS')
	if value == unsafe { nil } { return '' }
	for i in 0 .. 1024 {
		if unsafe { *(&u8(value) + i) } == 0 { return unsafe { tos(&u8(value), i) } }
	}
	return ns_home_directory_failure()
}

// Native Foundation's no-argument C entry returns a +0 NSString in x0.
// Vinix uses the parent of its existing Documents override, otherwise the
// parent of the loaded bundle: the same container used by ns_search_paths.
// Each result owns copied bytes and is autoreleased on the calling thread.
fn ns_home_directory_checked() !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return ns_home_directory_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	documents := ns_home_documents_checked()!
	path := ns_home_parent_checked(if documents.len != 0 { documents } else { ios_runtime.bundle })!
	// Native standardizes its returned path. This bounded profile excludes
	// dot components and collapses redundant separators without filesystem I/O.
	scratch := u64(C.__builtin_alloca(1024))
	mut length := 0
	for byte in path {
		if byte == `/` && length > 0 && unsafe { *(&u8(scratch + u64(length - 1))) } == `/` { continue }
		unsafe { *(&u8(scratch + u64(length))) = byte }
		length++
	}
	return objc_autorelease(owned_string(unsafe { tos(&u8(scratch), length) }))
}
fn ns_home_directory() u64 { return ns_home_directory_checked() or { panic(err) } }
