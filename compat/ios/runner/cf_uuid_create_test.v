// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#include <CoreFoundation/CFUUID.h>
	@[typedef]
	struct C.CFUUIDBytes {
		byte0 u8 byte1 u8 byte2 u8 byte3 u8 byte4 u8 byte5 u8 byte6 u8 byte7 u8
		byte8 u8 byte9 u8 byte10 u8 byte11 u8 byte12 u8 byte13 u8 byte14 u8 byte15 u8
	}
	fn C.CFUUIDCreate(voidptr) voidptr
	fn C.CFUUIDGetUUIDBytes(voidptr) C.CFUUIDBytes
	fn C.CFUUIDGetTypeID() u64
	fn C.CFGetTypeID(voidptr) u64
	fn C.CFGetRetainCount(voidptr) i64
	fn C.CFAllocatorGetDefault() voidptr
	fn C.CFRetain(voidptr) voidptr
}

type UUIDCreateCall = fn (u64) u64
type UUIDCreateKeep = fn (u64) u64
type UUIDCreateDrop = fn (u64)
type UUIDCreateProbe = fn (u64, u64, u64, u64, u64, &u64)

fn uuid_create_emit(code u64) {
	// Allocator in x0; protected x1–x8, preserved x20/x21.
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0503f3, 0xaa0003f0,
		0xaa0103e0, 0xaa0203e1, 0xaa0303e2, 0xaa0403e3, 0xaa0303e4, 0xaa0303e5,
		0xaa0303e6, 0xaa0303e7, 0xaa0303e8, 0xaa0303f4, 0xd2824695, 0xd63f0200,
		0xa9000660, 0xa9015674, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
}

fn uuid_create_raw(entry u64, allocator u64, code u64, guard u64) u64 {
	mut capture := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	unsafe { UUIDCreateProbe(voidptr(code))(entry, allocator, guard, guard, guard, &capture[1]) }
	assert capture[0] == 0xcafe && capture[3] == guard && capture[4] == 0x1234 && capture[5] == 0xbeef
	return capture[1]
}

fn uuid_create_native(allocator u64) u64 {
	$if macos { return u64(C.CFUUIDCreate(voidptr(allocator))) }
	return 0
}

fn uuid_create_native_cases(code u64, guard u64) {
	$if macos {
		mut observed := [16]u8{}
		mut missing := [16]u8{init: 0xff}
		mut samples := [128][16]u8{}
		for i in 0 .. 128 {
			pool := C.objc_autoreleasePoolPush()
			object := uuid_create_raw(u64(unsafe { voidptr(uuid_create_native) }), if i & 1 == 0 { u64(0) } else { u64(C.CFAllocatorGetDefault()) }, code, guard)
			assert object != 0 && C.CFGetTypeID(voidptr(object)) == C.CFUUIDGetTypeID()
			assert C.CFGetRetainCount(voidptr(object)) == 1 && C.CFRetain(voidptr(object)) == voidptr(object)
			assert C.CFGetRetainCount(voidptr(object)) == 2
			C.CFRelease(voidptr(object)); C.objc_autoreleasePoolPop(pool)
			assert C.CFGetRetainCount(voidptr(object)) == 1
			bytes := C.CFUUIDGetUUIDBytes(voidptr(object))
			assert sizeof(bytes) == 16
			unsafe { C.memcpy(&samples[i][0], &bytes, 16) }
			assert samples[i][6] >> 4 == 4 && samples[i][8] >> 6 == 2
			for j in 0 .. i { assert unsafe { C.memcmp(&samples[i][0], &samples[j][0], 16) } != 0 }
			for j in 0 .. 16 { observed[j] |= samples[i][j]; missing[j] &= samples[i][j] }
			C.CFRelease(voidptr(object))
		}
		for j in 0 .. 16 {
			mask := if j == 6 { u8(15) } else if j == 8 { u8(63) } else { u8(255) }
			assert observed[j] & mask == mask && missing[j] & mask == 0
		}
		println('NATIVE-CF-UUID-CREATE: one allocator argument, protected x1–x8 and preserved x20/x21, owned CFUUID type, pool-independent references, balanced retain/release, unique version-4 values and varying random bits')
	}
}

fn uuid_create_worker(entry u64, allocator u64, index int) u64 {
	create := unsafe { UUIDCreateCall(voidptr(entry)) }
	output := u64(C.malloc(64 * 16))
	assert output != 0
	for i in 0 .. 64 {
		pool := objc_pool_push()
		darwin_set_errno(i32(170 + index))
		object := create(allocator)
		assert unsafe { *C.ios_errno_address() } == 170 + index
		header := obj_header(object)
		assert header.refs == 1 && header.cls == ios_runtime.names['VinixCFUUID'] && !header.uuid_owned
		assert header.uuid_bytes[6] >> 4 == 4 && header.uuid_bytes[8] >> 6 == 2
		assert objc_pool().objects.len == 0
		objc_pool_pop(pool)
		unsafe { C.memcpy(voidptr(output + u64(i * 16)), &header.uuid_bytes[0], 16) }
		objc_release(object)
	}
	return output
}

fn uuid_create_threads(entry u64, allocator u64) {
	mut workers := []thread u64{}
	for index in 0 .. 8 { workers << spawn uuid_create_worker(entry, if index & 1 == 0 { u64(0) } else { allocator }, index) }
	values := workers.wait()
	mut observed := [16]u8{}
	mut missing := [16]u8{init: 0xff}
	for i, buffer in values {
		for j in 0 .. 64 {
			at := buffer + u64(j * 16)
			for previous in 0 .. i + 1 {
				for k in 0 .. if previous == i { j } else { 64 } {
					assert unsafe { C.memcmp(voidptr(at), voidptr(values[previous] + u64(k * 16)), 16) } != 0
				}
			}
			for k in 0 .. 16 { byte := unsafe { *(&u8(at + u64(k))) }; observed[k] |= byte; missing[k] &= byte }
		}
	}
	for j in 0 .. 16 {
		mask := if j == 6 { u8(15) } else if j == 8 { u8(63) } else { u8(255) }
		assert observed[j] & mask == mask && missing[j] & mask == 0
	}
	for pointer in values { unsafe { C.free(voidptr(pointer)) } }
	unsafe { values.free(); workers.free() }
}

fn test_cf_uuid_create() {
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page * 2, 3, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != unsafe { voidptr(-1) }; defer { assert C.munmap(code, page * 2) == 0 }
	uuid_create_emit(u64(code)); C.__builtin___clear_cache(code, voidptr(u64(code) + 92))
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := u64(code) + u64(page); assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	uuid_create_native_cases(u64(code), guard)
	if _ := cf_uuid_create_checked(0) { assert false }
	for _ in 0 .. 2 {
		objc_start()
		lib := '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation'
		entry := runtime_symbol(lib, '_CFUUIDCreate') or { panic(err) }
		keep := unsafe { UUIDCreateKeep(voidptr(runtime_symbol(lib, '_CFRetain') or { panic(err) })) }
		drop := unsafe { UUIDCreateDrop(voidptr(runtime_symbol(lib, '_CFRelease') or { panic(err) })) }
		allocator := read64(runtime_symbol(lib, '_kCFAllocatorSystemDefault') or { panic(err) })
		assert read64(runtime_symbol(lib, '_kCFAllocatorDefault') or { panic(err) }) == 0
		assert allocator == cf_allocator_default()
		null_allocator := read64(runtime_symbol(lib, '_kCFAllocatorNull') or { panic(err) })
		baseline := ios_runtime.live
		for invalid in [u64(1), guard, null_allocator, ios_runtime.names['NSObject']]! {
			if _ := cf_uuid_create_checked(invalid) { assert false }
			assert ios_runtime.live == baseline
		}
		for allocation in [u64(0), allocator]! {
			pool := objc_pool_push()
			object := uuid_create_raw(entry, allocation, u64(code), guard)
			assert object != 0 && ios_runtime.live == baseline + 1 && obj_header(object).refs == 1
			assert cf_type_id(object) == ios_runtime.names['VinixCFUUID'] && !objc_is_kind(object, ios_runtime.names['NSUUID'])
			bytes := obj_header(object).uuid_bytes
			assert bytes[6] >> 4 == 4 && bytes[8] >> 6 == 2
			assert keep(object) == object && obj_header(object).refs == 2
			drop(object); objc_pool_pop(pool)
			assert obj_header(object).refs == 1
			assert unsafe { C.memcmp(&bytes[0], &obj_header(object).uuid_bytes[0], 16) } == 0
			// A CF collection retains the value after its creating caller releases it.
			holder := objc_allocate(ios_runtime.names['NSArray'])
			mut header := obj_header(holder); array_append(mut header, object)
			mut weak := u64(0); objc_store_weak(unsafe { &weak }, object)
			drop(object); assert weak == object && obj_header(object).refs == 1
			objc_release(holder); assert weak == 0 && ios_runtime.live == baseline
		}
		uuid_create_threads(entry, allocator)
		assert ios_runtime.live == baseline && objc_pool().objects.len == 0
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! {
			if _ := runtime_symbol(library, '_CFUUIDCreate') { assert false }
		}
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.swift_concurrency_retired
		if _ := cf_uuid_create_checked(0) { assert false }
	}
	println('IOS-CF-UUID-CREATE: scoped one-allocator owned ABI, protected x1–x8 and preserved x20/x21, nil/default allocator and explicit rejection, distinct CFUUID type, secure version-4 bytes, varying random bits and 512 unique concurrent values per runtime, unchanged errno, balanced retains, collection/weak lifetime, no autoreleases and two zero-live-object teardowns')
}
