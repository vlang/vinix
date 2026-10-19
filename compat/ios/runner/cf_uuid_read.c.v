// SPDX-License-Identifier: GPL-2.0-or-later
module main

// A 16-byte integer aggregate has the native CFUUIDBytes return ABI on ARM64:
// its first/second eight bytes occupy x0/x1, without an indirect x8 result.
struct CFUUIDWords {
	first u64
	second u64
}

struct CFUUIDReadFailure {}
fn (_ &CFUUIDReadFailure) msg() string { return 'iOS: unsupported CFUUID byte extraction input or runtime lifetime' }
fn (_ &CFUUIDReadFailure) code() int { return 1 }
__global cf_uuid_read_failure_value = CFUUIDReadFailure{}
fn cf_uuid_read_failure() IError { return unsafe { &cf_uuid_read_failure_value } }

fn cf_uuid_get_uuid_bytes_checked(uuid u64) !CFUUIDWords {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return cf_uuid_read_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := ios_runtime.objects[uuid] or { return cf_uuid_read_failure() }
	if header.cls != ios_runtime.names['VinixCFUUID'] || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 { return cf_uuid_read_failure() }
	mut value := CFUUIDWords{}
	unsafe { C.memcpy(&value, &header.uuid_bytes[0], 16) }
	return value
}

// One CFUUID in x0; an independent 16-byte value returned in x0/x1.
fn cf_uuid_get_uuid_bytes(uuid u64) CFUUIDWords {
	return cf_uuid_get_uuid_bytes_checked(uuid) or { panic(err) }
}
