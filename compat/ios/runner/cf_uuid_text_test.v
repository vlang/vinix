// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#include <CoreFoundation/CFUUID.h>
	@[typedef]
	struct C.CFUUIDBytes {
		byte0 u8 byte1 u8 byte2 u8 byte3 u8 byte4 u8 byte5 u8 byte6 u8 byte7 u8
		byte8 u8 byte9 u8 byte10 u8 byte11 u8 byte12 u8 byte13 u8 byte14 u8 byte15 u8
	}
	fn C.CFUUIDCreateFromUUIDBytes(voidptr, C.CFUUIDBytes) voidptr
	fn C.CFUUIDGetUUIDBytes(voidptr) C.CFUUIDBytes
	fn C.CFUUIDCreateString(voidptr, voidptr) voidptr
	fn C.CFUUIDCreateFromString(voidptr, voidptr) voidptr
	fn C.CFStringGetCString(voidptr, &u8, i64, u32) bool
	fn C.CFStringGetLength(voidptr) i64
	fn C.CFStringGetTypeID() u64
	fn C.CFGetTypeID(voidptr) u64
	fn C.CFGetRetainCount(voidptr) i64
	fn C.CFRetain(voidptr) voidptr
	fn C.CFAllocatorGetDefault() voidptr
}

type UUIDTextCall = fn (u64, u64) u64
type UUIDTextProbe = fn (u64, u64, u64, u64, u64, &u64)

fn uuid_text_emit(code u64) {
	// Allocator/UUID in x0/x1, protected x2–x8, preserved x20/x21.
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0503f3, 0xaa0003f0,
		0xaa0103e0, 0xaa0203e1, 0xaa0303e2, 0xaa0403e3, 0xaa0303e4, 0xaa0303e5,
		0xaa0303e6, 0xaa0303e7, 0xaa0303e8, 0xaa0303f4, 0xd2824695, 0xd63f0200,
		0xa9000660, 0xa9015674, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
}

fn uuid_text_raw(entry u64, allocator u64, uuid u64, code u64, guard u64) u64 {
	mut capture := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	unsafe { UUIDTextProbe(voidptr(code))(entry, allocator, uuid, guard, guard, &capture[1]) }
	assert capture[0] == 0xcafe && capture[3] == guard && capture[4] == 0x1234 && capture[5] == 0xbeef
	return capture[1]
}

fn uuid_text_sample(index int) [16]u8 {
	if index == 259 { return [u8(0x12), 0x3e, 0x45, 0x67, 0xe8, 0x9b, 0x12, 0xd3, 0xa4, 0x56, 0x42, 0x66, 0x14, 0x17, 0x40, 0]! }
	mut bytes := [16]u8{}
	for i in 0 .. 16 { bytes[i] = if index == 256 { u8(0) } else if index == 257 { u8(255) } else if index == 258 { u8(i) } else { u8((index + i * 17) & 255) } }
	return bytes
}

fn uuid_text_known(index int) string {
	return match index {
		256 { '00000000-0000-0000-0000-000000000000' }
		257 { 'FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF' }
		258 { '00010203-0405-0607-0809-0A0B0C0D0E0F' }
		259 { '123E4567-E89B-12D3-A456-426614174000' }
		else { '' }
	}
}

fn uuid_text_cases(entry u64, allocator u64, code u64, guard u64, native bool) {
	for i in 0 .. 260 {
		bytes := uuid_text_sample(i)
		mut words := [2]u64{}; unsafe { C.memcpy(&words[0], &bytes[0], 16) }
		mut uuid := u64(0)
		mut pool := u64(0)
		if native {
			$if macos {
				mut raw := C.CFUUIDBytes{}; unsafe { C.memcpy(&raw, &bytes[0], 16) }
				uuid = u64(C.CFUUIDCreateFromUUIDBytes(unsafe { nil }, raw))
				pool = u64(C.objc_autoreleasePoolPush())
			}
		} else { uuid = cf_uuid_create_from_uuid_bytes(0, words[0], words[1]); pool = objc_pool_push() }
		assert uuid != 0
		text := uuid_text_raw(entry, if i & 1 == 0 { u64(0) } else { allocator }, uuid, code, guard)
		assert text != 0
		mut buffer := [37]u8{}
		if native {
			$if macos {
				assert C.CFGetTypeID(voidptr(text)) == C.CFStringGetTypeID() && C.CFStringGetLength(voidptr(text)) == 36
				assert C.CFGetRetainCount(voidptr(text)) == 1 && C.CFGetRetainCount(voidptr(uuid)) == 1
				assert C.CFRetain(voidptr(text)) == voidptr(text) && C.CFGetRetainCount(voidptr(text)) == 2
				C.CFRelease(voidptr(text)); C.CFRelease(voidptr(uuid)); C.objc_autoreleasePoolPop(voidptr(pool))
				assert C.CFGetRetainCount(voidptr(text)) == 1 && C.CFStringGetCString(voidptr(text), &buffer[0], 37, 0x08000100)
				parsed := C.CFUUIDCreateFromString(unsafe { nil }, voidptr(text))
				raw := C.CFUUIDGetUUIDBytes(parsed); assert unsafe { C.memcmp(&raw, &bytes[0], 16) } == 0
				C.CFRelease(parsed); C.CFRelease(voidptr(text))
			}
		} else {
			header := obj_header(text)
			assert header.refs == 1 && header.cls == ios_runtime.names['NSString'] && obj_header(uuid).refs == 1
			assert objc_retain(text) == text && header.refs == 2; objc_release(text)
			objc_release(uuid); assert objc_pool().objects.len == 0; objc_pool_pop(pool)
			assert header.refs == 1 && header.text_length == 36 && unsafe { header.text[36] } == 0
			unsafe { C.memcpy(&buffer[0], header.text, 37) }
			parsed := cf_uuid_create_from_string(0, text)
			assert unsafe { C.memcmp(&obj_header(parsed).uuid_bytes[0], &bytes[0], 16) } == 0
			objc_release(parsed); objc_release(text)
		}
		assert buffer[36] == 0
		for position in 0 .. 36 {
			assert if position in [8, 13, 18, 23]! { buffer[position] == `-` }
				else { (buffer[position] >= `0` && buffer[position] <= `9`) || (buffer[position] >= `A` && buffer[position] <= `F`) }
		}
		if i >= 256 { assert unsafe { tos(&buffer[0], 36) } == uuid_text_known(i) }
	}
}

fn uuid_text_rejections(guard u64, null_allocator u64) {
	uuid := cf_uuid_create_from_uuid_bytes(0, 0, 0)
	other := objc_allocate(ios_runtime.names['NSObject'])
	ns := objc_allocate(ios_runtime.names['NSUUID'])
	text := owned_string('00000000-0000-0000-0000-000000000000')
	stale := cf_uuid_create_from_uuid_bytes(0, 1, 2); objc_release(stale)
	baseline := ios_runtime.live
	for invalid in [u64(0), 1, guard, ios_runtime.names['VinixCFUUID'], ios_runtime.names['NSString'], other, ns, text, stale]! {
		if _ := cf_uuid_create_string_checked(0, invalid) { assert false }
		assert ios_runtime.live == baseline
	}
	for invalid in [u64(1), guard, null_allocator, ios_runtime.names['NSObject']]! {
		if _ := cf_uuid_create_string_checked(invalid, uuid) { assert false }
		assert ios_runtime.live == baseline
	}
	mut header := obj_header(uuid)
	header.destroyed = true
	if _ := cf_uuid_create_string_checked(0, uuid) { assert false }
	header.destroyed = false; header.refs = 0
	if _ := cf_uuid_create_string_checked(0, uuid) { assert false }
	header.refs = 1
	assert ios_runtime.live == baseline && obj_header(uuid).refs == 1
	objc_release(uuid); objc_release(other); objc_release(ns); objc_release(text)
}

fn uuid_text_worker(call UUIDTextCall, allocator u64, uuid u64) {
	for _ in 0 .. 200 {
		text := call(allocator, uuid)
		assert obj_header(text).refs == 1 && string_text(text) == '00010203-0405-0607-0809-0A0B0C0D0E0F'
		objc_release(text)
	}
}

fn test_cf_uuid_text() {
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page * 2, 3, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != unsafe { voidptr(-1) }; defer { assert C.munmap(code, page * 2) == 0 }
	uuid_text_emit(u64(code)); C.__builtin___clear_cache(code, voidptr(u64(code) + 92))
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := u64(code) + u64(page); assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	$if macos {
		uuid_text_cases(u64(unsafe { voidptr(C.CFUUIDCreateString) }), u64(C.CFAllocatorGetDefault()), u64(code), guard, true)
		println('NATIVE-CF-UUID-TEXT: two-pointer owned CFString ABI, protected x2–x8 and preserved x20/x21, 260 canonical uppercase cases, every byte value at every position, four known strings, exact parse round trips, source/pool independence and balanced retains')
	}
	if _ := cf_uuid_create_string_checked(0, 0) { assert false }
	for _ in 0 .. 2 {
		objc_start()
		lib := '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation'
		entry := runtime_symbol(lib, '_CFUUIDCreateString') or { panic(err) }
		call := unsafe { UUIDTextCall(voidptr(entry)) }
		allocator := read64(runtime_symbol(lib, '_kCFAllocatorSystemDefault') or { panic(err) })
		null_allocator := read64(runtime_symbol(lib, '_kCFAllocatorNull') or { panic(err) })
		baseline := ios_runtime.live
		uuid_text_cases(entry, allocator, u64(code), guard, false)
		uuid_text_rejections(guard, null_allocator)
		assert ios_runtime.live == baseline && objc_pool().objects.len == 0
		uuid := cf_uuid_create_from_uuid_bytes(0, 0x0706050403020100, 0x0f0e0d0c0b0a0908)
		mut workers := []thread{}
		for i in 0 .. 8 { workers << spawn uuid_text_worker(call, if i & 1 == 0 { u64(0) } else { allocator }, uuid) }
		workers.wait(); unsafe { workers.free() }
		assert obj_header(uuid).refs == 1 && ios_runtime.live == baseline + 1
		text := call(0, uuid); objc_release(uuid)
		holder := objc_allocate(ios_runtime.names['NSArray']); mut header := obj_header(holder); array_append(mut header, text)
		mut weak := u64(0); objc_store_weak(unsafe { &weak }, text)
		objc_release(text); assert weak != 0 && obj_header(weak).refs == 1
		objc_release(holder); assert weak == 0 && ios_runtime.live == baseline
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! {
			if _ := runtime_symbol(library, '_CFUUIDCreateString') { assert false }
		}
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.swift_concurrency_retired
		if _ := cf_uuid_create_string_checked(0, 0) { assert false }
	}
	println('IOS-CF-UUID-TEXT: scoped two-pointer owned CFString ABI, protected x2–x8 and preserved x20/x21, 260 canonical uppercase cases, four known strings and exact parse round trips, nil/stale/foreign/allocator rejection, unchanged UUID references, collection/weak and source/pool independence, eight concurrent readers, no autoreleases and two zero-live-object teardowns')
}
