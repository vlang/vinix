// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
fn C.objc_getClass(&char) voidptr

type Context2Lookup = fn (u64, u64, u64, u64) u64
type Context2Probe = fn (u64, u64, u64, u64, u64, &u64, u64)
type Context2ArrayAccess = fn (u64, u64) SwiftAssociatedMetadata
type Context2ClassMetadata = fn (u64) u64
__global context2_guard = u64(0)

fn context2_case(lookup Context2Lookup, probe Context2Probe, name u64, length u64, context u64, args u64, expected u64) {
	for _ in 0 .. 128 {
		mut output := [u64(0x1234), 0, 0, 0, 0, 0, 0x5678]!
		probe(name, length, context, args, u64(unsafe { voidptr(lookup) }), unsafe { &output[1] },context2_guard)
		assert output[0] == 0x1234 && output[6] == 0x5678
		assert output[1] == expected && output[3] == context2_guard && output[4] == 0x5121 && output[5] == 0x5222
		assert lookup(name, length, context, args) == expected
	}
}

fn context2_basics(lookup Context2Lookup, probe Context2Probe, integer u64, text u64, void_metadata u64, array_access Context2ArrayAccess, array_descriptor u64) {
	for name, metadata in {'Si': integer, 'SS': text, 'S': text, 'yt': void_metadata,
		'SaySSG': array_access(0, text).metadata, 'SaySaySiGG': array_access(0, array_access(0, integer).metadata).metadata,
		'Si\x00junk': integer, '': u64(0), 'Say': u64(0), 'SaySS': u64(0), 'x': u64(0)} {
		context2_case(lookup, probe, u64(name.str), u64(name.len), 0, 0, metadata)
	}
	mut args := [text]!
	for name, metadata in {'x': text, 'SayxG': array_access(0, text).metadata, 'Si': integer} {
		context2_case(lookup, probe, u64(name.str), u64(name.len), array_descriptor, u64(unsafe { &args[0] }), metadata)
	}
	page := usize(C.getpagesize())
	bytes := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert bytes != u64(-1)
	boundary := bytes + u64(page) - 2
	unsafe { *(&u8(boundary)) = `S`; *(&u8(boundary + 1)) = `i` }
	assert C.mprotect(unsafe { voidptr(bytes + u64(page)) }, page, C.PROT_NONE) == 0
	context2_case(lookup, probe, boundary, 2, 0, 0, integer)
	// Nongeneric expressions do not read either unused generic input.
	context2_case(lookup, probe, boundary, 2, bytes + u64(page), bytes + u64(page), integer)
	context2_case(lookup, probe, bytes + u64(page), 0, 0, 0, 0)
	assert lookup(0, 0, 0, 0) == 0
	assert C.munmap(unsafe { voidptr(bytes) }, page * 2) == 0
}

fn context2_fixture(base u64, metadata u64) u64 {
	page := u64(C.getpagesize())
	descriptor := base + page + 64
	module_descriptor := base + page + 128
	// Record the native effective request before returning complete metadata.
	for i, word in [u32(0x58000109),0xf9000120,0x58000080,0xd2800001,0xd65f03c0]! { write32(base + u64(i*4),word) }
	unsafe { *(&u64(base + 24)) = metadata; *(&u64(base + 32)) = base + page + 336 }
	write32(descriptor, 0x51)
	swift_protocol_relative(descriptor + 4, module_descriptor)
	swift_protocol_relative(descriptor + 8, base + page + 192)
	swift_protocol_relative(descriptor + 12, base)
	write32(descriptor + 24, 2)
	swift_protocol_relative(module_descriptor + 8, base + page + 224)
	C.memcpy(unsafe { voidptr(base + page + 192) }, c'Fixture', 8)
	C.memcpy(unsafe { voidptr(base + page + 224) }, c'VinixContext2', 13)
	C.__builtin___clear_cache(unsafe { voidptr(base) }, unsafe { voidptr(base + 40) })
	assert C.mprotect(unsafe { voidptr(base) }, usize(page), C.PROT_READ | C.PROT_EXEC) == 0
	return descriptor
}

fn context2_symbolic(name u64, tag u8, target u64) {
	unsafe { *(&u8(name)) = tag }
	delta := u32(i32(i64(target) - i64(name + 1)))
	for i in u64(0) .. 4 { unsafe { *(&u8(name + 1 + i)) = u8(delta >> (i * 8)) } }
}

fn context2_native(probe Context2Probe) {
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		assert lib != unsafe { nil }
		entry := C.dlsym(lib,c'swift_getTypeByMangledNameInContext2'); assert entry != unsafe { nil }
		lookup := unsafe { Context2Lookup(entry) }
		integer := u64(C.dlsym(lib, c'$sSiN')); text := u64(C.dlsym(lib, c'$sSSN'))
		array_access := unsafe { Context2ArrayAccess(C.dlsym(lib, c'$sSaMa')) }
		context2_basics(lookup, probe, integer, text, u64(C.dlsym(lib, c'$sytN')) + 8,
			array_access, u64(C.dlsym(lib, c'$sSaMn')))
		class_metadata := unsafe { Context2ClassMetadata(C.dlsym(lib, c'swift_getObjCClassMetadata')) }
		for name, cls in {'So8NSObjectC': 'NSObject', 'So8NSStringC': 'NSString'} {
			context2_case(lookup, probe, u64(name.str), u64(name.len), 0, 0, class_metadata(u64(C.objc_getClass(cls.str))))
		}
		page := usize(C.getpagesize())
		base := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		assert base != u64(-1)
		descriptor := context2_fixture(base, integer); name := base + u64(page) + 256; slot := name + 64
		for tag in [u8(1), 2]! {
			unsafe { *(&u64(slot)) = descriptor }
			context2_symbolic(name, tag, if tag == 1 { descriptor } else { slot })
			context2_case(lookup, probe, name, 5, 0, 0, integer)
			assert read64(base + u64(page) + 336) == 0xff
		}
		assert C.munmap(unsafe { voidptr(base) }, page * 2) == 0
		println('NATIVE-CONTEXT2: canonical bounded String/Int/Void/nested Array metadata, generic Array substitution, ObjC wrappers, direct/indirect nominal accessor references, guarded raw calls preserving x20/x21 and protected end-of-span reads')
	}
}

__global context2_reentry_calls = u64(0)
fn context2_worker() u64 {
	metadata := swift_array_access(0, swift_string_metadata()).metadata
	for _ in 0 .. 256 { assert swift_context2_lookup(u64(c'SaySSG'), 6, 0, 0) == metadata }
	return metadata
}
fn context2_reentry_access(request u64) SwiftAssociatedMetadata {
	assert request == 0xff
	worker := spawn context2_worker()
	assert worker.wait() == swift_array_access(0, swift_string_metadata()).metadata
	context2_reentry_calls++
	return SwiftAssociatedMetadata{metadata: swift_integer_metadata()}
}
fn context2_incomplete_access(_request u64) SwiftAssociatedMetadata {
	return SwiftAssociatedMetadata{metadata: swift_integer_metadata(), state: 0xff}
}
fn context2_reject(name u64, length u64, context u64, args u64) {
	if _ := swift_context2_lookup_checked(name, length, context, args) { assert false, 'unsupported type lookup accepted' }
}

fn context2_suite(probe Context2Probe) {
	lookup := unsafe { Context2Lookup(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_getTypeByMangledNameInContext2') or { panic(err) })) }
	integer := swift_integer_metadata(); text := swift_string_metadata()
	array_descriptor := swift_array_arena() + u64(C.getpagesize()) + 160
	context2_basics(lookup, probe, integer, text, swift_void_full_metadata() + 8, swift_array_access, array_descriptor)
	for name, cls in {'So8NSObjectC': 'NSObject', 'So8NSStringC': 'NSString'} {
		context2_case(lookup, probe, u64(name.str), u64(name.len), 0, 0, swift_objc_metadata(ios_runtime.names[cls]))
	}
	assert lookup(u64(c'So12MissingClassC'), 17, 0, 0) == 0
	mut args := [text]!
	assert lookup(u64('x'.str), 1, read64(text + 8), u64(unsafe { &args[0] })) == 0
	assert lookup(u64('x'.str), 1, array_descriptor, 0) == 0 // Reject missing caller input safely.
	context2_reject(u64('x'.str), 1, 1, u64(unsafe { &args[0] }))
	for name in ['Sb', 'SSSg', 'SaySSGG', 'SSx', '$sSi']! { context2_reject(u64(name.str), u64(name.len), 0, 0) }
	assert swift_context2_lookup(u64(c'q_'), 2, 0, 0) == 0
	context2_reject(0, 1, 0, 0); context2_reject(1, 1048577, 0, 0); context2_reject(~u64(0) - 1, 2, 0, 0)
	page := usize(C.getpagesize())
	base := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert base != u64(-1)
	descriptor := context2_fixture(base, integer); name := base + u64(page) + 256; slot := name + 64
	for flags in [u32(0x50), 0x51, 0x52]! {
		write32(descriptor, flags)
		for tag in [u8(1), 2]! {
			unsafe { *(&u64(slot)) = descriptor }
			context2_symbolic(name, tag, if tag == 1 { descriptor } else { slot })
			context2_case(lookup, probe, name, 5, 0, 0, integer)
			assert read64(base + u64(page) + 336) == 0xff
			for length in u64(1) .. 5 { assert lookup(name, length, 0, 0) == 0 }
		}
	}
	write32(descriptor, 0xd1); context2_reject(name, 5, 0, 0)
	write32(descriptor, 0x43); context2_reject(name, 5, 0, 0)
	write32(descriptor, 0x51); write32(descriptor + 12, 0); context2_reject(name, 5, 0, 0)
	// The fixture's tail bridge runs a V accessor that waits for another
	// metadata reader. Its completion proves no runtime lock crosses calls.
	assert C.mprotect(unsafe { voidptr(base) }, page, C.PROT_READ | C.PROT_WRITE) == 0
	write32(base, 0x58000050); write32(base + 4, 0xd61f0200)
	unsafe { *(&u64(base + 8)) = u64(voidptr(context2_reentry_access)) }
	C.__builtin___clear_cache(unsafe { voidptr(base) }, unsafe { voidptr(base + 16) })
	assert C.mprotect(unsafe { voidptr(base) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	swift_protocol_relative(descriptor + 12, base)
	context2_reentry_calls = 0
	assert lookup(name, 5, 0, 0) == integer && context2_reentry_calls == 1
	unsafe { *(&u8(name + 5)) = `?` }; context2_reject(name, 6, 0, 0)
	assert context2_reentry_calls == 1 // Full syntax is checked before callbacks.
	assert C.mprotect(unsafe { voidptr(base) }, page, C.PROT_READ | C.PROT_WRITE) == 0
	unsafe { *(&u64(base + 8)) = u64(voidptr(context2_incomplete_access)) }
	C.__builtin___clear_cache(unsafe { voidptr(base) }, unsafe { voidptr(base + 16) })
	assert C.mprotect(unsafe { voidptr(base) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	context2_reject(name, 5, 0, 0)
	unsafe { *(&u64(slot)) = 0 }; context2_reject(name, 5, 0, 0)
	assert C.munmap(unsafe { voidptr(base) }, page * 2) == 0
	mut workers := []thread u64{}
	for _ in 0 .. 8 { workers << spawn context2_worker() }
	results := workers.wait()
	for metadata in results { assert metadata == swift_array_access(0, text).metadata }
	unsafe { workers.free(); results.free() }
	ios_runtime.swift_concurrency_retired = true; context2_reject(context2_guard,1,context2_guard,context2_guard); ios_runtime.swift_concurrency_retired = false
	if _ := runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib','_swift_getTypeByMangledNameInContext2') { assert false }
	if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib','__swift_getTypeByMangledNameInContext2') { assert false }
	assert ios_runtime.objects.len == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.live == 0
}

fn test_swift_context2_lookup() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page*2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	for i, op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0503f3,0xaa0403f0,0xaa0603f4,u32(0xd2800000|(0x5121<<5)|21),u32(0xd2800000|(0x5222<<5)|22),0xaa0603e8,0xd63f0200,0xa9000660,0xa9015674,0xf9001276,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]! { write32(code + u64(i * 4), op) }
	C.__builtin___clear_cache(unsafe { voidptr(code) }, unsafe { voidptr(code + 68) })
	assert C.mprotect(unsafe { voidptr(code) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	context2_guard = code + u64(page); assert C.mprotect(voidptr(context2_guard),page,C.PROT_NONE) == 0
	probe := unsafe { Context2Probe(voidptr(code)) }
	context2_native(probe)
	context2_reject(context2_guard,0,0,0)
	for _ in 0 .. 2 {
		objc_start(); context2_suite(probe)
		objc_stop()
		context2_reject(context2_guard,0,0,0)
		assert ios_runtime.swift_array_metadata.len == 0 && ios_runtime.swift_array_arena == 0
		assert ios_runtime.swift_metadata_arena == 0 && ios_runtime.swift_integer_arena == 0
		assert ios_runtime.swift_void_arena == 0 && ios_runtime.swift_objc_metadata.len == 0
	}
	assert C.munmap(unsafe { voidptr(code) }, page*2) == 0
	println('IOS-CONTEXT2: canonical bounded metadata, embedded zeros, nested Arrays, ObjC names, generic Array substitution, direct/indirect class/struct/enum accessors, guarded raw ABI, protected boundaries, unsupported contexts/expressions, complete-response validation, unlocked reentrant accessors, eight readers and two drained lifetimes')
}
