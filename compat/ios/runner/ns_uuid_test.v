// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.object_getClass(voidptr) voidptr
fn C.class_getInstanceSize(voidptr) usize
type UUIDSend = fn (u64, u64, u64) u64
struct UUIDApi { native bool send u64 cls u64 strings u64 }
fn (api UUIDApi) message(object u64, name &char, arg u64) u64 {
	mut selector := u64(name)
	$if macos { if api.native { selector = u64(C.sel_registerName(name)) } }
	return unsafe { UUIDSend(voidptr(api.send))(object, selector, arg) }
}
fn (api UUIDApi) string(value &char) u64 { return api.message(api.strings, c'stringWithUTF8String:', u64(value)) }
fn (api UUIDApi) text(object u64) string { return ctext(api.message(object, c'UTF8String', 0)) }
fn (api UUIDApi) release(object u64) { api.message(object, c'release', 0) }
fn (api UUIDApi) pool() u64 {
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0) } }
	return objc_pool_push()
}
fn (api UUIDApi) drain(pool u64) {
	$if macos { if api.native { api.release(pool); return } }
	objc_pool_pop(pool)
}
fn (api UUIDApi) parse(text &char) u64 { return api.message(api.message(api.cls, c'alloc', 0), c'initWithUUIDString:', api.string(text)) }

fn uuid_object_cases(api UUIDApi) {
	pool := api.pool()
	object := api.message(api.cls, c'alloc', 0)
	mut bytes := [16]u8{}
	api.message(object, c'getUUIDBytes:', u64(unsafe { &bytes[0] }))
	for byte in bytes { assert byte == 0 }
	$if macos { if api.native { assert C.class_getInstanceSize(C.object_getClass(unsafe { voidptr(object) })) == 24 } }
	assert api.message(object, c'classForCoder', 0) == api.cls
	for i in 0 .. 16 { bytes[i] = u8(i) }
	assert api.message(object, c'initWithUUIDBytes:', u64(unsafe { &bytes[0] })) == object
	for i in 0 .. 16 { bytes[i] = 255 }
	mut output := [32]u8{init: 0xa5}
	api.message(object, c'getUUIDBytes:', u64(unsafe { &output[8] }))
	for i in 0 .. 8 { assert output[i] == 0xa5 && output[i + 24] == 0xa5 }
	for i in 0 .. 16 { assert output[i + 8] == u8(i) }
	assert api.text(api.message(object, c'UUIDString', 0)) == '00010203-0405-0607-0809-0A0B0C0D0E0F'
	assert api.text(api.message(object, c'description', 0)) == '00010203-0405-0607-0809-0A0B0C0D0E0F'
	for selector in [c'copy', c'copyWithZone:']! { assert api.message(object, selector, 0) == object; api.release(object) }
	assert api.message(object, c'initWithUUIDBytes:', 0) == object
	assert api.text(api.message(object, c'UUIDString', 0)) == '00000000-0000-0000-0000-000000000000'
	for value in [c'e621e1f8-c36c-495a-93fc-0c247a3e6e5f', c'E621E1F8-C36C-495A-93FC-0C247A3E6E5F']! {
		parsed := api.parse(value); assert parsed != 0
		assert api.text(api.message(parsed, c'UUIDString', 0)) == 'E621E1F8-C36C-495A-93FC-0C247A3E6E5F'
		api.release(parsed)
	}
	for value in [c'', c'invalid', c'E621E1F8C36C495A93FC0C247A3E6E5F', c'{E621E1F8-C36C-495A-93FC-0C247A3E6E5F}', c'G621E1F8-C36C-495A-93FC-0C247A3E6E5F']! { assert api.parse(value) == 0 }
	assert api.message(api.message(api.cls, c'alloc', 0), c'initWithUUIDString:', 0) == 0
	a := api.parse(c'00000000-0000-0000-0000-000000000001'); b := api.parse(c'00000000-0000-0000-0000-000000000002')
	assert i64(api.message(a, c'compare:', b)) == -1 && i64(api.message(b, c'compare:', a)) == 1 && api.message(a, c'compare:', a) == 0
	assert api.message(a, c'isEqual:', b) == 0 && api.message(a, c'isEqual:', 0) == 0
	assert api.message(a, c'initWithUUIDString:', api.string(c'00000000-0000-0000-0000-000000000002')) == a
	assert api.message(a, c'isEqual:', b) == 1 && api.message(a, c'hash', 0) == api.message(b, c'hash', 0)
	api.release(a); api.release(b); api.release(object)
	mut seen := map[string]bool{}
	for index in 0 .. 256 {
		fresh := api.message(api.cls, if index & 1 == 0 { c'new' } else { c'UUID' }, 0)
		api.message(fresh, c'getUUIDBytes:', u64(unsafe { &bytes[0] }))
		assert bytes[6] >> 4 == 4 && bytes[8] >> 6 == 2
		key := api.text(api.message(fresh, c'UUIDString', 0)); assert key !in seen; seen[key.clone()] = true
		if index & 1 == 0 { api.release(fresh) }
	}
	api.drain(pool)
}

fn test_nsuuid_native_values() {
	$if macos {
		api := UUIDApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), cls: u64(C.objc_getClass(c'NSUUID')), strings: u64(C.objc_getClass(c'NSString'))}
		uuid_object_cases(api)
		println('IOS-NSUUID-NATIVE: concrete allocation, zero defaults, copied bytes, canonical parsing, immutable copy identity, reinitialization, comparisons and256 unique version4 values')
	}
}

fn test_nsuuid_runtime_values() {
	for _ in 0 .. 2 {
		objc_start()
		api := UUIDApi{send: u64(unsafe { voidptr(C.ios_objc_msgsend) }), cls: ios_runtime.names['NSUUID'], strings: ios_runtime.names['NSString']}
		assert runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', '_OBJC_CLASS_$_NSUUID')! == api.cls
		assert objc_class_size(api.cls) == 8 && objc_class_size(ios_runtime.names['_NSUUIDBridge']) == 8 && objc_class_size(ios_runtime.names['__NSConcreteUUID']) == 24
		assert objc_class_parent(ios_runtime.names['__NSConcreteUUID']) == ios_runtime.names['_NSUUIDBridge']
		uuid_object_cases(api); assert ios_runtime.live == 0
		pool := api.pool(); a := api.parse(c'00000000-0000-0000-0000-000000000001'); b := api.parse(c'00000000-0000-0000-0000-000000000001')
		assert object_equal(a, b) && cf_hash(a) == cf_hash(b)
		description := cf_copy_description(a); assert string_text(description) == '00000000-0000-0000-0000-000000000001'; objc_release(description)
		set := objc_new(ios_runtime.names['NSMutableSet']); ns_set_mutate(set, 'addObject:', a); ns_set_mutate(set, 'addObject:', b); assert obj_header(set).items.len == 1
		objc_release(set); api.release(a); api.release(b); api.drain(pool)
		mut storage := [24]u8{}
		caller := objc_construct_instance(ios_runtime.names['__NSConcreteUUID'], u64(unsafe { &storage[0] }))
		assert api.message(caller, c'initWithUUIDBytes:', 0) == caller
		assert objc_destruct_instance(caller) == caller
		for _ in 0 .. 100 { object := objc_new(api.cls); assert objc_set_class(object, ios_runtime.names['NSObject']) == ios_runtime.names['__NSConcreteUUID']; objc_release(object) }
		assert ios_runtime.live == 0 && ios_runtime.block_refs.len == 0
		objc_stop(); assert ios_runtime.live == 0
	}
	println('IOS-NSUUID: class-cluster metadata, collection equality/hash, copied descriptions, caller storage,100 isa changes and two zero-live-object shutdown cycles')
}

fn test_nsuuid_rejections() {
	objc_start(); cls := ios_runtime.names['NSUUID']
	for mode in ['output', 'compare', 'string-type', 'coding', 'mutable', 'subclass', 'abstract', 'caller-invalid']! {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			if mode == 'subclass' { sub := objc_allocate_class(cls, c'UUIDUnsupportedSubclass', 0); objc_register_class(sub); objc_new(sub) }
			api := UUIDApi{send: u64(unsafe { voidptr(C.ios_objc_msgsend) }), cls: cls, strings: ios_runtime.names['NSString']}
			mut object := u64(0)
			mut storage := [24]u8{}
			if mode in ['abstract', 'caller-invalid']! { object = objc_construct_instance(if mode == 'abstract' { cls } else { ios_runtime.names['__NSConcreteUUID'] }, u64(unsafe { &storage[0] })) }
			else { object = objc_new(cls) }
			match mode {
				'output' { api.message(object, c'getUUIDBytes:', 0) }
				'compare' { api.message(object, c'compare:', 0) }
				'string-type' { api.message(object, c'initWithUUIDString:', objc_new(ios_runtime.names['NSObject'])) }
				'coding' { api.message(object, c'encodeWithCoder:', 0) }
				'mutable' { api.message(object, c'mutableCopy', 0) }
				'abstract' { api.message(object, c'init', 0) }
				'caller-invalid' { api.message(object, c'initWithUUIDString:', 0) }
				else {}
			}
			C._exit(0)
		}
		C.close(fds[1]); mut buffer := [16384]u8{}; mut length := 0
		for { assert length < buffer.len; count := C.read(fds[0], unsafe { &buffer[length] }, usize(buffer.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&buffer[0], length) }
		reason := match mode { 'output' { 'UUID byte output must not be nil' } 'compare' { 'UUID comparison requires another UUID' } 'string-type' { 'UUID string initializer requires NSString' } 'subclass' { 'abstract or custom UUID subclass construction is not implemented' } 'abstract' { 'UUID operation requires concrete UUID storage' } 'caller-invalid' { 'invalid UUID initializer cannot consume caller-owned storage' } else { 'UUID coding and mutable copies are not implemented' } }
		assert output.contains('iOS: ' + reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output
	}
	assert ios_runtime.live == 0; objc_stop()
	println('IOS-NSUUID-REJECT: eight output/type/coding/mutability/subclass/abstract/caller-invalid cases fail explicitly')
}
