// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFError.h>
	#include <CoreFoundation/CFString.h>
	#include <CoreFoundation/CFDictionary.h>
}
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFStringCreateWithBytes(voidptr, &u8, i64, u32, bool) voidptr
fn C.CFErrorCreate(voidptr, voidptr, i64, voidptr) voidptr
fn C.CFDictionaryCreateMutable(voidptr, i64, voidptr, voidptr) voidptr
fn C.CFDictionarySetValue(voidptr, voidptr, voidptr)
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRelease(voidptr)
type DescribeExtract = fn (u64, &u64, &SwiftErrorValue)
type DescribeBytes = fn (u64, u64) u64
type DescribeRelease = fn (u64)
type DescribeProbe = fn (u64, u64, u64, u64, &u64) SwiftStringWords
struct DescribeApi {
	native bool
	extract DescribeExtract
	bytes DescribeBytes
	release DescribeRelease
	probe DescribeProbe
	entry u64
}
fn describe_api(native bool, probe u64, framework bool) DescribeApi {
	library := if framework { '/System/Library/Frameworks/Foundation.framework/Foundation' } else { '/usr/lib/swift/libswiftFoundation.dylib' }
	if native {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		foundation := C.dlopen(library.str, C.RTLD_NOW)
		assert core != unsafe { nil } && foundation != unsafe { nil }
		return DescribeApi{ native: true
			extract: unsafe { DescribeExtract(C.dlsym(core, c'swift_getErrorValue')) }
			bytes: unsafe { DescribeBytes(C.dlsym(core, c'$sSS11utf8CStrings15ContiguousArrayVys4Int8VGvg')) }
			release: unsafe { DescribeRelease(C.dlsym(core, c'swift_bridgeObjectRelease')) }
			probe: unsafe { DescribeProbe(voidptr(probe)) }
			entry: u64(C.dlsym(foundation, c'$ss5ErrorP10FoundationE20localizedDescriptionSSvg'))
		}
	}
	return DescribeApi{
		extract: swift_error_value
		bytes: swift_string_utf8_cstring
		release: swift_bridge_release
		probe: unsafe { DescribeProbe(voidptr(probe)) }
		entry: runtime_symbol(library, '_$ss5ErrorP10FoundationE20localizedDescriptionSSvg') or { panic(err) }
	}
}
fn (api DescribeApi) text(value string) u64 {
	$if macos { if api.native { return u64(C.CFStringCreateWithBytes(unsafe { nil }, value.str, i64(value.len), 0x08000100, false)) } }
	return owned_string(value)
}
fn (api DescribeApi) drop(owner u64) {
	$if macos { if api.native { C.CFRelease(unsafe { voidptr(owner) }); return } }
	objc_release(owner)
}
fn (api DescribeApi) refs(owner u64) i64 {
	$if macos { if api.native { return C.CFGetRetainCount(unsafe { voidptr(owner) }) } }
	return obj_header(owner).refs
}
fn (api DescribeApi) make(domain string, code i64, mask u32, fields [5]string) u64 {
	name := api.text(domain); mut info := u64(0)
	if mask != 0 {
		$if macos { if api.native { info = u64(C.CFDictionaryCreateMutable(unsafe { nil }, 0,
			unsafe { &C.kCFTypeDictionaryKeyCallBacks }, unsafe { &C.kCFTypeDictionaryValueCallBacks })) } }
		if !api.native { info = cf_dictionary_mutable(0, 0, cf_callbacks_constant('_kCFTypeDictionaryKeyCallBacks'), cf_callbacks_constant('_kCFTypeDictionaryValueCallBacks')) }
		for index, key_name in ['NSLocalizedDescription', 'NSLocalizedFailure', 'NSLocalizedFailureReason', 'NSDescription', 'NSLocalizedRecoverySuggestion']! {
			if mask & (u32(1) << index) == 0 { continue }
			key := api.text(key_name); value := api.text(fields[index])
			$if macos { if api.native { C.CFDictionarySetValue(unsafe { voidptr(info) }, unsafe { voidptr(key) }, unsafe { voidptr(value) }) } }
			if !api.native { cf_dictionary_set(info, key, value) }
			api.drop(key); api.drop(value)
		}
		if !api.native { objc_set_class(info, ios_runtime.names['NSDictionary']) }
	}
	$if macos { if api.native {
		owner := u64(C.CFErrorCreate(unsafe { nil }, unsafe { voidptr(name) }, code, unsafe { voidptr(info) }))
		api.drop(name); if info != 0 { api.drop(info) }; assert owner != 0; return owner
	} }
	owner := objc_allocate(cf_error_type_id()); mut header := obj_header(owner)
	header.number = code; header.fields[0] = name; header.fields[1] = info
	return owner
}
fn describe_value(api DescribeApi, owner u64) SwiftErrorValue {
	// Caller supplies persistent scratch instead; this helper must not return
	// a pointer into its own stack. Extract the metadata/table only here.
	mut scratch := u64(0); mut value := SwiftErrorValue{}
	api.extract(owner, unsafe { &scratch }, unsafe { &value })
	return SwiftErrorValue{ metadata: value.metadata, witness: value.witness }
}
fn describe_call(api DescribeApi, owner u64) SwiftStringWords {
	mut scratch := [u64(0x1111), u64(0), u64(0x3333)]!
	mut value := SwiftErrorValue{}
	api.extract(owner, unsafe { &scratch[1] }, unsafe { &value })
	mut context := [2]u64{}
	result := api.probe(value.value, value.metadata, value.witness, api.entry, unsafe { &context[0] })
	assert context[0] == value.value && context[1] == 0x7654
	assert scratch[0] == 0x1111 && scratch[1] == owner && scratch[2] == 0x3333
	return result
}
fn describe_assert(api DescribeApi, result SwiftStringWords, expected string) {
	array := api.bytes(result.first, result.second)
	assert read64(array + 16) == u64(expected.len + 1)
	assert C.memcmp(unsafe { voidptr(array + 32) }, expected.str, usize(expected.len)) == 0
	assert unsafe { *(&u8(array + 32 + u64(expected.len))) } == 0
	api.release(array)
}
fn describe_case(api DescribeApi, domain string, code i64, mask u32, fields [5]string, expected string) {
	owner := api.make(domain, code, mask, fields); before := api.refs(owner)
	first := describe_call(api, owner); second := describe_call(api, owner)
	assert api.refs(owner) == before
	describe_assert(api, first, expected); api.release(first.second)
	assert api.refs(owner) == before
	api.drop(owner)
	describe_assert(api, second, expected); api.release(second.second)
}
fn describe_worker(api DescribeApi, owner u64) {
	for _ in 0 .. 200 {
		words := describe_call(api, owner)
		describe_assert(api, words, 'The operation couldn’t be completed. (Fortnite error -7.)')
		api.release(words.second)
	}
}
fn describe_cases(api DescribeApi) {
	empty := [5]string{}
	describe_case(api, 'Fortnite', -7, 0, empty, 'The operation couldn’t be completed. (Fortnite error -7.)')
	describe_case(api, 'long Unicode é 🎮', 13, 0, empty, 'The operation couldn’t be completed. (long Unicode é 🎮 error 13.)')
	describe_case(api, '', 0, 0, empty, 'The operation couldn’t be completed. ( error 0.)')
	describe_case(api, 'a\x00b', 0, 0, empty, 'The operation couldn’t be completed. (a\x00b error 0.)')
	describe_case(api, 'Fortnite', i64(9223372036854775807), 0, empty, 'The operation couldn’t be completed. (Fortnite error 9223372036854775807.)')
	describe_case(api, 'Fortnite', -i64(9223372036854775807) - 1, 0, empty, 'The operation couldn’t be completed. (Fortnite error -9223372036854775808.)')
	describe_case(api, 'NSOSStatusErrorDomain', -26275, 0, empty, 'The operation couldn’t be completed. (OSStatus error -26275.)')
	describe_case(api, 'NSPOSIXErrorDomain', 13, 0, empty, 'The operation couldn’t be completed. Permission denied')
	describe_case(api, 'NSPOSIXErrorDomain', -7, 0, empty, 'The operation couldn’t be completed. (POSIX error -7 - Unknown error: -7)')
	describe_case(api, 'NSPOSIXErrorDomain', i64(9223372036854775807), 0, empty, 'The operation couldn’t be completed. (POSIX error 9223372036854775807 - Unknown error: -1)')
	describe_case(api, 'NSPOSIXErrorDomain', -i64(9223372036854775807) - 1, 0, empty, 'The operation couldn’t be completed. Undefined error: 0')
	fields := ['Description π\x00🎮', 'Failure π\x00🎮', 'Reason π\x00🎮', 'Detail π\x00🎮', 'Ignored recovery']!
	for mask, expected in { u32(1):'Description π\x00🎮', 2:'Failure π\x00🎮', 4:'The operation couldn’t be completed. Reason π\x00🎮',
		8:'The operation couldn’t be completed. (Fortnite error -7 - Detail π\x00🎮)', 16:'The operation couldn’t be completed. (Fortnite error -7.)',
		6:'Failure π\x00🎮 Reason π\x00🎮', 5:'Description π\x00🎮', 12:'The operation couldn’t be completed. Reason π\x00🎮', 10:'Failure π\x00🎮' } {
		describe_case(api, 'Fortnite', -7, mask, fields, expected)
	}
	describe_case(api, 'Fortnite', -7, 1, empty, '')
	describe_case(api, 'Fortnite', -7, 2, empty, '')
	describe_case(api, 'Fortnite', -7, 4, empty, 'The operation couldn’t be completed. ')
	describe_case(api, 'Fortnite', -7, 8, empty, 'The operation couldn’t be completed. (Fortnite error -7 - )')
	describe_case(api, 'NSCocoaErrorDomain', 260, 1, fields, 'Description π\x00🎮')
	describe_case(api, 'NSMachErrorDomain', 13, 6, fields, 'Failure π\x00🎮 Reason π\x00🎮')
	owner := api.make('Fortnite', -7, 0, empty)
	mut workers := []thread{}
	for _ in 0 .. 4 { workers << spawn describe_worker(api, owner) }
	workers.wait(); unsafe { workers.free() }; assert api.refs(owner) == 1; api.drop(owner)
	if !api.native { assert ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0 }
}
fn describe_invalid(api DescribeApi) {
	owner := api.make('Fortnite', -7, 0, [5]string{}); value := describe_value(api, owner)
	mut source := owner
	page := usize(C.getpagesize()); guard := C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert guard != unsafe { voidptr(-1) }
	for pointer in [u64(0), 1, ~u64(0), u64(guard)]! {
		if _ := swift_error_description_checked(pointer, value.witness, u64(guard)) { assert false }
		if _ := swift_error_description_checked(value.metadata, pointer, u64(guard)) { assert false }
	}
	for pointer in [u64(0), 1]! { if _ := swift_error_description_checked(value.metadata, value.witness, pointer) { assert false } }
	for object in [u64(0), 1, ~u64(0), u64(guard)]! {
		source = object
		if _ := swift_error_description_checked(value.metadata, value.witness, u64(unsafe { &source })) { assert false }
	}
	assert C.munmap(guard, page) == 0
	source = objc_allocate(ios_runtime.names['NSObject'])
	if _ := swift_error_description_checked(value.metadata, value.witness, u64(unsafe { &source })) { assert false }
	objc_release(source)
	source = owner; api.drop(owner)
	if _ := swift_error_description_checked(value.metadata, value.witness, u64(unsafe { &source })) { assert false }
	for domain in ['NSCocoaErrorDomain', 'NSMachErrorDomain']! {
		error_owner := api.make(domain, 13, 0, [5]string{}); source = error_owner
		if _ := swift_error_description_checked(value.metadata, value.witness, u64(unsafe { &source })) { assert false }
		api.drop(error_owner)
	}
	bad := api.make('Fortnite', 0, 1, ['wrong type', '', '', '', '']!)
	info := obj_header(bad).fields[1]; key := owned_string('NSLocalizedDescription'); number := objc_allocate(ios_runtime.names['NSNumber'])
	objc_set_class(info, ios_runtime.names['NSMutableDictionary']); cf_dictionary_set(info, key, number); objc_release(key); objc_release(number)
	source = bad
	if _ := swift_error_description_checked(value.metadata, value.witness, u64(unsafe { &source })) { assert false }
	api.drop(bad)
	large := api.make('Fortnite', 0, 0, [5]string{}); source = large
	mut domain := obj_header(obj_header(large).fields[0])
	old_text := domain.text; old_length := domain.text_length
	domain.text = unsafe { &char(1) }; domain.text_length = 1024 * 1024 + 1
	if _ := swift_error_description_checked(value.metadata, value.witness, u64(unsafe { &source })) { assert false }
	domain.text = old_text; domain.text_length = old_length; api.drop(large)
}
fn test_swift_error_description() {
	page := usize(C.getpagesize()); code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	for index, op in [u32(0xa9bd57f4), 0xa9015ff6, 0xa9027bfd, 0xaa0003f4, 0xaa0103e0, 0xaa0203e1,
		0xaa0303f6, 0xaa0403f7, u32(0xd2800000 | (0x7654 << 5) | 21), 0xd63f02c0, 0xa90056f4,
		0xa9427bfd, 0xa9415ff6, 0xa8c357f4, 0xd65f03c0]! { write32(code + u64(index * 4), op) }
	C.__builtin___clear_cache(unsafe { voidptr(code) }, unsafe { voidptr(code + 60) })
	assert C.mprotect(unsafe { voidptr(code) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		api := describe_api(true, code, false); describe_cases(api)
		assert api.entry == describe_api(true, code, true).entry
		println('IOS-SWIFT-ERROR-DESCRIPTION-NATIVE: borrowed CFError value and owned String, preserved Swift contexts, domain/code/description/failure/reason/detail priority, Unicode/NUL and Int64 limits, native POSIX messages, concurrent calls and Foundation reexport')
	}
	if _ := swift_error_description_checked(0, 0, 0) { assert false }
	for framework in [false, true]! {
		objc_start(); baseline := ios_runtime.live
		api := describe_api(false, code, framework)
		assert api.entry == describe_api(false, code, !framework).entry
		describe_cases(api); describe_invalid(api)
		assert ios_runtime.live == baseline && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0
		objc_stop(); assert ios_runtime.swift_foundation_arena == 0 && ios_runtime.swift_error_arena == 0
		if _ := swift_error_description_checked(0, 0, 0) { assert false }
	}
	assert C.munmap(unsafe { voidptr(code) }, page) == 0
	println('IOS-SWIFT-ERROR-DESCRIPTION: native CFError differential, x20 borrowed Self and preserved x21, owned String after source release, explicit fields and C-locale fallback, Unicode/NUL and Int64 limits, concurrent calls, registry/type/size guards and explicit unsupported catalogs/conformances, both Foundation import names and two drained lifetimes')
}
