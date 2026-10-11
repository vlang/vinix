// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFError.h>
	#include <CoreFoundation/CFString.h>
	#include <CoreFoundation/CFDictionary.h>
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFStringCreateWithBytes(voidptr, &u8, i64, u32, bool) voidptr
fn C.CFErrorCreate(voidptr, voidptr, i64, voidptr) voidptr
fn C.CFErrorGetDomain(voidptr) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRetain(voidptr) voidptr
fn C.CFRelease(voidptr)
fn C.CFDictionaryCreateMutable(voidptr, i64, voidptr, voidptr) voidptr
fn C.CFDictionarySetValue(voidptr, voidptr, voidptr)
fn C.CFDictionaryGetCount(voidptr) i64
fn C.CFDictionaryGetValue(voidptr, voidptr) voidptr
fn C.object_getClass(voidptr) voidptr
fn C.objc_getClass(&char) voidptr

type ValueGet = fn (u64, &u64, &SwiftErrorValue)
type ValueMetadata = fn (u64) u64
type ValueRelease = fn (u64)
type ValueUTF8 = fn (u64, u64) u64
type ValueWitness = fn (u64, u64, u64) u64
type ValueDestroy = fn (u64, u64)
type ValueEnumGet = fn (u64, u32, u64) u32
type ValueEnumStore = fn (u64, u32, u32, u64)
type ValueGetterProbe = fn (u64, u64, u64, u64, &u64) SwiftStringWords
type ValueGetProbe = fn (u64, &u64, &SwiftErrorValue, u64, &u64)

struct ValueApi {
	native bool
	protocol u64
	requirements [4]u64
	@[required]
	get ValueGet
	@[required]
	metadata ValueMetadata
	@[required]
	bridge_release ValueRelease
	@[required]
	utf8 ValueUTF8
	@[required]
	getter ValueGetterProbe
	@[required]
	get_probe ValueGetProbe
}

fn value_api(native bool, code u64) ValueApi {
	mut entries := [5]u64{}
	for i, name in ['_swift_getErrorValue', '_swift_getObjCClassMetadata', '_$ss5ErrorMp',
		'_swift_bridgeObjectRelease', '_$sSS11utf8CStrings15ContiguousArrayVys4Int8VGvg']! {
		if native {
			library := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
			assert library != unsafe { nil }
			entries[i] = u64(C.dlsym(library, name[1..].str))
		} else { entries[i] = runtime_symbol('/usr/lib/swift/libswiftCore.dylib', name) or { panic(err) } }
		assert entries[i] != 0
	}
	mut requirements := [4]u64{}
	for i, name in ['_$ss5ErrorP7_domainSSvgTq', '_$ss5ErrorP5_codeSivgTq',
		'_$ss5ErrorP9_userInfoyXlSgvgTq', '_$ss5ErrorP19_getEmbeddedNSErroryXlSgyFTq']! {
		if native {
			library := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
			requirements[i] = u64(C.dlsym(library, name[1..].str))
		} else { requirements[i] = runtime_symbol('/usr/lib/swift/libswiftCore.dylib', name) or { panic(err) } }
		assert requirements[i] != 0
	}
	return ValueApi{ native: native, protocol: entries[2], requirements: requirements, get: unsafe { ValueGet(voidptr(entries[0])) },
		metadata: unsafe { ValueMetadata(voidptr(entries[1])) }, bridge_release: unsafe { ValueRelease(voidptr(entries[3])) },
		utf8: unsafe { ValueUTF8(voidptr(entries[4])) }, getter: unsafe { ValueGetterProbe(voidptr(code)) },
		get_probe: unsafe { ValueGetProbe(voidptr(code + 64)) } }
}
fn (api ValueApi) text(text string) u64 {
	$if macos {
		if api.native { return u64(C.CFStringCreateWithBytes(unsafe { nil }, text.str, i64(text.len), 0x08000100, false)) }
	}
	return owned_string(text)
}
fn (api ValueApi) release(owner u64) {
	$if macos { if api.native { C.CFRelease(unsafe { voidptr(owner) }); return } }
	objc_release(owner)
}
fn (api ValueApi) retain(owner u64) {
	$if macos { if api.native { assert u64(C.CFRetain(unsafe { voidptr(owner) })) == owner; return } }
	assert objc_retain(owner) == owner
}
fn (api ValueApi) refs(owner u64) i64 {
	$if macos { if api.native { return C.CFGetRetainCount(unsafe { voidptr(owner) }) } }
	return obj_header(owner).refs
}
fn (api ValueApi) cls(owner u64) u64 {
	$if macos { if api.native { return u64(C.object_getClass(unsafe { voidptr(owner) })) } }
	return read64(owner)
}
fn (api ValueApi) domain(owner u64) u64 {
	$if macos { if api.native { return u64(C.CFErrorGetDomain(unsafe { voidptr(owner) })) } }
	return cf_error_domain(owner)
}
fn (api ValueApi) make(text string, code i64, info bool) u64 {
	domain := api.text(text)
	mut dictionary := u64(0)
	if info {
		key := api.text('VinixErrorTestKey')
		item := api.text('owned user info')
		$if macos {
			if api.native {
				dictionary = u64(C.CFDictionaryCreateMutable(unsafe { nil }, 0,
					unsafe { &C.kCFTypeDictionaryKeyCallBacks }, unsafe { &C.kCFTypeDictionaryValueCallBacks }))
				C.CFDictionarySetValue(unsafe { voidptr(dictionary) }, unsafe { voidptr(key) }, unsafe { voidptr(item) })
			}
		}
		if !api.native {
			dictionary = cf_dictionary_mutable(0, 0, cf_callbacks_constant('_kCFTypeDictionaryKeyCallBacks'), cf_callbacks_constant('_kCFTypeDictionaryValueCallBacks'))
			cf_dictionary_set(dictionary, key, item)
			objc_set_class(dictionary, ios_runtime.names['NSDictionary'])
		}
		api.release(key); api.release(item)
	}
	$if macos {
		if api.native {
			owner := u64(C.CFErrorCreate(unsafe { nil }, unsafe { voidptr(domain) }, code, unsafe { voidptr(dictionary) }))
			api.release(domain); if dictionary != 0 { api.release(dictionary) }
			assert owner != 0
			return owner
		}
	}
	owner := objc_allocate(cf_error_type_id())
	mut header := obj_header(owner)
	header.number = code; header.fields[0] = domain; header.fields[1] = dictionary
	return owner
}

fn value_relative(field u64) u64 { return u64(i64(field) + i64(unsafe { *(&i32(field)) })) }
fn value_layout(api ValueApi, value SwiftErrorValue) {
	assert read64(value.metadata) == 0x305
	witness := read64(value.metadata - 8)
	assert read64(witness + 64) == 8 && read64(witness + 72) == 8
	assert unsafe { *(&u32(witness + 80)) } == 0x10007 && unsafe { *(&u32(witness + 84)) } == 0x7fffffff
	assert unsafe { *(&u32(api.protocol)) } == 0x70043 && unsafe { *(&u32(api.protocol + 12)) } == 0
	assert unsafe { *(&u32(api.protocol + 16)) } == 4 && unsafe { *(&u32(api.protocol + 20)) } == 0
	assert unsafe { (&u8(value_relative(api.protocol + 8))).vstring() } == 'Error'
	for i in 0 .. 4 {
		assert api.requirements[i] == api.protocol + 24 + u64(i * 8)
		assert unsafe { *(&u32(api.requirements[i])) } & 0xffff == if i == 3 { u32(0x11) } else { u32(0x13) }
	}
	if !api.native {
		conformance := read64(value.witness)
		assert value_relative(conformance) == api.protocol && unsafe { *(&u32(conformance + 12)) } == 0x18
		assert read64(value_relative(conformance + 4)) == cf_error_type_id()
		assert value_relative(conformance + 8) == value.witness
	}
}
fn value_string(api ValueApi, words SwiftStringWords, text string) {
	array := api.utf8(words.first, words.second)
	assert read64(array + 16) == u64(text.len + 1)
	assert C.memcmp(unsafe { voidptr(array + 32) }, text.str, usize(text.len)) == 0
	assert unsafe { *(&u8(array + 32 + u64(text.len))) } == 0
	api.bridge_release(array)
}
fn value_call(api ValueApi, value SwiftErrorValue, index int) SwiftStringWords {
	mut context := u64(0)
	result := api.getter(value.value, value.metadata, value.witness,
		read64(value.witness + u64(index * 8)) & 0x0000ffffffffffff, unsafe { &context })
	assert context == value.value
	return result
}
fn value_case(api ValueApi, text string, code i64, info bool) {
	owner := api.make(text, code, info)
	before := api.refs(owner)
	mut scratch := [u64(0x11223344), 0xdeadbeef, 0x55667788]!
	mut output := [u64(0x11223344), 0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0x55667788]!
	result := unsafe { &SwiftErrorValue(&output[1]) }
	mut context := [2]u64{}
	for mode in 0 .. 2 {
		if mode == 0 { api.get(owner, unsafe { &scratch[1] }, result) }
		else {
			api.get_probe(owner, unsafe { &scratch[1] }, result, u64(unsafe { voidptr(api.get) }), unsafe { &context[0] })
			assert context[0] == 0x5020 && context[1] == 0x5021
		}
		assert scratch[0] == 0x11223344 && scratch[2] == 0x55667788 && output[0] == 0x11223344 && output[4] == 0x55667788
		assert scratch[1] == owner && result.value == u64(unsafe { &scratch[1] }) && api.refs(owner) == before
		assert result.metadata == api.metadata(api.cls(owner)) && read64(result.metadata + 8) == api.cls(owner)
	}
	value_layout(api, unsafe { *result })
	domain := value_call(api, unsafe { *result }, 1)
	assert i64(value_call(api, unsafe { *result }, 2).first) == code
	user_info := value_call(api, unsafe { *result }, 3).first
	assert user_info != 0
	mut count := i64(0)
	$if macos { if api.native { count = C.CFDictionaryGetCount(unsafe { voidptr(user_info) }) } }
	if !api.native { count = cf_array_count(user_info) }
	assert count == if info { i64(1) } else { i64(0) }
	embedded := value_call(api, unsafe { *result }, 4).first
	assert embedded == owner && api.refs(owner) == before + 1
	api.release(embedded)
	api.release(owner)
	// Both getter results remain owned after the error's final destruction.
	value_string(api, domain, text)
	api.bridge_release(domain.second)
	if info {
		key := api.text('VinixErrorTestKey')
		mut item := u64(0)
		$if macos { if api.native { item = u64(C.CFDictionaryGetValue(unsafe { voidptr(user_info) }, unsafe { voidptr(key) })) } }
		if !api.native { item = cf_dictionary_value(user_info, key); assert string_text(item) == 'owned user info' }
		assert item != 0
		api.release(key)
	}
	api.release(user_info)
}
fn value_worker(api ValueApi, owner u64) {
	for _ in 0 .. 1000 {
		mut scratch := u64(0); mut result := SwiftErrorValue{}
		api.get(owner, unsafe { &scratch }, unsafe { &result })
		assert result.metadata == api.metadata(api.cls(owner)) && i64(value_call(api, result, 2).first) == -26275
	}
}

struct ValueReentry {
	destination u64
	expected u64
	metadata u64
mut:
	calls int
}
fn value_reentry_reader(state &ValueReentry) {
	assert read64(state.destination) == state.expected
	mut temporary := u64(0)
	assert swift_objc_value_copy(u64(unsafe { &temporary }), state.destination, state.metadata) == u64(unsafe { &temporary })
	assert temporary == state.expected && swift_objc_metadata(read64(temporary)) == state.metadata
	swift_objc_value_destroy(u64(unsafe { &temporary }), state.metadata)
}
fn value_reentry_dealloc(owner u64, _selector &char) {
	mut state := unsafe { &ValueReentry(obj_header(owner).tag) }
	assert state.calls == 0 && read64(state.destination) == state.expected
	// The worker copies the published owner and resolves its metadata while
	// dealloc waits, proving assignment invokes destruction without the lock.
	worker := spawn value_reentry_reader(state)
	worker.wait()
	state.calls++
}
fn value_reentry(api ValueApi) {
	cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixSwiftObjCValueReentry', 0)
	assert cls != 0
	objc_register_class(cls)
	objc_replace_method(cls, objc_selector(c'dealloc'), u64(unsafe { voidptr(value_reentry_dealloc) }), c'v16@0:8')
	metadata := api.metadata(ios_runtime.names['NSObject'])
	for index in [3, 5]! {
		mut source := objc_allocate(ios_runtime.names['NSObject'])
		mut destination := objc_allocate(cls)
		state := unsafe { &ValueReentry(C.__builtin_alloca(sizeof(ValueReentry))) }
		unsafe { *state = ValueReentry{ destination: u64(&destination), expected: source, metadata: metadata } }
		mut header := obj_header(destination)
		header.tag = i64(state)
		if index == 5 { objc_retain(source) }
		assign := unsafe { ValueWitness(voidptr(read64(read64(metadata - 8) + u64(index * 8)))) }
		assert assign(u64(unsafe { &destination }), u64(unsafe { &source }), metadata) == u64(unsafe { &destination })
		assert state.calls == 1 && destination == source && obj_header(source).refs == 2
		objc_release(destination); objc_release(source)
	}
}
fn value_metadata_worker(api ValueApi, cls u64) u64 { return api.metadata(cls) }
fn value_metadata_concurrent(api ValueApi) {
	cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixSwiftObjCMetadataConcurrent', 0)
	assert cls != 0
	if _ := swift_objc_metadata_checked(cls) { assert false } // Unregistered classes cannot publish metadata.
	objc_register_class(cls)
	mut workers := []thread u64{}
	for _ in 0 .. 8 { workers << spawn value_metadata_worker(api, cls) }
	values := workers.wait()
	for metadata in values { assert metadata == values[0] && read64(metadata + 8) == cls }
	assert ios_runtime.swift_objc_metadata[cls] == values[0]
	// A Swift class uses its existing metadata address point rather than a
	// foreign wrapper. The artificial class only exercises the flag branch.
	swift_cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixSwiftClassMetadataFlagTest', 0)
	objc_register_class(swift_cls)
	unsafe { *(&u64(swift_cls + 32)) = 2 }
	assert api.metadata(swift_cls) == swift_cls && swift_cls !in ios_runtime.swift_objc_metadata
	objc_dispose_class(swift_cls)
}
fn value_witnesses(api ValueApi) {
	owner := api.make('VWT owner', 1, false)
	metadata := api.metadata(api.cls(owner)); table := read64(metadata - 8)
	mut source := owner; mut destination := u64(0)
	for index in [0, 2]! {
		initialize := unsafe { ValueWitness(voidptr(read64(table + u64(index * 8)) & 0x0000ffffffffffff)) }
		assert initialize(u64(unsafe { &destination }), u64(unsafe { &source }), metadata) == u64(unsafe { &destination })
		assert destination == owner && api.refs(owner) == 2
		destroy := unsafe { ValueDestroy(voidptr(read64(table + 8) & 0x0000ffffffffffff)) }
		destroy(u64(unsafe { &destination }), metadata)
		assert api.refs(owner) == 1
	}
	self_assign := unsafe { ValueWitness(voidptr(read64(table + 24) & 0x0000ffffffffffff)) }
	assert self_assign(u64(unsafe { &source }), u64(unsafe { &source }), metadata) == u64(unsafe { &source })
	assert source == owner && api.refs(owner) == 1
	for index in [3, 5]! {
		old := api.make('old owned error domain', 0, false)
		domain := api.domain(old); api.retain(domain); refs := api.refs(domain)
		destination = old
		if index == 5 { api.retain(owner) } // The moved source owns its reference.
		assign := unsafe { ValueWitness(voidptr(read64(table + u64(index * 8)) & 0x0000ffffffffffff)) }
		assert assign(u64(unsafe { &destination }), u64(unsafe { &source }), metadata) == u64(unsafe { &destination })
		assert destination == owner && api.refs(owner) == 2 && api.refs(domain) == refs - 1
		api.release(domain); api.release(destination)
	}
	take := unsafe { ValueWitness(voidptr(read64(table + 32) & 0x0000ffffffffffff)) }
	assert take(u64(unsafe { &destination }), u64(unsafe { &source }), metadata) == u64(unsafe { &destination })
	assert destination == owner && api.refs(owner) == 1
	get := unsafe { ValueEnumGet(voidptr(read64(table + 48) & 0x0000ffffffffffff)) }
	store := unsafe { ValueEnumStore(voidptr(read64(table + 56) & 0x0000ffffffffffff)) }
	for bits in [u64(0), 1, 0xfff, 0x1000, 0x7fffffff, 0x80000000, 0xffffffff, 0x100000000, owner]! {
		mut value := bits
		assert get(u64(unsafe { &value }), 1, metadata) == if bits >> 32 == 0 { u32(bits) + 1 } else { u32(0) }
	}
	for index in [u32(0), 1, 2, 0x7fffffff]! {
		mut value := owner
		store(u64(unsafe { &value }), index, 0x7fffffff, metadata)
		assert value == if index == 0 { owner } else { u64(index - 1) }
	}
	api.release(destination)
}
fn value_suite(api ValueApi) {
	assert api.metadata(0) == 0
	for text in ['', 'Fortnite', 'a\x00b', 'NSOSStatusErrorDomain', 'long owned Unicode error domain é 🎮']! {
		for code in [i64(-26275), 0, 1, 0x7fffffff]! { value_case(api, text, code, code == 1) }
	}
	value_witnesses(api)
	owner := api.make('shared owner', -26275, false)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn value_worker(api, owner) }
	workers.wait()
	assert api.refs(owner) == 1
	api.release(owner)
	if !api.native {
		value_reentry(api)
		value_metadata_concurrent(api)
		mut scratch := u64(0x1234); mut result := SwiftErrorValue{ value: 1, metadata: 2, witness: 3 }
		for invalid in [u64(0), 1, 0xdeadbeef]! {
			if _ := swift_error_value_checked(invalid, unsafe { &scratch }, unsafe { &result }) { assert false }
		}
		assert scratch == 0x1234 && result.value == 1 && result.metadata == 2 && result.witness == 3
		other := objc_allocate(ios_runtime.names['NSObject'])
		if _ := swift_error_value_checked(other, unsafe { &scratch }, unsafe { &result }) { assert false }
		if _ := swift_error_value_checked(other, unsafe { nil }, unsafe { &result }) { assert false }
		assert scratch == 0x1234 && result.value == 1
		objc_release(other)
		valid := api.make('invalid buffers', 0, false)
		if _ := swift_error_value_checked(valid, unsafe { nil }, unsafe { &result }) { assert false }
		if _ := swift_error_value_checked(valid, unsafe { &scratch }, unsafe { nil }) { assert false }
		if _ := swift_error_value_checked(valid, unsafe { &u64(u64(&scratch) + 1) }, unsafe { &result }) { assert false }
		if _ := swift_error_value_checked(valid, unsafe { &scratch }, unsafe { &SwiftErrorValue(u64(&result) + 1) }) { assert false }
		assert scratch == 0x1234 && result.value == 1 && result.metadata == 2 && result.witness == 3
		api.release(valid)
		if _ := swift_objc_metadata_checked(0) { assert false }
		if _ := swift_objc_metadata_checked(read64(cf_error_type_id())) { assert false }
		for name in ['NSObject', 'NSString', 'NSDictionary']! {
			cls := ios_runtime.names[name]; metadata := api.metadata(cls)
			assert read64(metadata) == 0x305 && read64(metadata + 8) == cls && api.metadata(cls) == metadata
		}
	}
}
fn test_swift_error_value() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	for i, op in [u32(0xa9be7bfd), 0xa90153f3, 0xaa0403f3, 0xaa0003f4, 0xaa0303f0,
		0xaa0103e0, 0xaa0203e1, 0xd63f0200, 0xf9000274, 0xa94153f3, 0xa8c27bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0403f3, 0xaa0303f0,
		0xd28a0414, 0xd28a0435, 0xd63f0200, 0xa9005674, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! { write32(code + 64 + u64(i * 4), op) }
	C.__builtin___clear_cache(unsafe { voidptr(code) }, unsafe { voidptr(code + 116) })
	assert C.mprotect(unsafe { voidptr(code) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		value_suite(value_api(true, code))
		println('IOS-SWIFT-ERROR-VALUE-NATIVE: genuine CFError extraction, canonical ObjC wrapper metadata, ordinary C extraction, complete Error witnesses, owned getter results, pointer VWT and concurrent borrowed calls')
	}
	for _ in 0 .. 2 {
		objc_start()
		value_suite(value_api(false, code))
		arena := ios_runtime.swift_error_arena
		metadata := swift_objc_metadata(cf_error_type_id())
		assert arena != 0 && ios_runtime.live == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0
		objc_stop()
		assert ios_runtime.swift_error_arena == 0 && ios_runtime.swift_objc_metadata.len == 0
		assert C.mprotect(unsafe { voidptr(arena) }, page, C.PROT_READ) == -1
		assert C.mprotect(unsafe { voidptr(metadata - 8) }, page, C.PROT_READ) == -1
	}
	assert C.munmap(unsafe { voidptr(code) }, page) == 0
	println('IOS-SWIFT-ERROR-VALUE: native CFError extraction differential, canonical real ObjC metadata, all four usable Error witnesses, owned domain/userInfo/embedded results, pointer value ownership, unlocked reentrant assignment, eight concurrent metadata publishers, guarded destinations, preserved contexts, eight borrowed workers, explicit unsupported owners and two drained/unmapped cycles')
}
