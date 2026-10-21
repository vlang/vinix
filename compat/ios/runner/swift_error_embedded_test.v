// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFError.h>
	#include <CoreFoundation/CFString.h>
}
#include <dlfcn.h>
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
fn C.CFStringCreateWithBytes(voidptr,&u8,i64,u32,bool) voidptr
fn C.CFErrorCreate(voidptr,voidptr,i64,voidptr) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRelease(voidptr)
type EeProbe = fn (u64,u64,u64,u64,&u64,u64)
type EeGet = fn (u64,&u64,&SwiftErrorValue)
const ee_symbol = '_$ss5ErrorPsE19_getEmbeddedNSErroryXlSgyF'

fn ee_control() u64 { return 0xfeed1234 }
fn ee_emit(code u64) {
	// Self, metadata, table, entry, output, x8. Capture x0 and the three
	// callee-saved Swift contexts; a nonzero control checks the adapter too.
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0403f3,
		0xaa0303f0, 0xaa0003f4, 0xaa0103e0, 0xaa0203e1,
		u32(0xd2800000 | (0x5121 << 5) | 21), u32(0xd2800000 | (0x5222 << 5) | 22),
		0xaa0503e8, 0xd63f0200, 0xf9000260, 0xa900d674, 0xf9000e76,
		0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
}
fn ee_expect(probe EeProbe, entry u64, source u64, metadata u64, table u64, guard u64, expected u64) {
	mut output := [u64(0x12345678), ~u64(0), ~u64(0), ~u64(0), ~u64(0), 0x87654321]!
	probe(source, metadata, table, entry, unsafe { &output[1] }, guard)
	assert output[0] == 0x12345678 && output[5] == 0x87654321
	assert output[1] == expected && output[2] == source && output[3] == 0x5121 && output[4] == 0x5222
}
fn ee_cases(probe EeProbe, entry u64, guard u64) {
	values := [u64(0), 1, guard, guard + u64(C.getpagesize()), ~u64(0)]!
	for source in values { for metadata in values { for table in values {
		ee_expect(probe, entry, source, metadata, table, guard, 0)
	} } }
}
fn ee_native(probe EeProbe, guard u64) {
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		assert lib != unsafe { nil }
		entry := u64(C.dlsym(lib, unsafe { &char(ee_symbol.str + 1) }))
		get_entry := C.dlsym(lib, c'swift_getErrorValue')
		assert entry != 0 && get_entry != unsafe { nil }
		ee_cases(probe, entry, guard)
		text := 'embedded NSError default ownership fixture'
		domain := C.CFStringCreateWithBytes(unsafe { nil }, text.str, i64(text.len), 0x08000100, false)
		owner := C.CFErrorCreate(unsafe { nil }, domain, -17, unsafe { nil })
		assert owner != unsafe { nil }; C.CFRelease(domain)
		before := C.CFGetRetainCount(owner)
		get := unsafe { EeGet(get_entry) }
		mut scratch := u64(0); mut value := SwiftErrorValue{}
		get(u64(owner), unsafe { &scratch }, unsafe { &value })
		assert scratch == u64(owner) && value.value == u64(unsafe { &scratch })
		for _ in 0 .. 32 { ee_expect(probe, entry, value.value, value.metadata, value.witness, guard, 0) }
		assert scratch == u64(owner) && C.CFGetRetainCount(owner) == before
		// The concrete CFError override returns an owned object. Calling the
		// default with that same table must still return nil without dispatch.
		ee_expect(probe, read64(value.witness + 32) & 0x0000ffffffffffff, value.value, value.metadata, value.witness, guard, u64(owner))
		assert C.CFGetRetainCount(owner) == before + 1
		C.CFRelease(owner); assert C.CFGetRetainCount(owner) == before
		C.CFRelease(owner)
		println('NATIVE-ERROR-EMBEDDED: nil default, 125 opaque argument combinations, ignored protected x8, preserved x20/x21/x22, unchanged borrowed CFError ownership and distinct retained concrete override')
	}
}
fn ee_resolver() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', ee_symbol) or { panic(err) }
}
fn ee_worker(probe EeProbe, entry u64, guard u64) {
	for _ in 0 .. 32 { assert ee_resolver() == entry; ee_cases(probe, entry, guard) }
}
fn test_swift_error_embedded() {
	$if !arm64 { return }
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != ~u64(0)
	defer { assert C.munmap(voidptr(code), page * 2) == 0 }
	guard := code + u64(page)
	ee_emit(code)
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 76))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	probe := unsafe { EeProbe(voidptr(code)) }
	ee_expect(probe, u64(unsafe { voidptr(ee_control) }), guard, guard, guard, guard, 0xfeed1234)
	ee_native(probe, guard)
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn ee_resolver() }
		entries := publishers.wait()
		for entry in entries { assert entry != 0 && entry == entries[0] }
		assert ios_runtime.swift_error_arena == 0 && ios_runtime.swift_objc_metadata.len == 0
		ee_cases(probe, entries[0], guard)
		domain := owned_string('embedded NSError default ownership fixture')
		owner := objc_allocate(cf_error_type_id())
		mut header := obj_header(owner)
		header.number = -17; header.fields[0] = domain // Transfer the owned domain.
		before := obj_header(owner).refs
		mut scratch := u64(0); mut value := SwiftErrorValue{}
		swift_error_value(owner, unsafe { &scratch }, unsafe { &value })
		for _ in 0 .. 32 { ee_expect(probe, entries[0], value.value, value.metadata, value.witness, guard, 0) }
		assert scratch == owner && obj_header(owner).refs == before
		ee_expect(probe, read64(value.witness + 32), value.value, value.metadata, value.witness, guard, owner)
		assert obj_header(owner).refs == before + 1
		objc_release(owner); assert obj_header(owner).refs == before; objc_release(owner)
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn ee_worker(probe, entries[0], guard) }
		workers.wait()
		for symbol in [ee_symbol + 'Extra', ee_symbol[1..], '_$ss5ErrorP19_getEmbeddedNSErroryXlSgyF']! {
			assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol) == none
		}
		assert runtime_symbol('/usr/lib/libSystem.B.dylib', ee_symbol) == none
		assert ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.objects.len == 0 && ios_runtime.live == 0
		objc_stop()
		assert ios_runtime.swift_error_arena == 0 && ios_runtime.swift_objc_metadata.len == 0
		// This pure default has no runtime state or mapping to become stale.
		assert ee_resolver() == entries[0]; ee_cases(probe, entries[0], guard)
	}
	println('IOS-ERROR-EMBEDDED: nil default with opaque protected arguments/x8, preserved x20/x21/x22, borrowed ownership and concrete override, exact routing, no arena/cache publication, eight cold resolvers/workers and two drained lifetimes')
}
