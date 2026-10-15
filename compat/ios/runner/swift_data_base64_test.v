// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.base64

$if macos {
	#flag -framework Foundation
}

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr

type Base64Construct = fn (u64) SwiftDataWords
type Base64Destroy = fn (u64, u64)
type Base64Access = fn (u64) SwiftAssociatedMetadata
type Base64Create = fn (u64, u64, i64) u64
type Base64Release = fn (u64)
type Base64Retain = fn (u64) u64
type Base64Utf8 = fn (u64, u64) u64
type Base64Probe = fn (u64, u64, u64, u64, &u64, u64)

struct Base64Api {
	native    bool
	entry     u64
	construct Base64Construct
	destroy   Base64Destroy
	metadata  u64
	release   Base64Release
	retain    Base64Retain
	utf8      Base64Utf8
	probe     Base64Probe
}

fn base64_entry(native bool, overlay bool) u64 {
	library := if overlay {
		'/usr/lib/swift/libswiftFoundation.dylib'
	} else {
		'/System/Library/Frameworks/Foundation.framework/Foundation'
	}
	symbol := '_$s10Foundation4DataV19base64EncodedString7optionsSSSo27NSDataBase64EncodingOptionsV_tF'
	return if native {
		u64(C.dlsym(C.dlopen(library.str, 2), symbol[1..].str))
	} else {
		runtime_symbol(library, symbol) or { panic(err) }
	}
}

fn base64_api(native bool, code u64) Base64Api {
	entry := base64_entry(native, false)
	assert entry != 0 && base64_entry(native, true) == entry
	if native {
		lib := C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		response := unsafe { Base64Access(C.dlsym(lib, c'$s10Foundation4DataVMa'))(0) }
		metadata := response.metadata
		return Base64Api{ native: true, entry: entry, construct: unsafe { Base64Construct(C.dlsym(lib, c'$s10Foundation4DataV11referencingACSo6NSDataCh_tcfC')) }, destroy: unsafe { Base64Destroy(voidptr(read64((read64(metadata - 8) & 0x0000ffffffffffff) + 8) & 0x0000ffffffffffff)) }, metadata: metadata, release: unsafe { Base64Release(C.dlsym(core, c'swift_bridgeObjectRelease')) }, retain: unsafe { Base64Retain(C.dlsym(core, c'swift_bridgeObjectRetain')) }, utf8: unsafe { Base64Utf8(C.dlsym(core, c'$sSS11utf8CStrings15ContiguousArrayVys4Int8VGvg')) }, probe: unsafe { Base64Probe(voidptr(code)) } }
	}
	return Base64Api{ entry: entry, construct: swift_data_reference, destroy: swift_data_reference_destroy, release: swift_bridge_release, retain: swift_bridge_retain, utf8: swift_string_utf8_cstring, probe: unsafe { Base64Probe(voidptr(code)) } }
}

fn (api Base64Api) source(bytes []u8) SwiftDataWords {
	object := if api.native {
		unsafe { Base64Create(C.dlsym(voidptr(-2), c'CFDataCreate'))(0, u64(bytes.data), i64(bytes.len)) }
	} else {
		cf_data_create(0, u64(bytes.data), i64(bytes.len))
	}
	value := api.construct(object)
	if api.native {
		unsafe { Base64Release(C.dlsym(C.dlopen(c'/usr/lib/libobjc.A.dylib', 2), c'objc_release'))(object) }
	} else {
		objc_release(object)
	}
	return value
}

fn (api Base64Api) drop(value SwiftDataWords) {
	mut words := [value.first, value.second]!
	api.destroy(u64(unsafe { &words[0] }), api.metadata)
	assert words == [value.first, value.second]!
}

fn (api Base64Api) encode(value SwiftDataWords, options u64, guard u64) SwiftStringWords {
	mut out := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	api.probe(api.entry, options, value.first, value.second, unsafe { &out[1] }, guard)
	assert out[0] == 0xcafe && out[3] == 0x5020 && out[4] == 0x5021 && out[5] == 0xbeef
	return SwiftStringWords{ first: out[1], second: out[2] }
}

fn (api Base64Api) verify(result SwiftStringWords, expected string) {
	array := api.utf8(result.first, result.second)
	assert read64(array + 16) == u64(expected.len + 1)
	assert unsafe { C.memcmp(voidptr(array + 32), expected.str, usize(expected.len)) } == 0
	assert unsafe { *(&u8(array + 32 + u64(expected.len))) } == 0
	api.release(array)
	if expected.len <= 15 {
		assert result == swift_string_literal(expected.str, i64(expected.len), true)
	} else {
		assert result.first == u64(expected.len) | u64(0xf000000000000000)
		assert result.second >> 60 == 0 && read64(result.second + 8) == 3
		assert unsafe { *(&u8(result.second + 32 + u64(expected.len))) } == 0
	}
}

// Independent standard-library encoding plus line splitting is the oracle;
// the implementation writes directly from Data into Swift String storage.
fn base64_expected(bytes []u8, options u64) string {
	encoded := base64.encode(bytes)
	width := if options & 1 != 0 {
		64
	} else if options & 2 != 0 {
		76
	} else {
		0
	}
	if width == 0 || encoded.len <= width { return encoded }
	ending := match options & 0x30 {
		0x10 { '\r' }
		0x20 { '\n' }
		else { '\r\n' }
	}
	mut lines := []string{}
	for i := 0; i < encoded.len; i += width {
		end := if i + width < encoded.len { i + width } else { encoded.len }
		lines << encoded[i..end]
	}
	result := lines.join(ending)
	unsafe {
		lines.free()
		encoded.free()
	}
	return result
}

fn base64_case(api Base64Api, guard u64, count int, start int, end int, options u64, guarded bool) {
	mut bytes := []u8{len: count}
	defer { unsafe { bytes.free() } }
	for i in 0 .. count { bytes[i] = u8(i * 37 + 5) }
	value := api.source(bytes)
	owner := if count > 14 { value.second & 0x3fffffffffffffff } else { u64(0) }
	mut mapping := u64(0)
	mut original := u64(0)
	page := u64(C.getpagesize())
	if guarded {
		assert !api.native && owner != 0 && u64(count) <= page
		mapping = u64(C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		assert mapping != u64(-1) && C.mprotect(voidptr(mapping + page), usize(page), C.PROT_NONE) == 0
		original = read64(owner + 16)
		C.memcpy(voidptr(mapping + page - u64(count)), voidptr(original), usize(count))
		assert C.mprotect(voidptr(mapping), usize(page), C.PROT_READ) == 0
		unsafe { *(&u64(owner + 16)) = mapping + page - u64(count) }
	}
	slice := if count > 14 {
		SwiftDataWords{ first: (u64(end) << 32) | u64(start), second: value.second }
	} else {
		value
	}
	expected := base64_expected(bytes[start..end], options)
	defer { unsafe { expected.free() } }
	first := api.encode(slice, options, guard)
	second := api.encode(slice, options, guard)
	if owner != 0 {
		assert read64(owner + 8) == 3
	}
	if guarded {
		unsafe { *(&u64(owner + 16)) = original }
		assert C.munmap(voidptr(mapping), usize(page * 2)) == 0
	}
	api.drop(value)
	api.verify(first, expected)
	api.verify(second, expected)
	if expected.len > 15 {
		assert first.second != second.second
	}
	assert api.retain(first.second) == first.second
	if expected.len > 15 {
		assert read64(first.second + 8) == 0x200000003
	}
	api.release(first.second)
	api.release(first.second)
	api.verify(second, expected)
	api.release(second.second)
}

fn base64_worker(api Base64Api, guard u64) {
	for _ in 0 .. 3 {
		for count in [0, 1, 9, 10, 14, 15, 49, 58, 200, 4096]! {
			base64_case(api, guard, count, 0, count, 0x31, false)
		}
	}
}

fn base64_suite(api Base64Api, guard u64) {
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn base64_worker(api, guard) }
	workers.wait()
	for count in [0, 1, 2, 3, 8, 9, 10, 11, 12, 13, 14, 15, 16, 31, 47, 48, 49, 56, 57, 58, 59,
		96, 114, 115, 200]! {
		for options in [u64(0), 1, 2, 3, 16, 17, 18, 19, 32, 33, 34, 35, 48, 49, 50, 51]! {
			base64_case(api, guard, count, 0, count, options, false)
		}
	}
	for count in [4096, 65536, 16777216]! { base64_case(api, guard, count, 0, count, 0, false) }
	for options in [u64(0), 3, 17, 34, 51]! {
		for pair in [[3, 12]!, [3, 3]!, [3, 73]!, [49, 115]!]! {
			base64_case(api, guard, 200, pair[0], pair[1], options, false)
		}
	}
	for value in [SwiftDataWords{}, SwiftDataWords{ first: 0xfeedface, second: 0xc000000000001234 }]! {
		assert api.encode(value, 0, guard) == swift_string_empty()
	}
	if !api.native {
		for count in [15, 16, 31, 47, 48, 49, 57, 58, 59, 65]! {
			base64_case(api, guard, count, 0, count, 51, true)
		}
		assert api.encode(SwiftDataWords{ first: (u64(3) << 32) | 3, second: guard | u64(0x4000000000000000) }, 0, guard) == swift_string_empty()
	}
}

fn base64_reject(options u64, first u64, second u64, reason string) {
	if _ := swift_data_base64_checked(options, first, second) {
		assert false
	} else {
		assert err.msg().contains(reason)
	}
}

fn test_swift_data_base64() {
	page := u64(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1) && C.mprotect(voidptr(code + page), usize(page), C.PROT_NONE) == 0
	// C probe -> native register ABI, protected x8 and preserved x20/x21.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0403f3, 0xaa0503e8,
		0xaa0103e0, 0xaa0203e1, 0xaa0303e2, 0xd28a0414, 0xd28a0435, 0xd63f0200, 0xa9000660, 0xa9015674,
		0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 72))
	assert C.mprotect(voidptr(code), usize(page), C.PROT_READ | C.PROT_EXEC) == 0
	guard := code + page
	$if macos {
		base64_suite(base64_api(true, code), guard)
		println('IOS-SWIFT-DATA-BASE64-NATIVE: empty/inline/slice input, padding, owned ASCII String thresholds, 16 option combinations, 64/76-column boundaries and CR/LF defaults, borrowed storage and independent concurrent results measured')
	}
	base64_reject(0, 0, 0, 'outside runtime lifetime')
	for _ in 0 .. 2 {
		objc_start()
		base64_suite(base64_api(false, code), guard)
		base64_reject(4, guard, guard, 'unknown NSData base64 encoding options')
		base64_reject(u64(-1), guard, guard, 'unknown NSData base64 encoding options')
		base64_reject(0, 0, u64(15) << 48, 'inline Swift Data length')
		base64_reject(0, guard, guard | u64(0x8000000000000000), 'large-range')
		for owner in [u64(0), 1, guard]! {
			base64_reject(0, u64(1) << 32, owner | u64(0x4000000000000000), 'registered snapshot')
		}
		base64_reject(0, (u64(1) << 32) | 2, guard | u64(0x4000000000000000), 'slice range')
		api := base64_api(false, code)
		mut bytes := []u8{len: 31}
		value := api.source(bytes)
		base64_reject(0, u64(32) << 32, value.second, 'layout or range')
		api.drop(value)
		unsafe { bytes.free() }
		for library in ['/usr/lib/swift/libswiftCore.dylib',
			'/System/Library/Frameworks/UIKit.framework/UIKit']! {
			if _ := runtime_symbol(library, '_$s10Foundation4DataV19base64EncodedString7optionsSSSo27NSDataBase64EncodingOptionsV_tF') {
				assert false
			}
		}
		assert ios_runtime.live == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_heap.len == 0
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.swift_foundation_arena == 0
		base64_reject(0, 0, 0, 'outside runtime lifetime')
	}
	assert C.munmap(voidptr(code), usize(page * 2)) == 0
	println('IOS-SWIFT-DATA-BASE64: native bytes/options and borrowed register ABI, owned independent String results, padding and line boundaries through 16 MiB, protected x8/input spans, safe invalid storage/options rejection, concurrent encoding and two empty runtime teardowns; external/large-range Data remains unsupported')
}
