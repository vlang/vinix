// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_getClass(&char) voidptr
fn C.class_createInstance(voidptr, usize) voidptr
fn C.sel_registerName(&char) voidptr

type SwiftLiteralCall = fn (&u8, i64, bool) SwiftStringWords
type SwiftCStringCall = fn (&u8) SwiftStringWords
type SwiftUTF8Call = fn (u64, u64) u64
type SwiftInterpolationCall = fn (u64, u64) SwiftStringWords
type SwiftRetainCall = fn (u64) u64
type SwiftReleaseCall = fn (u64)
type SwiftReleaseNCall = fn (u64, u32)
type SwiftBridgeReleaseNCall = fn (u64, i32)
type SwiftUniqueCall = fn (u64) bool
type SwiftSendCall = fn (u64, u64) u64
type SwiftARCProbeCall = fn (u64, u64, &u64)

struct SwiftStringApi {
	native bool
	@[required]
	literal SwiftLiteralCall
	@[required]
	interpolate SwiftInterpolationCall
	@[required]
	utf8 SwiftUTF8Call
	@[required]
	retain SwiftRetainCall
	@[required]
	release SwiftReleaseCall
	@[required]
	release_n SwiftReleaseNCall
	@[required]
	bridge_retain SwiftRetainCall
	@[required]
	bridge_release SwiftReleaseCall
	@[required]
	bridge_release_n SwiftBridgeReleaseNCall
	@[required]
	unknown_retain SwiftRetainCall
	@[required]
	unknown_release SwiftReleaseCall
	@[required]
	unique SwiftUniqueCall
}

fn swift_test_ascii(text string) bool {
	for i in 0 .. text.len { if text[i] >= 128 { return false } }
	return true
}
fn swift_test_preserve_most(api SwiftStringApi) {
	$if arm64 {
		page := usize(C.getpagesize())
		code := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		assert code != unsafe { voidptr(-1) }
		defer { assert C.munmap(code, page) == 0 }
		base := u64(code)
		write32(base, 0xa9be7bfd) // stp x29,x30,[sp,#-32]!
		write32(base + 4, 0xa90153f3) // stp x19,x20,[sp,#16]
		write32(base + 8, 0xaa0203f3) // mov x19,x2 (output)
		write32(base + 12, 0xaa0103f0) // mov x16,x1 (target)
		for reg in 1 .. 16 { write32(base + u64(3 + reg) * 4, 0xd2800000 | (u32(0x5000 + reg) << 5) | u32(reg)) }
		write32(base + 76, 0xd63f0200) // blr x16
		for pair in 0 .. 8 {
			reg := u32(pair * 2)
			write32(base + u64(20 + pair) * 4, 0xa9000000 | (u32(pair * 2) << 15) | ((reg + 1) << 10) | (19 << 5) | reg)
		}
		write32(base + 112, 0xa94153f3) // ldp x19,x20,[sp,#16]
		write32(base + 116, 0xa8c27bfd) // ldp x29,x30,[sp],#32
		write32(base + 120, 0xd65f03c0)
		C.__builtin___clear_cache(code, unsafe { voidptr(base + 124) })
		assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0
		probe := unsafe { SwiftARCProbeCall(code) }
		words := api.literal(c'ARC ABI', 7, true)
		object := api.utf8(words.first, words.second)
		mut registers := [16]u64{}
		for value in [u64(0), object]! {
			probe(value, u64(unsafe { voidptr(api.retain) }), unsafe { &registers[0] })
			assert registers[0] == value
			for reg in 9 .. 16 { assert registers[reg] == u64(0x5000 + reg) }
			probe(value, u64(unsafe { voidptr(api.release) }), unsafe { &registers[0] })
			for reg in 9 .. 16 { assert registers[reg] == u64(0x5000 + reg) }
		}
		assert read64(object + 8) == 3
		api.release(object)
	}
}
fn swift_test_array(api SwiftStringApi, words SwiftStringWords, text string) {
	array := api.utf8(words.first, words.second)
	assert array != 0 && read64(array) != 0
	assert read64(array + 8) == 3
	assert read64(array + 16) == u64(text.len + 1)
	assert read64(array + 24) & 1 == 0 && read64(array + 24) >> 1 >= u64(text.len + 1)
	for i in 0 .. text.len { assert unsafe { *(&u8(array + 32 + u64(i))) } == text[i] }
	assert unsafe { *(&u8(array + 32 + u64(text.len))) } == 0
	assert api.unique(array)
	assert api.retain(array) == array && !api.unique(array)
	assert read64(array + 8) == 0x200000003
	assert api.unknown_retain(array) == array && read64(array + 8) == 0x400000003
	api.unknown_release(array)
	for flag in [u64(0), u64(1) << 60, u64(1) << 61]! {
		assert api.bridge_retain(array | flag) == array | flag
		assert read64(array + 8) == 0x400000003
		api.bridge_release(array | flag)
	}
	api.release(array)
	assert api.unique(array) && read64(array + 8) == 3
	for _ in 0 .. 7 { api.retain(array) }
	api.release_n(array, 3)
	assert read64(array + 8) == 0x800000003
	api.bridge_release_n(array | (u64(1) << 60), 4)
	assert api.unique(array) && read64(array + 8) == 3
	api.release_n(array, 0); api.bridge_release_n(array, 0)
	assert read64(array + 8) == 3
	// Returned bytes are an owned copy; two getters never alias mutable storage.
	second := api.utf8(words.first, words.second)
	assert second != array
	unsafe { *(&u8(array + 32)) = 0x7f }
	assert unsafe { *(&u8(second + 32)) } == if text.len == 0 { u8(0) } else { text[0] }
	api.release_n(array, 1); api.bridge_release(second)
	if !api.native { assert ios_runtime.swift_buffers.len == 0 }
}
fn swift_test_worker(api SwiftStringApi, object u64) {
	for _ in 0 .. 2000 {
		assert api.retain(object) == object
		assert api.bridge_retain(object | (u64(1) << 61)) == object | (u64(1) << 61)
		assert api.unknown_retain(object) == object
		api.release(object); api.bridge_release(object | (u64(1) << 61)); api.unknown_release(object)
	}
}
fn swift_test_run(api SwiftStringApi) {
	swift_test_preserve_most(api)
	assert api.retain(0) == 0 && api.bridge_retain(0) == 0 && api.unknown_retain(0) == 0
	api.release(0); api.release_n(0, 10); api.bridge_release(0); api.bridge_release_n(0, 10); api.unknown_release(0)
	for tagged in [u64(0x8000000000000001), u64(0xe800000000000000)]! {
		assert api.bridge_retain(tagged) == tagged && api.unknown_retain(tagged) == tagged
		api.bridge_release(tagged); api.bridge_release_n(tagged, 17); api.unknown_release(tagged)
	}
	for text in ['', 'A', 'Fortnite', '123456789012345', '1234567890123456',
		'a longer native string with é and 🎮', 'é 🎮', 'a\x00b']! {
		words := api.literal(text.str, i64(text.len), swift_test_ascii(text))
		expected := swift_string_literal(text.str, i64(text.len), swift_test_ascii(text))
		assert words.first == expected.first && words.second == expected.second
		result := api.interpolate(words.first, words.second)
		assert result.first == words.first && result.second == words.second
		swift_test_array(api, result, text)
		api.bridge_release(result.second)
	}
	// Exercise every small-string byte count with exactly sized nonterminated
	// input. Sanitizers catch any speculative read beyond the supplied bytes.
	for count in 1 .. 16 {
		mut bytes := &u8(C.malloc(usize(count)))
		for i in 0 .. count { unsafe { bytes[i] = u8(65 + i) } }
		words := api.literal(bytes, i64(count), true)
		C.free(bytes)
		array := api.utf8(words.first, words.second)
		for i in 0 .. count { assert unsafe { *(&u8(array + 32 + u64(i))) } == u8(65 + i) }
		api.release(array)
	}
	for _ in 0 .. 500 {
		words := api.literal(c'Fortnite', 8, true)
		array := api.utf8(words.first, words.second)
		api.release(array)
	}
	words := api.literal(c'Concurrent UTF-8 arrays', 23, true)
	array := api.utf8(words.first, words.second)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn swift_test_worker(api, array) }
	workers.wait()
	assert read64(array + 8) == 3 && api.unique(array)
	api.release(array); api.bridge_release(words.second)
}
fn swift_test_objc_bridge(api SwiftStringApi) {
	mut object := u64(0)
	mut release_objc := SwiftReleaseCall(objc_release)
	$if macos {
		if api.native {
			object = u64(C.class_createInstance(C.objc_getClass(c'NSObject'), 0))
			release_objc = unsafe { SwiftReleaseCall(C.dlsym(C.dlopen(c'/usr/lib/libobjc.A.dylib', C.RTLD_NOW), c'objc_release')) }
		}
	}
	if !api.native { object = objc_allocate(ios_runtime.names['NSObject']) }
	assert api.bridge_retain(object | (u64(1) << 62)) == object | (u64(1) << 62)
	assert api.unknown_retain(object) == object
	mut refs := i64(0)
	$if macos {
		if api.native {
			send := unsafe { SwiftSendCall(C.dlsym(C.dlopen(c'/usr/lib/libobjc.A.dylib', C.RTLD_NOW), c'objc_msgSend')) }
			refs = i64(send(object, u64(C.sel_registerName(c'retainCount'))))
		}
	}
	if !api.native { refs = obj_header(object).refs }
	assert refs == 3
	api.bridge_release_n(object | (u64(1) << 62), 1); api.unknown_release(object); release_objc(object)
}
fn test_swift_string_and_buffer_ownership() {
	mut native := unsafe { &SwiftStringApi(nil) }
	mut native_cstring := unsafe { SwiftCStringCall(nil) }
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		native = &SwiftStringApi{
			native: true
			literal: unsafe { SwiftLiteralCall(C.dlsym(lib, c'$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC')) }
			interpolate: unsafe { SwiftInterpolationCall(C.dlsym(lib, c'$sSS19stringInterpolationSSs013DefaultStringB0V_tcfC')) }
			utf8: unsafe { SwiftUTF8Call(C.dlsym(lib, c'$sSS11utf8CStrings15ContiguousArrayVys4Int8VGvg')) }
			retain: unsafe { SwiftRetainCall(C.dlsym(lib, c'swift_retain')) }
			release: unsafe { SwiftReleaseCall(C.dlsym(lib, c'swift_release')) }
			release_n: unsafe { SwiftReleaseNCall(C.dlsym(lib, c'swift_release_n')) }
			bridge_retain: unsafe { SwiftRetainCall(C.dlsym(lib, c'swift_bridgeObjectRetain')) }
			bridge_release: unsafe { SwiftReleaseCall(C.dlsym(lib, c'swift_bridgeObjectRelease')) }
			bridge_release_n: unsafe { SwiftBridgeReleaseNCall(C.dlsym(lib, c'swift_bridgeObjectRelease_n')) }
			unknown_retain: unsafe { SwiftRetainCall(C.dlsym(lib, c'swift_unknownObjectRetain')) }
			unknown_release: unsafe { SwiftReleaseCall(C.dlsym(lib, c'swift_unknownObjectRelease')) }
			unique: unsafe { SwiftUniqueCall(C.dlsym(lib, c'swift_isUniquelyReferenced_nonNull_native')) }
		}
		native_cstring = unsafe { SwiftCStringCall(C.dlsym(lib, c'$sSS7cStringSSSPys4Int8VG_tcfC')) }
		swift_test_run(*native); swift_test_objc_bridge(*native)
		println('IOS-SWIFT-NATIVE: String register pairs and consuming interpolation, small/immortal/owned tail UTF-8, Int8 array layout, ARC bit 33, u32/i32 batch releases, spare bridge bits, ObjC/tagged/nil ownership and eight concurrent ARC workers')
	}
	for _ in 0 .. 2 {
		objc_start()
		library := '/usr/lib/swift/libswiftCore.dylib'
		api := SwiftStringApi{
			literal: unsafe { SwiftLiteralCall(voidptr(runtime_symbol(library, '_$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC') or { panic(err) })) }
			interpolate: unsafe { SwiftInterpolationCall(voidptr(runtime_symbol(library, '_$sSS19stringInterpolationSSs013DefaultStringB0V_tcfC') or { panic(err) })) }
			utf8: unsafe { SwiftUTF8Call(voidptr(runtime_symbol(library, '_$sSS11utf8CStrings15ContiguousArrayVys4Int8VGvg') or { panic(err) })) }
			retain: unsafe { SwiftRetainCall(voidptr(runtime_symbol(library, '_swift_retain') or { panic(err) })) }
			release: unsafe { SwiftReleaseCall(voidptr(runtime_symbol(library, '_swift_release') or { panic(err) })) }
			release_n: unsafe { SwiftReleaseNCall(voidptr(runtime_symbol(library, '_swift_release_n') or { panic(err) })) }
			bridge_retain: unsafe { SwiftRetainCall(voidptr(runtime_symbol(library, '_swift_bridgeObjectRetain') or { panic(err) })) }
			bridge_release: unsafe { SwiftReleaseCall(voidptr(runtime_symbol(library, '_swift_bridgeObjectRelease') or { panic(err) })) }
			bridge_release_n: unsafe { SwiftBridgeReleaseNCall(voidptr(runtime_symbol(library, '_swift_bridgeObjectRelease_n') or { panic(err) })) }
			unknown_retain: unsafe { SwiftRetainCall(voidptr(runtime_symbol(library, '_swift_unknownObjectRetain') or { panic(err) })) }
			unknown_release: unsafe { SwiftReleaseCall(voidptr(runtime_symbol(library, '_swift_unknownObjectRelease') or { panic(err) })) }
			unique: unsafe { SwiftUniqueCall(voidptr(runtime_symbol(library, '_swift_isUniquelyReferenced_nonNull_native') or { panic(err) })) }
		}
		swift_test_run(api); swift_test_objc_bridge(api)
		$if macos {
			// Native owned tail strings are borrowed for conversion while their
			// owner remains alive. V must copy the bytes before native final release.
			for text in ['1234567890123456', 'a longer native string with é and 🎮']! {
				words := native_cstring(text.str)
				refs := read64(words.second + 8)
				native_result := native.interpolate(words.first, words.second)
				assert native_result.first == words.first && native_result.second == words.second
				assert read64(native_result.second + 8) == refs
				result := api.interpolate(native_result.first, native_result.second)
				assert result.first == words.first && result.second == words.second
				assert read64(result.second + 8) == refs
				swift_test_array(*native, result, text)
				swift_test_array(api, result, text)
				array := api.utf8(result.first, result.second)
				native.bridge_release(result.second)
				for i in 0 .. text.len { assert unsafe { *(&u8(array + 32 + u64(i))) } == text[i] }
				api.release(array)
			}
		}
		for words in [SwiftStringWords{ first: 16, second: 1 },
			SwiftStringWords{ first: u64(1) << 60, second: (u64(1) << 60) | 1 },
			SwiftStringWords{ second: u64(1) << 61 }]! {
			if _ := swift_string_utf8(words.first, words.second) { assert false, 'unsupported form must not be dereferenced' }
		}
		if _ := swift_buffer_refs(1, 1) { assert false, 'unknown heap objects must be rejected' }
		words := api.literal(c'overflow', 8, true)
		array := api.utf8(words.first, words.second)
		if _ := swift_buffer_refs(array, i64(swift_strong_limit)) { assert false }
		if _ := swift_buffer_refs(array, -2) { assert false }
		assert api.unique(array) && read64(array + 8) == 3
		api.release(array)
		if _ := runtime_symbol(library, '_swift_allocObject') { assert false, 'unmeasured generic allocation must remain unresolved' }
		if _ := runtime_symbol(library, '_$sSSN') { assert false, 'unsupported type metadata must remain unresolved' }
		assert ios_runtime.swift_buffers.len == 0 && ios_runtime.objects.len == 0 && ios_runtime.live == 0
		objc_stop()
		assert ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_arc_code == 0 && ios_runtime.objects.len == 0 && ios_runtime.live == 0
	}
	println('IOS-SWIFT: measured String/Int8 payload ABI, consuming interpolation transfer, owned copies, synchronized ARC, batch release widths, bridge ownership, rejected shared/foreign storage and application metadata, overflow/underflow and two empty runtime teardowns')
}
