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

type MangledLookup = fn (u64, u64, u64, u64) u64
type MangledProbe = fn (u64, u64, u64, u64, u64, &u64)
type MangledArrayAccess = fn (u64, u64) SwiftAssociatedMetadata
type MangledClassMetadata = fn (u64) u64

fn mangled_case(lookup MangledLookup, probe MangledProbe, name u64, length u64, context u64, args u64, expected u64) {
	for _ in 0 .. 128 {
		mut output := [u64(0x1234), 0, 0, 0, 0x5678]!
		probe(name, length, context, args, u64(unsafe { voidptr(lookup) }), unsafe { &output[1] })
		assert output[0] == 0x1234 && output[4] == 0x5678
		assert output[1] == expected && output[2] == 0x5020 && output[3] == 0x5021
		assert lookup(name, length, context, args) == expected
	}
}

fn mangled_basics(lookup MangledLookup, probe MangledProbe, integer u64, text u64, void_metadata u64, array_access MangledArrayAccess, array_descriptor u64) {
	for name, metadata in {'Si': integer, 'SS': text, 'S': text, 'yt': void_metadata,
		'SaySSG': array_access(0, text).metadata, 'SaySaySiGG': array_access(0, array_access(0, integer).metadata).metadata,
		'Si\x00junk': integer, '': u64(0), 'Say': u64(0), 'SaySS': u64(0), 'x': u64(0)} {
		mangled_case(lookup, probe, u64(name.str), u64(name.len), 0, 0, metadata)
	}
	mut args := [text]!
	for name, metadata in {'x': text, 'SayxG': array_access(0, text).metadata, 'Si': integer} {
		mangled_case(lookup, probe, u64(name.str), u64(name.len), array_descriptor, u64(unsafe { &args[0] }), metadata)
	}
	page := usize(C.getpagesize())
	bytes := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert bytes != u64(-1)
	boundary := bytes + u64(page) - 2
	unsafe { *(&u8(boundary)) = `S`; *(&u8(boundary + 1)) = `i` }
	assert C.mprotect(unsafe { voidptr(bytes + u64(page)) }, page, C.PROT_NONE) == 0
	mangled_case(lookup, probe, boundary, 2, 0, 0, integer)
	// Nongeneric expressions do not read either unused generic input.
	mangled_case(lookup, probe, boundary, 2, bytes + u64(page), bytes + u64(page), integer)
	mangled_case(lookup, probe, bytes + u64(page), 0, 0, 0, 0)
	assert lookup(0, 0, 0, 0) == 0
	assert C.munmap(unsafe { voidptr(bytes) }, page * 2) == 0
}

fn mangled_fixture(base u64, metadata u64) u64 {
	page := u64(C.getpagesize())
	descriptor := base + page + 64
	module_descriptor := base + page + 128
	write32(base, 0x58000080); write32(base + 4, 0xd2800001); write32(base + 8, 0xd65f03c0)
	unsafe { *(&u64(base + 16)) = metadata }
	write32(descriptor, 0x51)
	swift_protocol_relative(descriptor + 4, module_descriptor)
	swift_protocol_relative(descriptor + 8, base + page + 192)
	swift_protocol_relative(descriptor + 12, base)
	write32(descriptor + 24, 2)
	swift_protocol_relative(module_descriptor + 8, base + page + 224)
	C.memcpy(unsafe { voidptr(base + page + 192) }, c'Fixture', 8)
	C.memcpy(unsafe { voidptr(base + page + 224) }, c'VinixMangled', 13)
	C.__builtin___clear_cache(unsafe { voidptr(base) }, unsafe { voidptr(base + 24) })
	assert C.mprotect(unsafe { voidptr(base) }, usize(page), C.PROT_READ | C.PROT_EXEC) == 0
	return descriptor
}

fn mangled_symbolic(name u64, tag u8, target u64) {
	unsafe { *(&u8(name)) = tag }
	delta := u32(i32(i64(target) - i64(name + 1)))
	for i in u64(0) .. 4 { unsafe { *(&u8(name + 1 + i)) = u8(delta >> (i * 8)) } }
}

fn mangled_native(probe MangledProbe) {
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		assert lib != unsafe { nil }
		lookup := unsafe { MangledLookup(C.dlsym(lib, c'swift_getTypeByMangledNameInContext')) }
		integer := u64(C.dlsym(lib, c'$sSiN')); text := u64(C.dlsym(lib, c'$sSSN'))
		array_access := unsafe { MangledArrayAccess(C.dlsym(lib, c'$sSaMa')) }
		mangled_basics(lookup, probe, integer, text, u64(C.dlsym(lib, c'$sytN')) + 8,
			array_access, u64(C.dlsym(lib, c'$sSaMn')))
		class_metadata := unsafe { MangledClassMetadata(C.dlsym(lib, c'swift_getObjCClassMetadata')) }
		for name, cls in {'So8NSObjectC': 'NSObject', 'So8NSStringC': 'NSString'} {
			mangled_case(lookup, probe, u64(name.str), u64(name.len), 0, 0, class_metadata(u64(C.objc_getClass(cls.str))))
		}
		page := usize(C.getpagesize())
		base := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		assert base != u64(-1)
		descriptor := mangled_fixture(base, integer); name := base + u64(page) + 256; slot := name + 64
		for tag in [u8(1), 2]! {
			unsafe { *(&u64(slot)) = descriptor }
			mangled_symbolic(name, tag, if tag == 1 { descriptor } else { slot })
			mangled_case(lookup, probe, name, 5, 0, 0, integer)
		}
		assert C.munmap(unsafe { voidptr(base) }, page * 2) == 0
		println('IOS-SWIFT-MANGLED-NATIVE: canonical bounded String/Int/Void/nested Array metadata, generic Array substitution, ObjC wrappers, direct/indirect nominal accessor references, guarded raw calls preserving x20/x21 and protected end-of-span reads')
	}
}

__global mangled_reentry_calls = u64(0)
fn mangled_worker() u64 {
	metadata := swift_array_access(0, swift_string_metadata()).metadata
	for _ in 0 .. 256 { assert swift_mangled_lookup(u64(c'SaySSG'), 6, 0, 0) == metadata }
	return metadata
}
fn mangled_reentry_access(request u64) SwiftAssociatedMetadata {
	assert request == 0
	worker := spawn mangled_worker()
	assert worker.wait() == swift_array_access(0, swift_string_metadata()).metadata
	mangled_reentry_calls++
	return SwiftAssociatedMetadata{metadata: swift_integer_metadata()}
}
fn mangled_incomplete_access(_request u64) SwiftAssociatedMetadata {
	return SwiftAssociatedMetadata{metadata: swift_integer_metadata(), state: 0xff}
}
fn mangled_reject(name u64, length u64, context u64, args u64) {
	if _ := swift_mangled_lookup_checked(name, length, context, args) { assert false, 'unsupported type lookup accepted' }
}

fn mangled_suite(probe MangledProbe) {
	lookup := unsafe { MangledLookup(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_getTypeByMangledNameInContext') or { panic(err) })) }
	integer := swift_integer_metadata(); text := swift_string_metadata()
	array_descriptor := swift_array_arena() + u64(C.getpagesize()) + 160
	mangled_basics(lookup, probe, integer, text, swift_void_full_metadata() + 8, swift_array_access, array_descriptor)
	for name, cls in {'So8NSObjectC': 'NSObject', 'So8NSStringC': 'NSString'} {
		mangled_case(lookup, probe, u64(name.str), u64(name.len), 0, 0, swift_objc_metadata(ios_runtime.names[cls]))
	}
	assert lookup(u64(c'So12MissingClassC'), 17, 0, 0) == 0
	mut args := [text]!
	assert lookup(u64('x'.str), 1, read64(text + 8), u64(unsafe { &args[0] })) == 0
	assert lookup(u64('x'.str), 1, array_descriptor, 0) == 0 // Reject missing caller input safely.
	mangled_reject(u64('x'.str), 1, 1, u64(unsafe { &args[0] }))
	for name in ['Sb', 'SSSg', 'SaySSGG', 'SSx', '$sSi']! { mangled_reject(u64(name.str), u64(name.len), 0, 0) }
	assert swift_mangled_lookup(u64(c'q_'), 2, 0, 0) == 0
	mangled_reject(0, 1, 0, 0); mangled_reject(1, 1048577, 0, 0); mangled_reject(~u64(0) - 1, 2, 0, 0)
	page := usize(C.getpagesize())
	base := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert base != u64(-1)
	descriptor := mangled_fixture(base, integer); name := base + u64(page) + 256; slot := name + 64
	for flags in [u32(0x50), 0x51, 0x52]! {
		write32(descriptor, flags)
		for tag in [u8(1), 2]! {
			unsafe { *(&u64(slot)) = descriptor }
			mangled_symbolic(name, tag, if tag == 1 { descriptor } else { slot })
			mangled_case(lookup, probe, name, 5, 0, 0, integer)
			for length in u64(1) .. 5 { assert lookup(name, length, 0, 0) == 0 }
		}
	}
	write32(descriptor, 0xd1); mangled_reject(name, 5, 0, 0)
	write32(descriptor, 0x43); mangled_reject(name, 5, 0, 0)
	write32(descriptor, 0x51); write32(descriptor + 12, 0); mangled_reject(name, 5, 0, 0)
	// The fixture's tail bridge runs a V accessor that waits for another
	// metadata reader. Its completion proves no runtime lock crosses calls.
	assert C.mprotect(unsafe { voidptr(base) }, page, C.PROT_READ | C.PROT_WRITE) == 0
	write32(base, 0x58000050); write32(base + 4, 0xd61f0200)
	unsafe { *(&u64(base + 8)) = u64(voidptr(mangled_reentry_access)) }
	C.__builtin___clear_cache(unsafe { voidptr(base) }, unsafe { voidptr(base + 16) })
	assert C.mprotect(unsafe { voidptr(base) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	swift_protocol_relative(descriptor + 12, base)
	mangled_reentry_calls = 0
	assert lookup(name, 5, 0, 0) == integer && mangled_reentry_calls == 1
	unsafe { *(&u8(name + 5)) = `?` }; mangled_reject(name, 6, 0, 0)
	assert mangled_reentry_calls == 1 // Full syntax is checked before callbacks.
	assert C.mprotect(unsafe { voidptr(base) }, page, C.PROT_READ | C.PROT_WRITE) == 0
	unsafe { *(&u64(base + 8)) = u64(voidptr(mangled_incomplete_access)) }
	C.__builtin___clear_cache(unsafe { voidptr(base) }, unsafe { voidptr(base + 16) })
	assert C.mprotect(unsafe { voidptr(base) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	mangled_reject(name, 5, 0, 0)
	unsafe { *(&u64(slot)) = 0 }; mangled_reject(name, 5, 0, 0)
	assert C.munmap(unsafe { voidptr(base) }, page * 2) == 0
	mut workers := []thread u64{}
	for _ in 0 .. 8 { workers << spawn mangled_worker() }
	results := workers.wait()
	for metadata in results { assert metadata == swift_array_access(0, text).metadata }
	assert ios_runtime.objects.len == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.live == 0
}

fn test_swift_mangled_lookup() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0503f3, 0xaa0403f0,
		0xd28a0414, 0xd28a0435, 0xd63f0200, 0xa9005260, 0xf9000a75, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	C.__builtin___clear_cache(unsafe { voidptr(code) }, unsafe { voidptr(code + 56) })
	assert C.mprotect(unsafe { voidptr(code) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { MangledProbe(voidptr(code)) }
	mangled_native(probe)
	for _ in 0 .. 2 {
		objc_start(); mangled_suite(probe)
		objc_stop()
		assert ios_runtime.swift_array_metadata.len == 0 && ios_runtime.swift_array_arena == 0
		assert ios_runtime.swift_metadata_arena == 0 && ios_runtime.swift_integer_arena == 0
		assert ios_runtime.swift_void_arena == 0 && ios_runtime.swift_objc_metadata.len == 0
	}
	assert C.munmap(unsafe { voidptr(code) }, page) == 0
	println('IOS-SWIFT-MANGLED: canonical bounded metadata, embedded zeros, nested Arrays, ObjC names, generic Array substitution, direct/indirect class/struct/enum accessors, guarded raw ABI, protected boundaries, unsupported contexts/expressions, complete-response validation, unlocked reentrant accessors, eight readers and two drained cycles')
}
