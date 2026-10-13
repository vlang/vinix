// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFError.h>
	#include <CoreFoundation/CFString.h>
}
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.mincore(voidptr, usize, &u8) i32
fn C.CFStringCreateWithBytes(voidptr, &u8, i64, u32, bool) voidptr
fn C.CFErrorCreate(voidptr, voidptr, i64, voidptr) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRetain(voidptr) voidptr
fn C.CFRelease(voidptr)
type CStringInvoke = fn (u64, u64, u64, u64, u64, u64, u64, &u64)
type CStringSign = fn (u64, u64) u64
type CStringLiteral = fn (&u8, i64, bool) SwiftStringWords
type CStringCreate = fn (&u8) SwiftStringWords
type CStringRelease = fn (u64)
struct CStringApi {
	native bool
	entry u64
	closure u64
	invoke CStringInvoke
	literal CStringLiteral
	release CStringRelease
	int_type u64
	string_type u64
	void_type u64
}
struct CStringContext {
	api CStringApi
	expected string
	output u64
	metadata u64
	kind int
	error u64
	input_owner u64
	result SwiftStringWords
	reenter bool
mut:
	calls int
}
fn cstring_api(native bool, base u64) CStringApi {
	if native {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW); assert core != unsafe { nil }
		assert C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', C.RTLD_NOW) != unsafe { nil }
		sign := unsafe { CStringSign(voidptr(base + 224)) }
		return CStringApi{ native: true, entry: u64(C.dlsym(core, c'$sSS11withCStringyxxSPys4Int8VGKXEKlF')),
			closure: sign(base + 128, 63553), invoke: unsafe { CStringInvoke(voidptr(base)) },
			literal: unsafe { CStringLiteral(C.dlsym(core, c'$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC')) },
			release: unsafe { CStringRelease(C.dlsym(core, c'swift_bridgeObjectRelease')) },
			int_type: u64(C.dlsym(core, c'$sSiN')), string_type: u64(C.dlsym(core, c'$sSSN')), void_type: u64(C.dlsym(core, c'$sytN')) + 8 }
	}
	return CStringApi{ entry: runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSS11withCStringyxxSPys4Int8VGKXEKlF') or { panic(err) },
		closure: base + 128, invoke: unsafe { CStringInvoke(voidptr(base)) }, literal: swift_string_literal,
		release: swift_bridge_release, int_type: swift_integer_metadata(), string_type: swift_string_metadata(), void_type: swift_void_full_metadata() + 8 }
}
fn cstring_owned(api CStringApi, text string) SwiftStringWords {
	$if macos { if api.native {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		return unsafe { CStringCreate(C.dlsym(core, c'$sSS7cStringSSSPys4Int8VG_tcfC'))(text.str) }
	} }
	mut words := swift_interpolation_init(i64(text.len), 0)
	swift_string_append_bytes(u64(unsafe { &words }), u64(text.str), u64(text.len)); return words
}
fn cstring_keep_error(api CStringApi, owner u64) {
	$if macos { if api.native { C.CFRetain(unsafe { voidptr(owner) }); return } }
	objc_retain(owner)
}
fn cstring_drop_error(api CStringApi, owner u64) {
	$if macos { if api.native { C.CFRelease(unsafe { voidptr(owner) }); return } }
	objc_release(owner)
}
fn cstring_error_refs(api CStringApi, owner u64) i64 {
	$if macos { if api.native { return C.CFGetRetainCount(unsafe { voidptr(owner) }) } }
	return obj_header(owner).refs
}
fn cstring_error(api CStringApi) u64 {
	$if macos { if api.native {
		name := C.CFStringCreateWithBytes(unsafe { nil }, c'Fortnite', 8, 0x08000100, false)
		owner := C.CFErrorCreate(unsafe { nil }, name, -7, unsafe { nil }); C.CFRelease(name); return u64(owner)
	} }
	owner := objc_allocate(cf_error_type_id()); mut header := obj_header(owner)
	header.fields[0] = owned_string('Fortnite'); header.number = -7; return owner
}
fn cstring_callback(bytes u64, context u64, output u64, metadata u64) u64 {
	mut ctx := unsafe { &CStringContext(context) }
	assert output == ctx.output && metadata == ctx.metadata
	assert C.memcmp(unsafe { voidptr(bytes) }, ctx.expected.str, usize(ctx.expected.len)) == 0
	assert unsafe { *(&u8(bytes + u64(ctx.expected.len))) } == 0
	if ctx.input_owner != 0 { assert read64(ctx.input_owner + 8) >> 33 == 0 }
	if ctx.error != 0 { assert cstring_error_refs(ctx.api, ctx.error) == 2 }
	if !ctx.api.native {
		C.ios_objc_initialize_lock()
		assert (ios_runtime.swift_buffers[bytes - 32] or { u64(0) }) == u64(ctx.expected.len + 1)
		C.ios_objc_initialize_unlock()
	}
	ctx.calls++
	if ctx.reenter {
		// A worker finishes while this callback remains active. Holding the
		// registry lock over the callback would deadlock this nested call.
		worker := spawn cstring_nested(ctx.api); worker.wait()
		assert C.memcmp(unsafe { voidptr(bytes) }, ctx.expected.str, usize(ctx.expected.len)) == 0
	}
	if ctx.error == 0 {
		if ctx.kind == 1 { unsafe { *(&u64(output)) = 0x7172737475767778 } }
		if ctx.kind == 2 { unsafe { *(&SwiftStringWords(output)) = ctx.result } }
	}
	return ctx.error
}
fn cstring_call(api CStringApi, words SwiftStringWords, text string, kind int, error u64, input_owner u64, reenter bool, boundary u64) {
	metadata := if kind == 1 { api.int_type } else if kind == 2 { api.string_type } else { api.void_type }
	output := boundary - if kind == 1 { u64(8) } else if kind == 2 { u64(16) } else { u64(0) }
	if kind != 0 { unsafe { *(&u64(output - 8)) = 0x1111; *(&u64(output)) = 0x2222 } }
	if kind == 2 { unsafe { *(&u64(output + 8)) = 0x3333 } }
	result := if kind == 2 { cstring_owned(api, 'a real owned generic String result 🎮') } else { SwiftStringWords{} }
	if error != 0 { cstring_keep_error(api, error) }
	mut ctx := CStringContext{ api: api, expected: text, output: output, metadata: metadata, kind: kind,
		error: error, input_owner: input_owner, result: result, reenter: reenter }
	mut observed := [u64(0x4444), 0, 0, 0, 0, 0x5555]!
	api.invoke(api.entry, api.closure, u64(unsafe { &ctx }), words.first, words.second, metadata, output, unsafe { &observed[1] })
	assert ctx.calls == 1 && observed[0] == 0x4444 && observed[5] == 0x5555
	assert observed[1] == 0x6000 && observed[2] == 0x6001 && observed[3] == 0x5020 && observed[4] == error
	if kind != 0 { assert read64(output - 8) == 0x1111 }
	if error != 0 {
		if kind != 0 { assert read64(output) == 0x2222 }
		if kind == 2 { assert read64(output + 8) == 0x3333 }
		assert cstring_error_refs(api, error) == 2; cstring_drop_error(api, error)
	} else {
		if kind == 1 { assert read64(output) == 0x7172737475767778 }
		if kind == 2 { assert read64(output) == result.first && read64(output + 8) == result.second }
	}
	if kind == 2 { assert read64(result.second + 8) >> 33 == 0; api.release(result.second) }
	if input_owner != 0 { assert read64(input_owner + 8) >> 33 == 0 }
}
fn cstring_nested(api CStringApi) {
	page := usize(C.getpagesize()); memory := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert memory != u64(-1)
	boundary := memory + u64(page); assert C.mprotect(unsafe { voidptr(boundary) }, page, C.PROT_NONE) == 0
	text := 'nested CString callback'; words := api.literal(text.str, i64(text.len), true)
	cstring_call(api, words, text, 1, 0, 0, false, boundary)
	assert C.munmap(unsafe { voidptr(memory) }, page * 2) == 0
}
fn cstring_worker(api CStringApi) { for _ in 0 .. 40 { cstring_nested(api) } }
fn cstring_values(api CStringApi, boundary u64) {
	error := cstring_error(api)
	for text in ['', 'Fortnite', '123456789012345', 'π🎮', 'a\x00b', 'long borrowed literal with CString']! {
		words := api.literal(text.str, i64(text.len), text.is_ascii())
		for kind in 0 .. 3 { for thrown in [u64(0), error]! { cstring_call(api, words, text, kind, thrown, 0, kind == 1, boundary) } }
	}
	text := 'a real owned native String for withCString'; words := cstring_owned(api, text)
	for kind in 0 .. 3 { for thrown in [u64(0), error]! { cstring_call(api, words, text, kind, thrown, words.second, true, boundary) } }
	api.release(words.second); assert cstring_error_refs(api, error) == 1; cstring_drop_error(api, error)
	mut workers := []thread{}
	for _ in 0 .. 4 { workers << spawn cstring_worker(api) }; workers.wait(); unsafe { workers.free() }
	if !api.native { assert ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_strings.len == 0 }
}
fn cstring_invalid() {
	before := ios_runtime.swift_buffers.len
	for words in [SwiftStringWords{}, SwiftStringWords{ second: u64(1) << 61 },
		SwiftStringWords{ first: u64(1) << 60, second: u64(1) << 60 },
		SwiftStringWords{ first: u64(1) << 60 }, SwiftStringWords{ second: 1 }]! {
		if _ := swift_cstring_buffer_checked(words.first, words.second) { assert false }
	}
	assert ios_runtime.swift_buffers.len == before
	for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! {
		assert runtime_symbol(library, '_$sSS11withCStringyxxSPys4Int8VGKXEKlF') == none
	}
	assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '$sSS11withCStringyxxSPys4Int8VGKXEKlF') == none
}
fn test_swift_with_cstring() {
	page := usize(C.getpagesize()); base := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert base != u64(-1)
	boundary := base + u64(page * 2)
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xa90363f7, 0xaa0003f0, 0xaa0703f3,
		0xaa0603e8, 0xaa0103e0, 0xaa0203e1, 0xaa0303e2, 0xaa0403e3, 0xaa0503e4, 0xd28a0414,
		0xaa1f03f5, 0xd63f0200, 0xa9000660, 0xa9015674, 0xa9425bf5, 0xa94363f7, 0xa94153f3,
		0xa8c47bfd, 0xd65f03c0]! { write32(base + u64(i * 4), op) }
	for i, op in [u32(0xa9be7bfd), 0xa90153f3, 0xaa1403e1, 0xaa0803e2, 0xaa0403e3, 0x58000170,
		0xd63f0200, 0xaa0003f5, 0xd28c0000, 0xd28c0021, 0xa94153f3, 0xa8c27bfd, 0xd65f03c0]! { write32(base + 128 + u64(i * 4), op) }
	unsafe { *(&u64(base + 192)) = u64(voidptr(cstring_callback)) }
	write32(base + 224, 0xdac10020); write32(base + 228, 0xd65f03c0)
	C.__builtin___clear_cache(unsafe { voidptr(base) }, unsafe { voidptr(base + 232) })
	assert C.mprotect(unsafe { voidptr(base) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	assert C.mprotect(unsafe { voidptr(boundary) }, page, C.PROT_NONE) == 0
	$if macos { cstring_values(cstring_api(true, base), boundary)
		println('IOS-CSTRING-NATIVE: measured borrowed String/closure/context ABI, indirect Int/String/Void results, x20 preservation and x21 throws, exact NUL bytes, unchanged input/error/result ownership and reentrant concurrent callbacks') }
	for _ in 0 .. 2 {
		objc_start(); api := cstring_api(false, base); cstring_values(api, boundary); cstring_invalid()
		// An exactly bounded large literal has no readable terminator in its
		// source. Vinix copies its extent and adds NUL before calling the closure.
		text := 'exactly bounded literal'; source := boundary - u64(text.len)
		C.memcpy(unsafe { voidptr(source) }, text.str, usize(text.len))
		words := swift_string_literal(unsafe { &u8(source) }, i64(text.len), true)
		cstring_nested(api) // Separate result storage avoids aliasing the source.
		mut output := [3]u64{}; mut observed := [4]u64{}
		mut ctx := CStringContext{ api: api, expected: text, output: u64(unsafe { &output[1] }), metadata: api.int_type, kind: 1 }
		api.invoke(api.entry, api.closure, u64(unsafe { &ctx }), words.first, words.second, api.int_type, ctx.output, unsafe { &observed[0] })
		assert ctx.calls == 1 && output[1] == 0x7172737475767778 && observed[3] == 0
		assert ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.live == 0
		arena := ios_runtime.swift_cstring_arena; objc_stop(); assert ios_runtime.swift_cstring_arena == 0
		$if macos { assert C.mprotect(unsafe { voidptr(arena) }, page, C.PROT_READ) == -1 }
		$else { mut residency := u8(0); assert C.mincore(unsafe { voidptr(arena) }, page, unsafe { &residency }) == -1 }
	}
	assert C.munmap(unsafe { voidptr(base) }, page * 3) == 0
	println('IOS-CSTRING: scoped borrowed closure call, generic output and error register forwarding, bounded NUL copy, temporary release on success/throw, no lock across nested workers, four readers, two drained/unmapped runtimes and rejected unsupported storage')
}
