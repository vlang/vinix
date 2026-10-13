// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32

type RawAllocate = fn (u64, u64) u64
type RawDeallocate = fn (u64, u64, u64)
type PointerDeallocate = fn (u64, u64)
struct RawAllocationApi {
	allocate RawAllocate
	deallocate RawDeallocate
	pointers [4]PointerDeallocate
}

fn raw_allocation_api(native bool, core voidptr) RawAllocationApi {
	mut entries := [6]u64{}
	for i, name in ['_swift_slowAlloc', '_swift_slowDealloc', '_$sSp10deallocateyyF',
		'_$sSP10deallocateyyF', '_$sSv10deallocateyyF', '_$sSV10deallocateyyF']! {
		$if macos { if native { entries[i] = u64(C.dlsym(core, name[1..].str)) } }
		if !native { entries[i] = runtime_symbol('/usr/lib/swift/libswiftCore.dylib', name) or { panic(err) } }
		assert entries[i] != 0
		if !native { assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', name) or { panic(err) } == entries[i] }
	}
	return RawAllocationApi{
		allocate: unsafe { RawAllocate(voidptr(entries[0])) },
		deallocate: unsafe { RawDeallocate(voidptr(entries[1])) },
		pointers: [unsafe { PointerDeallocate(voidptr(entries[2])) },
			unsafe { PointerDeallocate(voidptr(entries[3])) },
			unsafe { PointerDeallocate(voidptr(entries[4])) },
			unsafe { PointerDeallocate(voidptr(entries[5])) }]!
	}
}

fn raw_allocation_bytes(pointer u64, size u64, alignment u64) {
	assert pointer != 0 && pointer & (alignment - 1) == 0
	count := if size == 0 { u64(1) } else { size }
	for i in u64(0) .. count { unsafe { *(&u8(pointer + i)) = u8(i ^ 0xa5) } }
	for i in u64(0) .. count { assert unsafe { *(&u8(pointer + i)) } == u8(i ^ 0xa5) }
}

fn raw_allocation_suite(api RawAllocationApi, guard u64) {
	for size in [u64(0), 1, 7, 16, 17, 257, 4097]! {
		for mask in [u64(0), 1, 3, 7, 15, 31, 63, 4095, u64(-1)]! {
			alignment := if mask == u64(-1) { u64(16) } else if mask < 15 { u64(16) } else { mask + 1 }
			pointer := api.allocate(size, mask)
			raw_allocation_bytes(pointer, size, alignment)
			// Byte count is informational, including unknown size (-1).
			api.deallocate(pointer, if size & 1 == 0 { u64(-1) } else { u64(0) }, mask)
		}
		for method in api.pointers {
			for mask in [u64(-1), 63, 4095]! {
				pointer := api.allocate(size, mask)
				raw_allocation_bytes(pointer, size, if mask == u64(-1) { u64(16) } else { mask + 1 })
				// Neither element metadata nor any pointed-to value is read.
				method(pointer, guard)
			}
		}
	}
	api.deallocate(0, u64(-1), u64(-1))
}

fn raw_allocation_worker(api RawAllocationApi, guard u64) {
	for i in 0 .. 300 {
		pointer := api.allocate(33, 63)
		raw_allocation_bytes(pointer, 33, 64)
		api.pointers[i % 4](pointer, guard)
	}
}

fn raw_allocation_interop(api RawAllocationApi, guard u64) {
	for method in api.pointers {
		pointer := u64(darwin_malloc(33))
		raw_allocation_bytes(pointer, 33, 16)
		method(pointer, guard)
	}
	for mask in [u64(7), 63, u64(-1)]! {
		pointer := api.allocate(33, mask)
		raw_allocation_bytes(pointer, 33, if mask == 63 { u64(64) } else { u64(16) })
		darwin_free(unsafe { voidptr(pointer) })
	}
}

fn raw_pointer_ownership(api RawAllocationApi, guard u64) {
	for method in api.pointers {
		owner := objc_allocate(ios_runtime.names['NSObject'])
		objc_retain(owner)
		pointer := api.allocate(8, u64(-1))
		unsafe { *(&u64(pointer)) = owner }
		method(pointer, guard)
		assert obj_header(owner).refs == 2
		objc_release(owner); objc_release(owner)
	}
	assert ios_runtime.objects.len == 0
}

fn test_swift_raw_alloc() {
	page := usize(C.getpagesize())
	guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert guard != u64(-1)
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		assert core != unsafe { nil }
		api := raw_allocation_api(true, core)
		raw_allocation_suite(api, guard)
		raw_allocation_interop(api, guard)
		assert C.dlclose(core) == 0
		println('IOS-SWIFT-RAW-ALLOC-NATIVE: 63 raw layouts, 84 pointer frees, zero-size normalization, default/explicit alignment, ignored byte count, protected metadata and libSystem interoperability')
	}
	for _ in 0 .. 2 {
		objc_start()
		api := raw_allocation_api(false, unsafe { nil })
		raw_allocation_suite(api, guard)
		raw_allocation_interop(api, guard)
		raw_pointer_ownership(api, guard)
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn raw_allocation_worker(api, guard) }
		workers.wait()
		for size in [u64(0x8000000000000000), u64(-1)]! {
			if _ := swift_raw_allocate_checked(size, 7) { assert false }
		}
		for mask in [u64(2), 5, 0x7fffffffffffffff, 0xfffffffffffffffe]! {
			if _ := swift_raw_allocate_checked(17, mask) { assert false }
		}
		// Raw memory is separate from header-bearing ARC and task allocations.
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0
		assert ios_runtime.swift_task_alloc_count == 0
		objc_stop()
	}
	assert C.munmap(unsafe { voidptr(guard) }, page) == 0
	println('IOS-SWIFT-RAW-ALLOC: six native ABI exports, alignment/zero-size matrix, four non-destructive pointer methods, ignored size/metadata, C allocator interoperability, eight concurrent workers, rejected allocation overflow and two drained lifetimes')
}
