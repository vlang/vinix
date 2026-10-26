// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct NSSearchPathsFailure {}
fn (_ &NSSearchPathsFailure) msg() string { return 'iOS: unsupported Foundation search path/domain' }
fn (_ &NSSearchPathsFailure) code() int { return 1 }
__global ns_search_paths_failure_value = NSSearchPathsFailure{}
fn ns_search_paths_failure() IError { return unsafe { &ns_search_paths_failure_value } }

// Application-container profile of NSSearchPathForDirectoriesInDomains.
// Querying paths performs no filesystem operations, as on Foundation. Keep
// the Documents override and NSHomeDirectory on the same container convention.
fn ns_search_paths_checked(directory u64, domain u64, expand bool) !u64 {
	if domain != 1 || directory !in [u64(5), 9, 13, 14]!
		|| ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return ns_search_paths_failure()
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	documents := ns_home_documents_checked()!
	parent := ns_home_parent_checked(if documents.len != 0 { documents } else { ios_runtime.bundle })!
	suffix := match directory {
		5 { '/Library' }
		9 { '/Documents' }
		13 { '/Library/Caches' }
		else { '/Library/Application Support' }
	}
	// The input can be a non-NUL-terminated borrowed prefix. Build into a
	// bounded stack buffer and let NSString copy it before returning.
	base := if !expand { '~' } else if directory == 9 && documents.len != 0 { documents } else { parent }
	ending := if expand && directory == 9 && documents.len != 0 { '' } else { suffix }
	if base.len + ending.len > 1023 { return ns_search_paths_failure() }
	scratch := u64(C.__builtin_alloca(1024))
	mut length := 0
	for part in [base, ending]! {
		for byte in part {
			if byte == `/` && length > 0 && unsafe { *(&u8(scratch + u64(length - 1))) } == `/` { continue }
			unsafe { *(&u8(scratch + u64(length))) = byte }
			length++
		}
	}
	for length > 1 && unsafe { *(&u8(scratch + u64(length - 1))) } == `/` { length-- }
	path := owned_string(unsafe { tos(&u8(scratch), length) })
	array := objc_allocate(ios_runtime.names['NSArray'])
	mut header := obj_header(array)
	array_append(mut header, path)
	objc_release(path)
	if ios_runtime.trace {
		C.printf(c'iOS: search path directory=%llu domain=%llu expand=%d: %.*s\n', directory, domain, int(expand), length, &u8(scratch))
	}
	return objc_autorelease(array)
}

fn ns_search_paths(directory u64, domain u64, expand bool) u64 {
	return ns_search_paths_checked(directory, domain, expand) or { panic(err) }
}
