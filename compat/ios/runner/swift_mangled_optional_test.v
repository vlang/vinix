// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr

type MoLookup = fn (u64, u64, u64, u64) u64
type MoState = fn (u64, u64, u64, u64, u64) u64
type MoAccess = fn (u64, u64) SwiftAssociatedMetadata
type MoCopy = fn (u64, u64, u64) u64
type MoInject = fn (u64, u32, u64)
type MoTag = fn (u64, u64) u32

struct MoApi {
	lookup MoLookup
	context2 MoLookup
	state MoState
	state2 MoState
	optional MoAccess
	array MoAccess
	integer u64
	text u64
	priority u64
	descriptor u64
}

fn mo_case(api MoApi, name string, context u64, args u64, expected u64) {
	assert api.lookup(u64(name.str), u64(name.len), context, args) == expected, name
	assert api.context2(u64(name.str), u64(name.len), context, args) == expected, name
	for request in [u64(0), 0x3f, 0xff, 0x100, 0x13f, 0x1ff]! {
		assert api.state(request, u64(name.str), u64(name.len), context, args) == expected, name
		assert api.state2(request, u64(name.str), u64(name.len), context, args) == expected, name
	}
}

fn mo_matrix(api MoApi) u64 {
	priority := api.optional(0, api.priority).metadata
	for name, metadata in {
		'ScPSg': priority,
		'ScPSgSg': api.optional(0, priority).metadata,
		'SSSg': api.optional(0, api.text).metadata,
		'SiSg': api.optional(0, api.integer).metadata,
		'SayScPSgG': api.array(0, priority).metadata,
		'SayScPGSg': api.optional(0, api.array(0, api.priority).metadata).metadata,
		'SaySayScPSgGSgGSg': api.optional(0, api.array(0, api.optional(0, api.array(0, priority).metadata).metadata).metadata).metadata,
		'ScPSg\x00junk': priority,
	} { mo_case(api, name, 0, 0, metadata) }
	mut args := [api.priority]!
	mo_case(api, 'xSg', api.descriptor, u64(unsafe { &args[0] }), priority)
	mo_case(api, 'SayxSgG', api.descriptor, u64(unsafe { &args[0] }), api.array(0, priority).metadata)
	mo_case(api, 'xSg', 0, 0, 0)
	mo_case(api, 'SayScPSg', 0, 0, 0)
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	defer { assert C.munmap(voidptr(span), page * 2) == 0 }
	assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_NONE) == 0
	name := span + u64(page) - 5
	C.memcpy(voidptr(name), c'ScPSg', 5)
	// No terminating NUL and both unused generic inputs are inaccessible.
	assert api.lookup(name, 5, span + u64(page), span + u64(page)) == priority
	assert api.context2(name, 5, span + u64(page), span + u64(page)) == priority
	assert api.state(0x1ff, name, 5, span + u64(page), span + u64(page)) == priority
	assert api.state2(0x1ff, name, 5, span + u64(page), span + u64(page)) == priority
	assert read64(priority) == 0x202 && read64(priority + 16) == api.priority
	witness := read64(priority - 8) & 0x0000ffffffffffff
	assert read64(witness + 64) == 2 && read64(witness + 72) == 2
	assert read32(witness + 84) == 0
	copy_value := unsafe { MoCopy(voidptr(read64(witness + 16) & 0x0000ffffffffffff)) }
	inject := unsafe { MoInject(voidptr(read64(witness + 104) & 0x0000ffffffffffff)) }
	tag := unsafe { MoTag(voidptr(read64(witness + 88) & 0x0000ffffffffffff)) }
	mut hash := u64(14695981039346656037)
	// TaskPriority? is exactly two bytes at a protected page boundary.
	value := span + u64(page) - 2
	for payload in [u8(0), 1, 9, 17, 21, 25, 255]! {
		for nil_value in [u32(0), 1]! {
			unsafe { *(&u8(value)) = payload; *(&u8(value + 1)) = 0x5a }
			inject(value, nil_value, priority)
			assert tag(value, priority) == nil_value
			mut destination := [u8(0x67), 0, 0, 0x89]!
			assert copy_value(u64(unsafe { &destination[1] }), value, priority) == u64(unsafe { &destination[1] })
			assert destination[0] == 0x67 && destination[3] == 0x89
			assert C.memcmp(unsafe { &destination[1] }, voidptr(value), 2) == 0
			for byte in destination { hash = (hash ^ u64(byte)) * u64(1099511628211) }
		}
	}
	return hash
}

fn mo_worker() u64 {
	mut metadata := u64(0)
	for _ in 0 .. 128 {
		result := swift_mangled_lookup(u64(c'ScPSg'), 5, 0, 0)
		if metadata != 0 { assert result == metadata }
		metadata = result
		assert swift_mangled_lookup(u64(c'SayScPSgG'), 9, 0, 0) == swift_array_access(0, metadata).metadata
	}
	return metadata
}

fn mo_reject(name string) {
	if _ := swift_mangled_lookup_checked(u64(name.str), u64(name.len), 0, 0) { assert false, name }
}

fn test_swift_mangled_optional() {
	mut native_hash := u64(0)
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		concurrency := C.dlopen(c'/usr/lib/swift/libswift_Concurrency.dylib', C.RTLD_NOW)
		assert core != unsafe { nil } && concurrency != unsafe { nil }
		api := MoApi{
			lookup: unsafe { MoLookup(C.dlsym(core, c'swift_getTypeByMangledNameInContext')) }
			context2: unsafe { MoLookup(C.dlsym(core, c'swift_getTypeByMangledNameInContext2')) }
			state: unsafe { MoState(C.dlsym(core, c'swift_getTypeByMangledNameInContextInMetadataState')) }
			state2: unsafe { MoState(C.dlsym(core, c'swift_getTypeByMangledNameInContextInMetadataState2')) }
			optional: unsafe { MoAccess(C.dlsym(core, c'$sSqMa')) }
			array: unsafe { MoAccess(C.dlsym(core, c'$sSaMa')) }
			integer: u64(C.dlsym(core, c'$sSiN')), text: u64(C.dlsym(core, c'$sSSN'))
			priority: u64(C.dlsym(concurrency, c'$sScPN')), descriptor: u64(C.dlsym(core, c'$sSaMn'))
		}
		native_hash = mo_matrix(api)
		println('IOS-SWIFT-OPTIONAL-LOOKUP-NATIVE: canonical Optional/Array order, TaskPriority byte witnesses, four lookup entries and guarded spans PASS')
	}
	for _ in 0 .. 2 {
		objc_start()
		// Reject the entire expression before publishing even the leaf metadata.
		for name in ['ScPSg?', 'ScPSgG', 'SayScPSgGG', 'ScPS', 'ScPSgSaySiG',
			'Say'.repeat(65) + 'ScP' + 'G'.repeat(65),
			'ScP' + 'Sg'.repeat(65), 'Say'.repeat(64) + 'ScP' + 'G'.repeat(64) + 'Sg'] { mo_reject(name) }
		assert ios_runtime.swift_task_priority_arena == 0 && ios_runtime.swift_optional_metadata.len == 0 && ios_runtime.swift_array_arena == 0
		for name in ['Say'.repeat(63) + 'ScPSg' + 'G'.repeat(63), 'ScP' + 'Sg'.repeat(64)] {
			parsed := swift_mangled_parse(u64(name.str), u64(name.len)) or { panic(err) }
			assert parsed.wrappers_count == 64
		}
		mut workers := []thread u64{}
		for _ in 0 .. 8 { workers << spawn mo_worker() }
		results := workers.wait()
		for metadata in results { assert metadata == results[0] }
		api := MoApi{lookup: swift_mangled_lookup, context2: swift_context2_lookup,
			state: swift_mangled_state_lookup, state2: swift_mangled_state2_lookup,
			optional: swift_optional_access, array: swift_array_access,
			integer: swift_integer_metadata(), text: swift_string_metadata(), priority: swift_task_priority_metadata(),
			descriptor: swift_array_arena() + u64(C.getpagesize()) + 160}
		hash := mo_matrix(api)
		if native_hash != 0 { assert hash == native_hash }
		assert ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.live == 0
		objc_stop()
		assert ios_runtime.swift_optional_metadata.len == 0 && ios_runtime.swift_optional_arena == 0
		assert ios_runtime.swift_array_metadata.len == 0 && ios_runtime.swift_task_priority_arena == 0
	}
	println('IOS-SWIFT-OPTIONAL-LOOKUP: canonical Optional/Array order, four lookup entries, TaskPriority byte witnesses, guarded spans, bounded nesting, rejection before allocation, eight publishers and two drained runtimes PASS')
}
