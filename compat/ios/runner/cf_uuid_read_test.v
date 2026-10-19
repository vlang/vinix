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
	fn C.CFGetRetainCount(voidptr) i64
}

type UUIDReadCall = fn (u64) CFUUIDWords
type UUIDReadProbe = fn (u64, u64, u64, u64, u64, &u8)

fn uuid_read_emit(code u64) {
	// UUID in x0, protected x1–x8, preserved x20/x21. Reproduce Fortnite's
	// unaligned STUR x0/[+5] and STUR x1/[+13] result stores into a guard frame.
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0503f3, 0xaa0003f0,
		0xaa0103e0, 0xaa0203e1, 0xaa0303e2, 0xaa0403e3, 0xaa0303e4, 0xaa0303e5,
		0xaa0303e6, 0xaa0303e7, 0xaa0303e8, 0xaa0303f4, 0xd2824695, 0xd63f0200,
		0xf8005260, 0xf800d261, 0xa901d674, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
}

fn uuid_read_raw(entry u64, uuid u64, code u64, guard u64) CFUUIDWords {
	mut capture := [48]u8{init: 0xa5}
	unsafe { UUIDReadProbe(voidptr(code))(entry, uuid, guard, guard, guard, &capture[0]) }
	for i in [0, 1, 2, 3, 4, 21, 22, 23, 40, 41, 42, 43, 44, 45, 46, 47]! { assert capture[i] == 0xa5 }
	mut preserved := [2]u64{}
	mut result := CFUUIDWords{}
	unsafe { C.memcpy(&preserved[0], &capture[24], 16); C.memcpy(&result, &capture[5], 16) }
	assert preserved[0] == guard && preserved[1] == 0x1234
	return result
}

fn uuid_read_sample(index int, guard u64) [16]u8 {
	mut bytes := [16]u8{}
	if index == 260 {
		words := [guard, ~guard]!
		unsafe { C.memcpy(&bytes[0], &words[0], 16) }
	} else {
		for i in 0 .. 16 { bytes[i] = if index == 256 { u8(0) } else if index == 257 { u8(255) } else if index == 258 { u8(i) } else if index == 259 { u8(255 - i) } else { u8((index + i * 17) & 255) } }
	}
	return bytes
}

fn uuid_read_cases(entry u64, code u64, guard u64, native bool) {
	for i in 0 .. 261 {
		bytes := uuid_read_sample(i, guard)
		mut input := [2]u64{}; unsafe { C.memcpy(&input[0], &bytes[0], 16) }
		mut uuid := u64(0)
		mut pool := u64(0)
		if native {
			$if macos {
				mut raw := C.CFUUIDBytes{}; unsafe { C.memcpy(&raw, &bytes[0], 16) }
				uuid = u64(C.CFUUIDCreateFromUUIDBytes(unsafe { nil }, raw))
				pool = u64(C.objc_autoreleasePoolPush())
			}
		} else { uuid = cf_uuid_create_from_uuid_bytes(0, input[0], input[1]); pool = objc_pool_push() }
		assert uuid != 0
		words := uuid_read_raw(entry, uuid, code, guard)
		assert sizeof(words) == 16 && words.first == input[0] && words.second == input[1]
		if native {
			$if macos {
				assert C.CFGetRetainCount(voidptr(uuid)) == 1
				C.CFRelease(voidptr(uuid)); C.objc_autoreleasePoolPop(voidptr(pool))
			}
		} else {
			assert obj_header(uuid).refs == 1 && unsafe { C.memcmp(&obj_header(uuid).uuid_bytes[0], &bytes[0], 16) } == 0
			assert objc_pool().objects.len == 0; objc_pool_pop(pool); objc_release(uuid)
		}
		// The aggregate has no owner, buffer pointer or source lifetime dependency.
		assert unsafe { C.memcmp(&words, &bytes[0], 16) } == 0
	}
}

fn uuid_read_rejections(guard u64) {
	uuid := cf_uuid_create_from_uuid_bytes(0, 1, 2)
	other := objc_allocate(ios_runtime.names['NSObject'])
	ns := objc_allocate(ios_runtime.names['NSUUID'])
	text := owned_string('00000000-0000-0000-0000-000000000000')
	stale := cf_uuid_create_from_uuid_bytes(0, 3, 4); objc_release(stale)
	baseline := ios_runtime.live
	for invalid in [u64(0), 1, guard, ios_runtime.names['VinixCFUUID'], ios_runtime.names['NSString'], other, ns, text, stale]! {
		if _ := cf_uuid_get_uuid_bytes_checked(invalid) { assert false }
		assert ios_runtime.live == baseline
	}
	mut header := obj_header(uuid)
	header.destroyed = true
	if _ := cf_uuid_get_uuid_bytes_checked(uuid) { assert false }
	header.destroyed = false; header.refs = 0
	if _ := cf_uuid_get_uuid_bytes_checked(uuid) { assert false }
	header.refs = 1
	assert ios_runtime.live == baseline && obj_header(uuid).refs == 1
	objc_release(uuid); objc_release(other); objc_release(ns); objc_release(text)
}

fn uuid_read_worker(call UUIDReadCall, uuid u64) {
	for _ in 0 .. 500 {
		value := call(uuid)
		assert value.first == 0x0706050403020100 && value.second == 0x0f0e0d0c0b0a0908
	}
}

fn uuid_read_constructors(call UUIDReadCall) {
	text := owned_string('00010203-0405-0607-0809-0A0B0C0D0E0F')
	parsed := cf_uuid_create_from_string(0, text); objc_release(text)
	value := call(parsed); objc_release(parsed)
	assert value.first == 0x0706050403020100 && value.second == 0x0f0e0d0c0b0a0908
	random := cf_uuid_create(0)
	copy := call(random)
	assert unsafe { C.memcmp(&copy, &obj_header(random).uuid_bytes[0], 16) } == 0
	objc_release(random)
	mut bytes := [16]u8{}; unsafe { C.memcpy(&bytes[0], &copy, 16) }
	assert bytes[6] >> 4 == 4 && bytes[8] >> 6 == 2
}

fn test_cf_uuid_read() {
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page * 2, 3, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != unsafe { voidptr(-1) }; defer { assert C.munmap(code, page * 2) == 0 }
	uuid_read_emit(u64(code)); C.__builtin___clear_cache(code, voidptr(u64(code) + 96))
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := u64(code) + u64(page); assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	$if macos {
		uuid_read_cases(u64(unsafe { voidptr(C.CFUUIDGetUUIDBytes) }), u64(code), guard, true)
		println('NATIVE-CF-UUID-READ: one-pointer 16-byte aggregate return in x0/x1, protected x1–x8, preserved x20/x21, unaligned result stores at +5/+13 with intact canaries, 261 exact payloads, unchanged references and copies surviving source/pool release')
	}
	if _ := cf_uuid_get_uuid_bytes_checked(0) { assert false }
	for _ in 0 .. 2 {
		objc_start()
		lib := '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation'
		entry := runtime_symbol(lib, '_CFUUIDGetUUIDBytes') or { panic(err) }
		call := unsafe { UUIDReadCall(voidptr(entry)) }
		baseline := ios_runtime.live
		uuid_read_cases(entry, u64(code), guard, false)
		uuid_read_rejections(guard)
		uuid_read_constructors(call)
		assert ios_runtime.live == baseline && objc_pool().objects.len == 0
		uuid := cf_uuid_create_from_uuid_bytes(0, 0x0706050403020100, 0x0f0e0d0c0b0a0908)
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn uuid_read_worker(call, uuid) }
		workers.wait(); unsafe { workers.free() }
		assert obj_header(uuid).refs == 1 && ios_runtime.live == baseline + 1
		copy := call(uuid); objc_release(uuid)
		assert copy.first == 0x0706050403020100 && copy.second == 0x0f0e0d0c0b0a0908
		assert ios_runtime.live == baseline && objc_pool().objects.len == 0
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! {
			if _ := runtime_symbol(library, '_CFUUIDGetUUIDBytes') { assert false }
		}
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.swift_concurrency_retired
		if _ := cf_uuid_get_uuid_bytes_checked(0) { assert false }
	}
	println('IOS-CF-UUID-READ: scoped one-pointer x0/x1 aggregate return, protected x1–x8 and preserved x20/x21, unaligned +5/+13 stores with intact canaries, 261 exact payloads, nil/stale/foreign rejection, all UUID constructors, independent copies, unchanged references, eight concurrent readers, no allocations/autoreleases and two zero-live-object teardowns')
}
