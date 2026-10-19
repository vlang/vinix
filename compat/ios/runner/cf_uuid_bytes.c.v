// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn cf_uuid_create_from_uuid_bytes_checked(allocator u64, first u64, second u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return cf_uuid_create_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if allocator != 0 && allocator != cf_allocator_default() { return cf_uuid_create_failure() }
	object := objc_allocate(ios_runtime.names['VinixCFUUID'])
	mut header := obj_header(object)
	// The by-value CFUUIDBytes occupies x1/x2 on ARM64. Copy its bits in
	// register order, including zero/nonstandard version and variant bits.
	unsafe {
		C.memcpy(&header.uuid_bytes[0], &first, 8)
		C.memcpy(&header.uuid_bytes[8], &second, 8)
	}
	return object
}

// Allocator in x0, sixteen inline bytes in x1/x2, owned CFUUID in x0.
fn cf_uuid_create_from_uuid_bytes(allocator u64, first u64, second u64) u64 {
	return cf_uuid_create_from_uuid_bytes_checked(allocator, first, second) or { panic(err) }
}
