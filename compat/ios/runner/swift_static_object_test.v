// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr

type StaticInitialize = fn (u64, u64) u64
type StaticProbe = fn (u64, u64, u64, &u64)
type StaticSign = fn (u64, u64) u64
type StaticRetain = fn (u64) u64
type StaticRelease = fn (u64)

fn static_write64(address u64, value u64) {
	unsafe { *(&u64(address)) = value }
}

fn static_map(length usize, protection int) u64 {
	address := u64(C.mmap(unsafe { nil }, length, protection, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert address != u64(-1)
	return address
}

fn static_cases(entry u64, probe StaticProbe, sign StaticSign, span u64, protected u64, native bool) {
	initialize := unsafe { StaticInitialize(voidptr(entry)) }
	mut slot := span
	for metadata in [u64(0), 1, 8, 0x12345678, protected]! {
		for offset in [u64(8), 16, 64, 128]! {
			C.memset(voidptr(slot), 0xa5, 192)
			object := slot + offset
			static_write64(object - 8, 0)
			mut result := [u64(0x1234), 0, 0, 0, 0x5678]!
			probe(metadata, object, entry, unsafe { &result[1] })
			assert result == [u64(0x1234), object, 0x5020, 0x5021, 0x5678]!
			mut expected := metadata
			$if macos {
				if native && metadata != 0 {
					expected = sign(metadata, object | (u64(27361) << 48))
				}
			}
			assert read64(object) == expected && read64(object + 8) == swift_static_object_immortal
			assert read64(object - 8) != 0
			for _ in 0 .. 128 {
				assert initialize(0x99999998, object) == object
			}
			assert read64(object) == expected && read64(object + 8) == swift_static_object_immortal
			for i in u64(0) .. 192 {
				if slot + i >= object - 8 && slot + i < object + 16 { continue }
				assert unsafe { *(&u8(slot + i)) } == 0xa5
			}
			slot += 256
		}
	}
}

fn static_worker(entry u64, object u64, metadata u64) {
	initialize := unsafe { StaticInitialize(voidptr(entry)) }
	for _ in 0 .. 1000 {
		assert initialize(metadata, object) == object
	}
}

fn static_reject(metadata u64, object u64) {
	if _ := swift_static_initialize_checked(metadata, object) {
		assert false, 'invalid static initialization accepted'
	}
}

fn static_arc(object u64) {
	assert swift_retain(object) == object && swift_unknown_retain(object) == object
	swift_release(object)
	swift_release_n(object, ~u32(0))
	swift_release_n(object, 0)
	swift_unknown_release(object)
	assert swift_bridge_retain(object) == object
	swift_bridge_release(object)
	swift_bridge_release_n(object, 2147483647)
	assert !swift_is_unique_native(object)
	assert (swift_buffer_refs(object, i64(0x7fffffffffffffff)) or { panic(err) }) == swift_strong_limit
	assert (swift_buffer_refs(object, -i64(0x7fffffffffffffff) - 1) or { panic(err) }) == swift_strong_limit
	if _ := swift_heap_deallocate_checked(object, 16, 7, false) {
		assert false
	}
	if _ := swift_heap_deallocate_checked(object, 16, 7, true) {
		assert false
	}
}

fn static_suite(probe StaticProbe, sign StaticSign, persistent u64) {
	page := usize(C.getpagesize())
	span := static_map(page * 2, C.PROT_READ | C.PROT_WRITE)
	protected := static_map(page, C.PROT_NONE)
	entry := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_initStaticObject') or { panic(err) }
	before := ios_runtime.swift_heap_sequence
	static_cases(entry, probe, sign, span, protected, false)
	for i in 0 .. 20 { static_arc(span + u64(i * 256) + [u64(8), 16, 64, 128]![i % 4]) }
	// Eight callers share one token; exactly one metadata argument wins.
	shared_object := span + 6008
	mut workers := []thread{}
	for i in 0 .. 8 { workers << spawn static_worker(entry, shared_object, u64(i + 1) * 8) }
	workers.wait()
	assert read64(shared_object) >= 8 && read64(shared_object) <= 64 && read64(shared_object) & 7 == 0
	assert read64(shared_object + 8) == swift_static_object_immortal
	swift_once_checked(shared_object - 8, 0, protected) or { panic(err) }
	static_arc(shared_object)
	// An earlier runtime lifetime's completed image storage keeps its metadata.
	assert swift_static_initialize(0x12345678, persistent) == persistent
	assert swift_static_initialize(0x99999998, persistent) == persistent
	assert read64(persistent) == 0x12345678
	static_arc(persistent)
	for invalid in [u64(0), 1, 7, 9, ~u64(0) - 7, ~u64(0) - 15]! { static_reject(0, invalid) }
	malformed := span + 6408
	for token in [u64(1), 3, 4, 0x8000000000000000]! {
		static_write64(malformed - 8, token)
		static_write64(malformed, 0x1234)
		static_write64(malformed + 8, 3)
		static_reject(0, malformed)
		assert read64(malformed - 8) == token && read64(malformed) == 0x1234 && read64(malformed + 8) == 3
	}
	for token in [swift_once_done, ~u64(0)]! {
		static_write64(malformed - 8, token)
		static_reject(0, malformed)
	}
	// A fake immortal header has no ARC provenance. Unknown unreadable memory
	// also rejects without probing its header or treating it as owned heap data.
	static_write64(malformed + 8, swift_static_object_immortal)
	if _ := swift_buffer_refs(malformed, 1) {
		assert false
	}
	if _ := swift_buffer_refs(protected, -1) {
		assert false
	}
	// Importing a completed native -1 token preserves metadata and payload.
	assert swift_static_initialize(0x99999998, malformed) == malformed
	assert read64(malformed) == 0x1234 && read64(malformed - 8) == ~u64(0)
	static_arc(malformed)
	// Header ends exactly at a guard page; nothing beyond its 16 bytes is read.
	guard := static_map(page * 2, C.PROT_READ | C.PROT_WRITE)
	assert C.mprotect(voidptr(guard + u64(page)), page, C.PROT_NONE) == 0
	object := guard + u64(page) - 16
	assert swift_static_initialize(protected, object) == object
	static_arc(object)
	// Fill the bounded registry. Capacity rejection cannot mutate the token or
	// header, and repeat initialization still succeeds when the table is full.
	capacity := static_map(page * 8, C.PROT_READ | C.PROT_WRITE)
	remaining := swift_static_object_limit - ios_runtime.swift_static_object_count
	for i in 0 .. remaining {
		assert swift_static_initialize(8, capacity + u64(i * 24) + 8) != 0
	}
	assert ios_runtime.swift_static_object_count == swift_static_object_limit
	last := capacity + u64(remaining * 24) + 8
	static_reject(8, last)
	assert read64(last - 8) == 0 && read64(last) == 0 && read64(last + 8) == 0
	assert swift_static_initialize(16, shared_object) == shared_object
	if _ := runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', '_swift_initStaticObject') {
		assert false
	}
	if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '__swift_initStaticObject') {
		assert false
	}
	assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_heap_sequence == before && ios_runtime.live == 0
	// Retain/release and shutdown must never touch borrowed header bytes.
	assert C.mprotect(voidptr(span), page * 2, C.PROT_NONE) == 0
	assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	assert C.mprotect(voidptr(capacity), page * 8, C.PROT_NONE) == 0
	static_arc(shared_object)
	static_arc(object)
	objc_stop()
	assert ios_runtime.swift_static_object_count == 0
	static_reject(0, protected + 8)
	if _ := swift_buffer_refs(shared_object, 1) {
		assert false
	}
	for pair in [[span, u64(page * 2)]!, [protected, u64(page)]!, [guard, u64(page * 2)]!,
		[capacity, u64(page * 8)]!]! {
		assert C.munmap(voidptr(pair[0]), usize(pair[1])) == 0
	}
}

fn test_swift_static_initialization() {
	page := usize(C.getpagesize())
	code := static_map(page, C.PROT_READ | C.PROT_WRITE)
	for i, word in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0303f3, 0xaa0203f0, 0xd28a0414,
		0xd28a0435, 0xd63f0200, 0xa9005260, 0xf9000a75, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), word)
	}
	write32(code + 64, 0xdac10820)
	write32(code + 68, 0xd65f03c0)
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 72))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { StaticProbe(voidptr(code)) }
	sign := unsafe { StaticSign(voidptr(code + 64)) }
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		assert lib != unsafe { nil }
		entry := u64(C.dlsym(lib, c'swift_initStaticObject'))
		assert entry != 0
		span := static_map(page * 2, C.PROT_READ | C.PROT_WRITE)
		protected := static_map(page, C.PROT_NONE)
		static_cases(entry, probe, sign, span, protected, true)
		retain := unsafe { StaticRetain(C.dlsym(lib, c'swift_retain')) }
		release := unsafe { StaticRelease(C.dlsym(lib, c'swift_release')) }
		for _ in 0 .. 1000 {
			assert retain(span + 8) == span + 8
			release(span + 8)
		}
		assert read64(span + 16) == swift_static_object_immortal
		assert C.munmap(voidptr(span), page * 2) == 0 && C.munmap(voidptr(protected), page) == 0
		println('NATIVE-STATIC-OBJECT: two scalar arguments and pointer result; first metadata wins with native PAC, exact immortal refcount, unchanged payload and x20/x21; opaque nil/protected metadata; repeated ARC leaves header unchanged')
	}
	static_reject(0, code + 8)
	persistent := static_map(page, C.PROT_READ | C.PROT_WRITE)
	for _ in 0 .. 2 {
		objc_start()
		static_suite(probe, sign, persistent + 8)
	}
	assert read64(persistent + 8) == 0x12345678 && read64(persistent + 16) == swift_static_object_immortal
	assert C.munmap(voidptr(persistent), page) == 0 && C.munmap(voidptr(code), page) == 0
	println('IOS-STATIC-OBJECT: first-winner once publication, borrowed immortal ARC/bridge/unknown routes, nil/protected metadata and guarded header boundaries, eight shared-token workers, fixed registry capacity, rejected fake immortals and invalid token/lifetime/heap deallocation, untouched inaccessible caller storage at retirement, two drained lifetimes')
}
