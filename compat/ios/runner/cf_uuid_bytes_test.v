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
	fn C.CFUUIDGetTypeID() u64
	fn C.CFGetTypeID(voidptr) u64
	fn C.CFGetRetainCount(voidptr) i64
	fn C.CFRetain(voidptr) voidptr
	fn C.CFAllocatorGetDefault() voidptr
}

type UUIDBytesCall = fn (u64, u64, u64) u64
type UUIDBytesProbe = fn (u64, u64, u64, u64, u64, &u64)

fn uuid_bytes_emit(code u64) {
	// Allocator in x0, by-value CFUUIDBytes in x1/x2; protected x3–x8.
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0503f3, 0xaa0003f0,
		0xaa0103e0, 0xaa0203e1, 0xaa0303e2, 0xaa0403e3, 0xaa0303e4, 0xaa0303e5,
		0xaa0303e6, 0xaa0303e7, 0xaa0303e8, 0xaa0303f4, 0xd2824695, 0xd63f0200,
		0xa9000660, 0xa9015674, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
}

fn uuid_bytes_raw(entry u64, allocator u64, first u64, second u64, code u64, guard u64) u64 {
	mut capture := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	unsafe { UUIDBytesProbe(voidptr(code))(entry, allocator, first, second, guard, &capture[1]) }
	assert capture[0] == 0xcafe && capture[3] == guard && capture[4] == 0x1234 && capture[5] == 0xbeef
	return capture[1]
}

fn uuid_bytes_sample(index int) [16]u8 {
	mut bytes := [16]u8{}
	for i in 0 .. 16 {
		bytes[i] = if index < 128 {
			if i == index / 8 { u8(1) << u32(index % 8) } else { u8(0) }
		} else if index < 256 {
			if i == (index - 128) / 8 { ~(u8(1) << u32(index % 8)) } else { u8(255) }
		} else { match index { 256 { u8(0) } 257 { u8(255) } 258 { u8(i) } else { u8(255 - i) } } }
	}
	return bytes
}

fn uuid_bytes_cases(entry u64, allocator u64, code u64, guard u64, native bool) {
	for i in 0 .. 261 {
		mut words := [2]u64{}
		mut bytes := [16]u8{}
		if i == 260 {
			// Neither input word is an address, even if it names protected memory.
			words[0] = guard; words[1] = ~guard
			unsafe { C.memcpy(&bytes[0], &words[0], 16) }
		} else {
			bytes = uuid_bytes_sample(i)
			unsafe { C.memcpy(&words[0], &bytes[0], 16) }
		}
		mut object := u64(0)
		mut pool := u64(0)
		if native { $if macos { pool = u64(C.objc_autoreleasePoolPush()) } } else { pool = objc_pool_push() }
		object = uuid_bytes_raw(entry, if i & 1 == 0 { u64(0) } else { allocator }, words[0], words[1], code, guard)
		assert object != 0
		if native {
			$if macos {
				assert C.CFGetTypeID(voidptr(object)) == C.CFUUIDGetTypeID()
				count := C.CFGetRetainCount(voidptr(object)); assert count >= 1
				assert C.CFRetain(voidptr(object)) == voidptr(object) && C.CFGetRetainCount(voidptr(object)) == count + 1
				C.CFRelease(voidptr(object)); C.objc_autoreleasePoolPop(voidptr(pool))
				raw := C.CFUUIDGetUUIDBytes(voidptr(object)); assert sizeof(raw) == 16
				assert unsafe { C.memcmp(&raw, &bytes[0], 16) } == 0
				assert C.CFGetRetainCount(voidptr(object)) == count
				C.CFRelease(voidptr(object))
			}
		} else {
			header := obj_header(object)
			assert header.refs == 1 && header.cls == ios_runtime.names['VinixCFUUID'] && !header.uuid_owned
			assert unsafe { C.memcmp(&header.uuid_bytes[0], &bytes[0], 16) } == 0
			assert objc_retain(object) == object && header.refs == 2; objc_release(object)
			assert objc_pool().objects.len == 0; objc_pool_pop(pool)
			assert header.refs == 1 && !objc_is_kind(object, ios_runtime.names['NSUUID'])
			objc_release(object)
		}
	}
}

fn uuid_bytes_lifetime(call UUIDBytesCall) {
	mut bytes := uuid_bytes_sample(258)
	mut words := [2]u64{}
	unsafe { C.memcpy(&words[0], &bytes[0], 16) }
	first := call(0, words[0], words[1]); second := call(0, words[0], words[1])
	words[0] = ~words[0]; words[1] = ~words[1]
	other := call(0, words[0], words[1])
	assert first != second && object_equal(first, second) && cf_hash(first) == cf_hash(second)
	assert !object_equal(first, other) && !object_equal(other, first)
	text := owned_string('00010203-0405-0607-0809-0A0B0C0D0E0F')
	parsed := cf_uuid_create_from_string(0, text); objc_release(text)
	assert object_equal(first, parsed) && cf_hash(first) == cf_hash(parsed)
	objc_release(parsed)
	set := objc_new(ios_runtime.names['NSMutableSet'])
	ns_set_insert(set, first); ns_set_insert(set, second); ns_set_insert(set, other)
	assert obj_header(set).items.len == 2 && ns_set_index(set, second, 0) >= 0
	mut weak := u64(0); objc_store_weak(unsafe { &weak }, first)
	objc_release(first); objc_release(second); objc_release(other)
	assert weak != 0 && obj_header(weak).refs == 1
	objc_release(set); assert weak == 0
}

fn uuid_bytes_worker(call UUIDBytesCall, allocator u64, index int) {
	for i in 0 .. 200 {
		first := u64(0x0123456789abcdef) ^ (u64(index) << 56) ^ u64(i)
		second := ~first
		object := call(allocator, first, second)
		header := obj_header(object)
		mut words := [2]u64{}
		unsafe { C.memcpy(&words[0], &header.uuid_bytes[0], 16) }
		assert header.refs == 1 && words[0] == first && words[1] == second
		objc_release(object)
	}
}

fn test_cf_uuid_bytes() {
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page * 2, 3, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != unsafe { voidptr(-1) }; defer { assert C.munmap(code, page * 2) == 0 }
	uuid_bytes_emit(u64(code)); C.__builtin___clear_cache(code, voidptr(u64(code) + 92))
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := u64(code) + u64(page); assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	$if macos {
		// Call the actual native aggregate ABI through the raw register probe.
		uuid_bytes_cases(u64(unsafe { voidptr(C.CFUUIDCreateFromUUIDBytes) }), u64(C.CFAllocatorGetDefault()), u64(code), guard, true)
		println('NATIVE-CF-UUID-BYTES: actual by-value 16-byte aggregate in x1/x2, protected x3–x8, preserved x20/x21, 261 exact bit/pointer-pattern round trips, owned pool-independent CFUUID references and balanced retains')
	}
	if _ := cf_uuid_create_from_uuid_bytes_checked(0, 0, 0) { assert false }
	for _ in 0 .. 2 {
		objc_start()
		lib := '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation'
		entry := runtime_symbol(lib, '_CFUUIDCreateFromUUIDBytes') or { panic(err) }
		call := unsafe { UUIDBytesCall(voidptr(entry)) }
		allocator := read64(runtime_symbol(lib, '_kCFAllocatorSystemDefault') or { panic(err) })
		assert read64(runtime_symbol(lib, '_kCFAllocatorDefault') or { panic(err) }) == 0
		null_allocator := read64(runtime_symbol(lib, '_kCFAllocatorNull') or { panic(err) })
		baseline := ios_runtime.live
		for invalid in [u64(1), guard, null_allocator, ios_runtime.names['NSObject']]! {
			if _ := cf_uuid_create_from_uuid_bytes_checked(invalid, guard, ~guard) { assert false }
			assert ios_runtime.live == baseline
		}
		uuid_bytes_cases(entry, allocator, u64(code), guard, false)
		uuid_bytes_lifetime(call)
		assert ios_runtime.live == baseline && objc_pool().objects.len == 0
		mut workers := []thread{}
		for i in 0 .. 8 { workers << spawn uuid_bytes_worker(call, if i & 1 == 0 { u64(0) } else { allocator }, i) }
		workers.wait(); unsafe { workers.free() }
		assert ios_runtime.live == baseline && objc_pool().objects.len == 0
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! {
			if _ := runtime_symbol(library, '_CFUUIDCreateFromUUIDBytes') { assert false }
		}
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.swift_concurrency_retired
		if _ := cf_uuid_create_from_uuid_bytes_checked(0, 0, 0) { assert false }
	}
	println('IOS-CF-UUID-BYTES: scoped allocator/16-byte aggregate ABI, protected x3–x8 and preserved x20/x21, 261 exact bit/pointer-pattern values, nil/default and rejected allocators, distinct owned CFUUID type, unchanged bits, equality/hash across constructors, set/weak lifetime, eight concurrent callers, no autoreleases and two zero-live-object teardowns')
}
