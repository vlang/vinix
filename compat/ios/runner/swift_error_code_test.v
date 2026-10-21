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
fn C.mincore(voidptr,usize,&u8) i32
type EcProbe = fn (u64,u64,u64,u64,&u64,u64)
type EcSign = fn (u64,u64) u64
type EcGet = fn (u64,&u64,&SwiftErrorValue)
const ec_symbol = '_$ss5ErrorPsE5_codeSivg'

fn ec_control() u64 { return 0xfeed1234 }
fn ec_tag(source u64, metadata u64) u32 {
	assert read64(metadata + 8) == source
	return read32(source)
}
fn ec_emit(code u64) {
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0403f3,
		0xaa0303f0, 0xaa0003f4, 0xaa0103e0, 0xaa0203e1,
		u32(0xd2800000 | (0x5121 << 5) | 21), u32(0xd2800000 | (0x5222 << 5) | 22),
		0xaa0503e8, 0xd63f0200, 0xf9000260, 0xa900d674, 0xf9000e76,
		0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	write32(code + 128, 0xdac10020); write32(code + 132, 0xd65f03c0) // Native PACIA.
	write32(code + 144, 0xdac10820); write32(code + 148, 0xd65f03c0) // Native PACDA.
}
fn ec_expect(probe EcProbe, entry u64, source u64, metadata u64, table u64, guard u64, expected u64) {
	mut output := [u64(0x12345678), ~u64(0), ~u64(0), ~u64(0), ~u64(0), 0x87654321]!
	probe(source, metadata, table, entry, unsafe { &output[1] }, guard)
	assert output[0] == 0x12345678 && output[5] == 0x87654321
	assert output[1] == expected && output[2] == source && output[3] == 0x5121 && output[4] == 0x5222
}
fn ec_suite(probe EcProbe, entry u64, records u64, native bool) {
	page := u64(C.getpagesize()); guard := records + page
	metadata := records + page - 16; witness := records + page * 3 - 96; source := records + page * 5 - 4
	assert C.mprotect(voidptr(records), usize(page), C.PROT_READ | C.PROT_WRITE) == 0
	// A non-enum needs exactly one readable word; its VWT/Self/table/x8 may
	// all be inaccessible. Optional kind 0x202 deliberately follows this path.
	unsafe { *(&u64(metadata)) = guard }
	for kind in [u64(0), 0x200, 0x202, 0x203, 0x300, 0x301, 0x302, 0x303, 0x304, 0x305, ~u64(0)]! {
		unsafe { *(&u64(metadata + 8)) = kind }
		assert C.mprotect(voidptr(records), usize(page), C.PROT_READ) == 0
		for receiver in [u64(0), 1, guard, ~u64(0)]! { ec_expect(probe, entry, receiver, metadata + 8, guard, guard, 1) }
		assert C.mprotect(voidptr(records), usize(page), C.PROT_READ | C.PROT_WRITE) == 0
	}
	assert C.mprotect(voidptr(records + page * 2), usize(page), C.PROT_READ | C.PROT_WRITE) == 0
	mut vwt := witness; mut callback := u64(unsafe { voidptr(ec_tag) })
	$if macos { if native {
		base := u64(unsafe { voidptr(probe) })
		vwt = unsafe { EcSign(voidptr(base + 144))(witness, (metadata - 8) | (u64(11839) << 48)) }
		callback = unsafe { EcSign(voidptr(base + 128))(callback, (witness + 88) | (u64(41909) << 48)) }
	} }
	unsafe { *(&u64(metadata - 8)) = vwt; *(&u64(metadata)) = 0x201; *(&u64(metadata + 8)) = source; *(&u64(witness + 88)) = callback }
	assert C.mprotect(voidptr(records), usize(page), C.PROT_READ) == 0
	assert C.mprotect(voidptr(records + page * 2), usize(page), C.PROT_READ) == 0
	for tag in [u32(0), 1, 2, 127, 255, 65535, 0x7fffffff, 0x80000000, 0xffffffff]! {
		assert C.mprotect(voidptr(records + page * 4), usize(page), C.PROT_READ | C.PROT_WRITE) == 0
		write32(source, tag)
		assert C.mprotect(voidptr(records + page * 4), usize(page), C.PROT_READ) == 0
		ec_expect(probe, entry, source, metadata, guard, guard, u64(tag))
		assert read32(source) == tag
	}
}
fn ec_native(probe EcProbe, records u64) {
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW); assert lib != unsafe { nil }
		entry := u64(C.dlsym(lib, unsafe { &char(ec_symbol.str + 1) }))
		merge := u64(C.dlsym(lib, c'$ss11_MergeErrorON')); get_entry := C.dlsym(lib, c'swift_getErrorValue')
		assert entry != 0 && merge != 0 && get_entry != unsafe { nil }
		ec_suite(probe, entry, records, true)
		guard := records + u64(C.getpagesize())
		for source in [u64(0), guard, ~u64(0)]! { ec_expect(probe, entry, source, merge, guard, guard, 0) }
		text := 'default Error code ownership fixture'
		domain := C.CFStringCreateWithBytes(unsafe { nil }, text.str, i64(text.len), 0x08000100, false)
		owner := C.CFErrorCreate(unsafe { nil }, domain, -17, unsafe { nil }); assert owner != unsafe { nil }; C.CFRelease(domain)
		get := unsafe { EcGet(get_entry) }; mut scratch := u64(0); mut value := SwiftErrorValue{}
		get(u64(owner), unsafe { &scratch }, unsafe { &value }); before := C.CFGetRetainCount(owner)
		ec_expect(probe, entry, value.value, value.metadata, guard, guard, 1)
		ec_expect(probe, read64(value.witness + 16) & 0x0000ffffffffffff, value.value, value.metadata, value.witness, guard, u64(i64(-17)))
		assert scratch == u64(owner) && C.CFGetRetainCount(owner) == before; C.CFRelease(owner)
		println('NATIVE-ERROR-CODE: enum UInt32 tag zero-extension through UINT32_MAX, non-enum/Optional code one, zero-size MergeError, exact borrowed metadata/VWT/value boundaries, protected unused table/x8, preserved x20/x21/x22 and CFError ownership/override')
	}
}
fn ec_resolver() u64 { return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', ec_symbol) or { panic(err) } }
fn ec_reentrant_tag(source u64, metadata u64) u32 {
	worker := spawn ec_resolver(); assert worker.wait() == ios_runtime.swift_error_arena + 160
	return ec_tag(source, metadata)
}
fn ec_worker(probe EcProbe, entry u64, records u64) {
	page := u64(C.getpagesize()); metadata := records + page - 16; source := records + page * 5 - 4
	for _ in 0 .. 256 { assert ec_resolver() == entry; ec_expect(probe, entry, source, metadata, records + page, records + page, 0xffffffff) }
}
fn test_swift_error_code() {
	$if !arm64 { return }
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	records := u64(C.mmap(unsafe { nil }, page * 6, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != ~u64(0) && records != ~u64(0)
	defer { assert C.munmap(voidptr(code), page) == 0; assert C.munmap(voidptr(records), page * 6) == 0 }
	for offset in [1, 3, 5]! { assert C.mprotect(voidptr(records + u64(page * usize(offset))), page, C.PROT_NONE) == 0 }
	ec_emit(code); C.__builtin___clear_cache(voidptr(code), voidptr(code + 152)); assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { EcProbe(voidptr(code)) }; guard := records + u64(page)
	ec_expect(probe, u64(unsafe { voidptr(ec_control) }), guard, guard, guard, guard, 0xfeed1234)
	ec_native(probe, records)
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread u64{}; for _ in 0 .. 8 { publishers << spawn ec_resolver() }; entries := publishers.wait()
		for entry in entries { assert entry != 0 && entry == entries[0] }
		arena := ios_runtime.swift_error_arena; assert entries[0] == arena + 160
		ec_suite(probe, entries[0], records, false)
		merge := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss11_MergeErrorON') or { panic(err) }
		for source in [u64(0), guard, ~u64(0)]! { ec_expect(probe, entries[0], source, merge, guard, guard, 0) }
		domain := owned_string('default Error code ownership fixture'); owner := objc_allocate(cf_error_type_id())
		mut header := obj_header(owner); header.fields[0] = domain; header.number = -17
		mut scratch := u64(0); mut value := SwiftErrorValue{}; swift_error_value(owner, unsafe { &scratch }, unsafe { &value }); before := obj_header(owner).refs
		ec_expect(probe, entries[0], value.value, value.metadata, guard, guard, 1)
		ec_expect(probe, read64(value.witness + 16), value.value, value.metadata, value.witness, guard, u64(i64(-17)))
		assert scratch == owner && obj_header(owner).refs == before; objc_release(owner)
		metadata := records + u64(page) - 16; witness := records + u64(page * 3) - 96; source := records + u64(page * 5) - 4
		assert C.mprotect(voidptr(records + u64(page * 2)), page, C.PROT_READ | C.PROT_WRITE) == 0
		unsafe { *(&u64(witness + 88)) = u64(voidptr(ec_reentrant_tag)) }
		assert C.mprotect(voidptr(records + u64(page * 2)), page, C.PROT_READ) == 0
		ec_expect(probe, entries[0], source, metadata, guard, guard, 0xffffffff)
		assert C.mprotect(voidptr(records + u64(page * 2)), page, C.PROT_READ | C.PROT_WRITE) == 0
		unsafe { *(&u64(witness + 88)) = u64(voidptr(ec_tag)) }
		assert C.mprotect(voidptr(records + u64(page * 2)), page, C.PROT_READ) == 0
		mut workers := []thread{}; for _ in 0 .. 8 { workers << spawn ec_worker(probe, entries[0], records) }; workers.wait()
		for invalid in [u64(0), 1, ~u64(0)]! { if _ := swift_error_code_checked(guard, invalid) { assert false } }
		assert C.mprotect(voidptr(records), page, C.PROT_READ | C.PROT_WRITE) == 0
		for invalid in [u64(0), 1, ~u64(0) - 7]! { unsafe { *(&u64(metadata - 8)) = invalid }; if _ := swift_error_code_checked(source, metadata) { assert false } }
		unsafe { *(&u64(metadata - 8)) = witness }
		assert C.mprotect(voidptr(records), page, C.PROT_READ) == 0
		assert C.mprotect(voidptr(records + u64(page * 2)), page, C.PROT_READ | C.PROT_WRITE) == 0
		for invalid in [u64(0), 1]! { unsafe { *(&u64(witness + 88)) = invalid }; if _ := swift_error_code_checked(source, metadata) { assert false } }
		assert C.mprotect(voidptr(records + u64(page * 2)), page, C.PROT_READ) == 0
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', ec_symbol + 'Extra') == none
		assert runtime_symbol('/usr/lib/libSystem.B.dylib', ec_symbol) == none
		ios_runtime.swift_concurrency_retired = true
		if _ := swift_error_code_checked(guard, guard) { assert false }; assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', ec_symbol) == none
		ios_runtime.swift_concurrency_retired = false
		assert ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.objects.len == 0 && ios_runtime.live == 0
		objc_stop(); assert ios_runtime.swift_error_arena == 0
		if _ := swift_error_code_checked(guard, guard) { assert false }
		for offset in [usize(0), page]! {
			$if macos { assert C.mprotect(voidptr(arena + u64(offset)), page, C.PROT_READ) == -1 }
			$else { mut resident := u8(0); assert C.mincore(voidptr(arena + u64(offset)), page, unsafe { &resident }) == -1 }
		}
	}
	println('IOS-ERROR-CODE: native enum/non-enum default codes, exact readonly metadata/VWT/value spans and UINT32_MAX, borrowed ownership, preserved contexts, reentrant tag callback, guarded validation/retired rejection, eight cold publishers/workers and two drained/unmapped lifetimes')
}
