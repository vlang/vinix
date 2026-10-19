// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct CFUUIDTextFailure {}
fn (_ &CFUUIDTextFailure) msg() string { return 'iOS: unsupported CFUUID string conversion input, allocator or runtime lifetime' }
fn (_ &CFUUIDTextFailure) code() int { return 1 }
__global cf_uuid_text_failure_value = CFUUIDTextFailure{}
fn cf_uuid_text_failure() IError { return unsafe { &cf_uuid_text_failure_value } }

fn cf_uuid_create_string_checked(allocator u64, uuid u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return cf_uuid_text_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if allocator != 0 && allocator != cf_allocator_default() { return cf_uuid_text_failure() }
	// Prove provenance before reading any UUID memory. CFUUID and NSUUID
	// have distinct storage; neither nil nor an arbitrary isa is sufficient.
	header := ios_runtime.objects[uuid] or { return cf_uuid_text_failure() }
	if header.cls != ios_runtime.names['VinixCFUUID'] || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 { return cf_uuid_text_failure() }
	mut buffer := [36]u8{}
	mut position := 0
	for i in 0 .. 16 {
		if position in [8, 13, 18, 23]! { buffer[position] = `-`; position++ }
		byte := header.uuid_bytes[i]
		buffer[position] = '0123456789ABCDEF'[byte >> 4]
		buffer[position + 1] = '0123456789ABCDEF'[byte & 15]
		position += 2
	}
	// owned_string copies the complete stack buffer, without an autorelease.
	return owned_string(unsafe { tos(&buffer[0], 36) })
}

// Allocator/CFUUID in x0/x1; one owned CFString reference in x0.
fn cf_uuid_create_string(allocator u64, uuid u64) u64 {
	return cf_uuid_create_string_checked(allocator, uuid) or { panic(err) }
}
