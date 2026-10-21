// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftErrorUserInfoFailure {}
fn (_ &SwiftErrorUserInfoFailure) msg() string { return 'iOS: unsupported or inactive Swift Error default userInfo' }
fn (_ &SwiftErrorUserInfoFailure) code() int { return 1 }
__global swift_error_user_info_failure_value = SwiftErrorUserInfoFailure{}
fn swift_error_user_info_failure() IError { return unsafe { &swift_error_user_info_failure_value } }
fn swift_error_user_info_active() ! {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return swift_error_user_info_failure()
	}
}

// Native forwards through Foundation's generic default-userInfo helper. For
// the existing concrete CFError and _MergeError conformances it returns an
// owned empty NSDictionary, even if CFError's concrete userInfo is nonempty.
// General value errors, LocalizedError/CustomNSError/RecoverableError and
// Swift boxes need protocol discovery and property dispatch, not this fallback.
fn swift_error_user_info_checked(source u64, metadata u64, table u64) !u64 {
	swift_error_user_info_active()!
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	swift_error_user_info_active()!
	if ios_runtime.swift_error_arena == 0 { return swift_error_user_info_failure() }
	page := u64(C.getpagesize())
	merge := ios_runtime.swift_merge_error_metadata_arena
	if merge != 0 && metadata == merge + page + 16 && table == merge + page + 320 {
		if ios_runtime.swift_merge_error_metadata_retired { return swift_error_user_info_failure() }
		// This enum's zero-sized Self has no bytes to read, copy or retain.
		return objc_allocate(ios_runtime.names['NSDictionary'])
	}
	known := ios_runtime.swift_objc_metadata[cf_error_type_id()] or { return swift_error_user_info_failure() }
	if metadata != known || table != ios_runtime.swift_error_arena + page + 160 {
		return swift_error_user_info_failure()
	}
	// The caller borrows one readable reference word. Check the canonical
	// metadata/table before touching it, then require a live registered owner.
	if source == 0 || source & 7 != 0 || source > ~u64(0) - 7 { return swift_error_user_info_failure() }
	owner := read64(source)
	header := ios_runtime.objects[owner] or { return swift_error_user_info_failure() }
	if header.cls != cf_error_type_id() || C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 {
		return swift_error_user_info_failure()
	}
	return objc_allocate(ios_runtime.names['NSDictionary'])
}
fn swift_error_user_info(source u64, metadata u64, table u64) u64 {
	return swift_error_user_info_checked(source, metadata, table) or { panic(err) }
}
fn swift_error_user_info_emit(code u64) {
	write32(code, 0xaa0103e2) // Swift x1 table -> C x2
	write32(code + 4, 0xaa0003e1) // Swift x0 metadata -> C x1
	write32(code + 8, 0xaa1403e0) // Swift x20 Self -> C x0
	write32(code + 12, 0x58000070)
	write32(code + 16, 0xd61f0200)
	write32(code + 20, 0xd503201f)
	unsafe { *(&u64(code + 24)) = u64(voidptr(swift_error_user_info)) }
}
fn swift_error_user_info_entry() !u64 {
	$if !arm64 { return swift_error_user_info_failure() }
	swift_error_user_info_active()!
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	swift_error_user_info_active()!
	return swift_error_metadata_arena() + 224
}
