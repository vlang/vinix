// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
#include <dlfcn.h>
$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFString.h>
}
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
fn C.dlclose(voidptr) i32
fn C.CFStringCreateWithBytes(voidptr,&u8,i64,u32,bool) voidptr
fn C.CFStringCreateMutableCopy(voidptr,i64,voidptr) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRelease(voidptr)
type ForeignCopyCall = fn (u64,i64,u64,u64) SwiftOptionalInt
const foreign_copy_symbol = '_$ss11_StringGutsV16_foreignCopyUTF84intoSiSgSrys5UInt8VG_tF'
fn foreign_copy_result(result SwiftOptionalInt, text string, capacity int, native bool) {
	// Native NSString's getBytes can use maxLength=0 as a count query even
	// with a nonnil buffer. This varies with NSString's backing representation.
	// Keep this measurement separate from V's checked capacity contract.
	if native && capacity == 0 && text.len != 0 {
		assert result.is_nil & 0xff == 1 || (result.is_nil & 0xff == 0 && result.value == text.len)
		return
	}
	assert result.is_nil & 0xff == if capacity < text.len {u64(1)} else {u64(0)}
	if capacity >= text.len { assert result.value == text.len }
}
fn foreign_copy_units(text string) u64 {
	mut units := u64(0)
	for b in text { if b & 0xc0 != 0x80 { units += if b >= 0xf0 {u64(2)} else {u64(1)} } }
	return units
}
fn foreign_copy_case(call ForeignCopyCall, text string, first u64, second u64, capacity int, offset int, native bool) {
	mut bytes := [128]u8{}; for i in 0 .. 128 { bytes[i] = 0xa5 }
	start := u64(unsafe { &bytes[0] }) + u64(offset)
	result := call(start,i64(capacity),first,second)
	foreign_copy_result(result,text,capacity,native)
	for i in 0 .. 128 {
		if capacity >= text.len && i >= offset && i < offset + text.len { assert bytes[i] == text[i - offset] }
		else if !native || i < offset || i >= offset + capacity { assert bytes[i] == 0xa5 }
	}
}
fn foreign_copy_ranges(call ForeignCopyCall,text string,first u64,second u64,native bool) int {
	mut cases := 0
	for capacity in 0 .. text.len + 3 {
		for offset in [1,7]! { foreign_copy_case(call,text,first,second,capacity,offset,native); cases++ }
	}
	page := u64(C.getpagesize()); mapping := u64(C.mmap(unsafe { nil },usize(page * 3),C.PROT_NONE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0))
	assert mapping != u64(-1); assert C.mprotect(voidptr(mapping + page),usize(page),C.PROT_READ | C.PROT_WRITE) == 0
	for capacity in [0,text.len,text.len + 1]! {
		start := mapping + page * 2 - u64(capacity)
		if capacity != 0 { C.memset(voidptr(start),0xa5,usize(capacity)) }
		result := call(start,i64(capacity),first,second)
		foreign_copy_result(result,text,capacity,native)
		if capacity >= text.len {
			assert result.value == text.len
			for i in 0 .. text.len { assert unsafe { *(&u8(start + u64(i))) } == text[i] }
			if capacity > text.len { assert unsafe { *(&u8(start + u64(text.len))) } == 0xa5 }
		}
		cases++
	}
	assert C.munmap(voidptr(mapping),usize(page * 3)) == 0
	return cases
}
fn foreign_copy_worker(call ForeignCopyCall,text string,first u64,second u64) {
	for _ in 0 .. 100 { foreign_copy_case(call,text,first,second,text.len + 1,3,false); foreign_copy_case(call,text,first,second,1,3,false) }
}
fn foreign_copy_constants(call ForeignCopyCall) {
	text := 'Constant\x00NSString 🎮'; mut record := [ios_runtime.names['NSString'],u64(0x7c8),u64(text.str),u64(text.len)]!
	address := u64(unsafe { &record[0] }); ios_runtime.constants[address] = true
	foreign_copy_ranges(call,text,foreign_copy_units(text),address | u64(0xd000000000000000),false)
	ios_runtime.constants.delete(address)
	wide := [u16(0x41),0,0xd83c,0xdfae,0x3c0,0]!
	record[1] = 0x7d0; record[2] = u64(unsafe { &wide[0] }); record[3] = 5
	ios_runtime.constants[address] = true
	metadata := ObjMetadata{image:macho.Image{segments:[macho.Segment{name:'__TEXT',address:0,filesize:12,prot:1}]},layout:macho.Layout{size:12},base:record[2]}
	metadata.constant_string(address) or { panic(err) }; unsafe { metadata.image.segments.free() }
	foreign_copy_ranges(call,'A\x00🎮π',5,address | u64(0xd000000000000000),false)
	ios_runtime.constants.delete(address)
	cached := ios_runtime.constant_utf8[address] or { panic('missing decoded constant') }
	ios_runtime.constant_utf8.delete(address); unsafe { cached.free() }
}
fn foreign_copy_invalid() {
	mut bytes := [64]u8{}; for i in 0 .. 64 { bytes[i] = 0xa5 }; start := u64(unsafe { &bytes[0] })
	owner := owned_string('π🎮'); second := owner | u64(0x5000000000000000)
	for pair in [[u64(0),u64(1)]!,[start,u64(-1)]!,[u64(-2),u64(4)]!]! {
		if _ := swift_foreign_copy_checked(pair[0],i64(pair[1]),3,second) { assert false }
	}
	page := usize(C.getpagesize()); guard := C.mmap(unsafe { nil },page,C.PROT_NONE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0); assert guard != unsafe { voidptr(-1) }
	for unknown in [u64(0),1,u64(guard)]! { if _ := swift_foreign_copy_checked(start,64,3,unknown | u64(0x5000000000000000)) { assert false } }
	for discriminator in [u64(0),4,6,7,8,9,12,14,15]! { if _ := swift_foreign_copy_checked(start,64,3,owner | (discriminator << 60)) { assert false } }
	for first in [u64(4),u64(3) | (u64(1) << 48),u64(3) | (u64(1) << 59)]! { if _ := swift_foreign_copy_checked(start,64,first,second) { assert false } }
	objc_release(owner); if _ := swift_foreign_copy_checked(start,64,3,second) { assert false }
	wrong := objc_allocate(ios_runtime.names['NSObject']); if _ := swift_foreign_copy_checked(start,64,0,wrong | u64(0x5000000000000000)) { assert false }; objc_release(wrong)
	invalid := owned_string('\xc0\x80'); if _ := swift_foreign_copy_checked(start,64,1,invalid | u64(0x5000000000000000)) { assert false }; objc_release(invalid)
	broken := objc_allocate(ios_runtime.names['NSString']); mut header := obj_header(broken); header.text = unsafe { &char(1) }; header.text_length = 1048577
	if _ := swift_foreign_copy_checked(start,64,1,broken | u64(0x5000000000000000)) { assert false }
	header.text_length = -1; if _ := swift_foreign_copy_checked(start,64,0,broken | u64(0x5000000000000000)) { assert false }
	header.text = unsafe { nil }; header.text_length = 1; if _ := swift_foreign_copy_checked(start,64,1,broken | u64(0x5000000000000000)) { assert false }
	header.text_length = 0; objc_release(broken)
	for b in bytes { assert b == 0xa5 }; assert C.munmap(guard,page) == 0
}
fn test_swift_foreign_copy() {
	texts := ['', 'Fortnite', 'a\x00b', 'π🎮', 'Aé€🎮é', 'long\x00 embedded NUL unicode π🎮', 'αβγδεζηθικλμνξοπρστυφχψω']!
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',C.RTLD_NOW); assert core != unsafe { nil }
		entry := C.dlsym(core,c'$ss11_StringGutsV16_foreignCopyUTF84intoSiSgSrys5UInt8VG_tF'); assert entry != unsafe { nil }
		call := unsafe { ForeignCopyCall(entry) }; mut cases := 0
		for text in texts {
			immutable := C.CFStringCreateWithBytes(unsafe { nil },text.str,i64(text.len),0x08000100,false); assert immutable != unsafe { nil }
			owner := C.CFStringCreateMutableCopy(unsafe { nil },0,immutable); assert owner != unsafe { nil }; C.CFRelease(immutable)
			before := C.CFGetRetainCount(owner)
			cases += foreign_copy_ranges(call,text,foreign_copy_units(text),u64(owner) | u64(0x5000000000000000),true)
			assert C.CFGetRetainCount(owner) == before; C.CFRelease(owner)
		}
		assert C.dlclose(core) == 0
		println('IOS-FOREIGN-COPY-NATIVE: destination/count x0/x1, borrowed foreign guts x2/x3, Optional<Int> payload x0/tag x1; '+cases.str()+' capacity/unaligned/page-edge cases, all UTF8 widths, embedded NUL, unchanged source ownership and guarded destination neighbours')
	}
	if _ := swift_foreign_copy_checked(0,0,0,0) { assert false }
	for _ in 0 .. 2 {
		objc_start(); baseline := ios_runtime.live
		call := unsafe { ForeignCopyCall(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib',foreign_copy_symbol) or { panic(err) })) }
		for text in texts {
			owner := owned_string(text); first := foreign_copy_units(text); second := owner | u64(0x5000000000000000)
			foreign_copy_ranges(call,text,first,second,false)
			foreign_copy_case(call,text,first | u64(0xc000000000000000),second,text.len + 1,5,false)
			if text.len == 0 { result := call(0,0,first,second); assert result.is_nil == 0 && result.value == 0 }
			mut workers := []thread{}; for _ in 0 .. 4 { workers << spawn foreign_copy_worker(call,text,first,second) }; workers.wait(); unsafe { workers.free() }
			assert obj_header(owner).refs == 1 && string_text(owner) == text; objc_release(owner)
		}
		foreign_copy_constants(call); foreign_copy_invalid()
		for library in ['/usr/lib/libSystem.B.dylib','/usr/lib/swift/libswiftFoundation.dylib']! { assert runtime_symbol(library,foreign_copy_symbol) == none }
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib',foreign_copy_symbol[1..]) == none
		assert ios_runtime.live == baseline && ios_runtime.objects.len == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0
		objc_stop(); if _ := swift_foreign_copy_checked(0,0,0,0) { assert false }
	}
	println('IOS-FOREIGN-COPY: checked borrowed NSString/decoded constants, exact UTF8 payload and Optional<Int>, nil without writes for insufficient capacity, protected empty ranges, invalid span/owner/flags/count/text rejection, four readers and two drained runtimes')
}
