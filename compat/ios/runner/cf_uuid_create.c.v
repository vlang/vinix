// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct CFUUIDCreateFailure {}
fn (_ &CFUUIDCreateFailure) msg() string { return 'iOS: unsupported CFUUID creation allocator or runtime lifetime' }
fn (_ &CFUUIDCreateFailure) code() int { return 1 }
__global cf_uuid_create_failure_value = CFUUIDCreateFailure{}
fn cf_uuid_create_failure() IError { return unsafe { &cf_uuid_create_failure_value } }

fn cf_uuid_create_checked(allocator u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return cf_uuid_create_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if allocator != 0 && allocator != cf_allocator_default() { return cf_uuid_create_failure() }
	// Obtain a complete version-4 value before publishing its owned object.
	// CFUUID has its own type; native CFUUID objects are not NSUUID instances.
	mut bytes := [16]u8{}
	darwin_uuid_generate(unsafe { &bytes[0] })
	object := objc_allocate(ios_runtime.names['VinixCFUUID'])
	mut header := obj_header(object)
	unsafe { C.memcpy(&header.uuid_bytes[0], &bytes[0], 16) }
	return object
}

// One allocator in x0, one owned reference returned in x0, no autorelease.
fn cf_uuid_create(allocator u64) u64 {
	return cf_uuid_create_checked(allocator) or { panic(err) }
}
