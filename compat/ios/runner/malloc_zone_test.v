// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

$if macos {
	#include <malloc/malloc.h>
	fn C.malloc_create_zone(usize, u32) voidptr
	fn C.malloc_destroy_zone(voidptr)
	fn C.malloc_zone_malloc(voidptr, usize) voidptr
	fn C.malloc_zone_calloc(voidptr, usize, usize) voidptr
	fn C.malloc_zone_realloc(voidptr, voidptr, usize) voidptr
	fn C.malloc_zone_free(voidptr, voidptr)
	fn C.malloc_zone_check(voidptr) i32
	fn C.malloc_zone_from_ptr(voidptr) voidptr
}

type HeapCreateCall = fn (usize, u32) voidptr
type HeapAllocCall = fn (voidptr, usize) voidptr
type HeapCallocCall = fn (voidptr, usize, usize) voidptr
type HeapFreeCall = fn (voidptr, voidptr)
type HeapResizeCall = fn (voidptr, voidptr, usize) voidptr
type HeapSizeCall = fn (voidptr, voidptr) usize
type HeapAlignCall = fn (voidptr, usize, usize) voidptr
type HeapCheckCall = fn (voidptr) i32
type HeapStatsCall = fn (voidptr, voidptr)

fn heap_test_create(native bool) voidptr {
	$if macos { if native { return C.malloc_create_zone(0x400000, 0) } }
	get := unsafe { HeapCreateCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_malloc_create_zone') or { panic(err) })) }
	return get(0x400000, 0)
}
fn heap_test_owner(native bool, pointer voidptr) voidptr {
	$if macos { if native { return C.malloc_zone_from_ptr(pointer) } }
	return darwin_zone_from_pointer(pointer)
}
fn heap_test_check(native bool, zone voidptr) i32 {
	$if macos { if native { return C.malloc_zone_check(zone) } }
	return darwin_zone_check(zone)
}
fn heap_test_drop(native bool, zone voidptr) {
	$if macos { if native { C.malloc_destroy_zone(zone); return } }
	darwin_zone_destroy(zone)
}
fn heap_test_errno() { assert unsafe { *C.ios_errno_address() } == 83 }

fn heap_test_profile(native bool) {
	darwin_set_errno(83); zone := heap_test_create(native); assert zone != unsafe { nil }; heap_test_errno()
	other := heap_test_create(native); assert other != unsafe { nil } && other != zone
	address := u64(zone)
	assert read64(address) == 0 && read64(address + 8) == 0
	assert read32(address + 104) >= 5
	size_call := unsafe { HeapSizeCall(voidptr(read64(address + 16))) }
	allocate := unsafe { HeapAllocCall(voidptr(read64(address + 24))) }
	zero := unsafe { HeapCallocCall(voidptr(read64(address + 32))) }
	page_alloc := unsafe { HeapAllocCall(voidptr(read64(address + 40))) }
	release := unsafe { HeapFreeCall(voidptr(read64(address + 48))) }
	resize := unsafe { HeapResizeCall(voidptr(read64(address + 56))) }
	align := unsafe { HeapAlignCall(voidptr(read64(address + 112))) }
	for requested in [usize(0), 1, 15, 16, 17, 31, 4096, 65536]! {
		darwin_set_errno(83); pointer := allocate(zone, requested); assert pointer != unsafe { nil } && u64(pointer) & 15 == 0; heap_test_errno()
		assert heap_test_owner(native, pointer) == zone && size_call(zone, pointer) >= requested, 'native ${native} requested ${requested}'
		assert heap_test_owner(native, voidptr(u64(pointer) + 1)) == unsafe { nil }
		assert size_call(zone, voidptr(u64(pointer) + 1)) == 0 && size_call(other, pointer) == 0
		if requested > 0 { unsafe { C.memset(pointer, 0x5a, requested) } }
		darwin_set_errno(83); larger := resize(zone, pointer, requested + 32); assert larger != unsafe { nil }; heap_test_errno()
		for i in usize(0) .. requested { assert unsafe { *(&u8(u64(larger) + u64(i))) } == 0x5a }
		assert heap_test_owner(native, larger) == zone && size_call(zone, larger) >= requested + 32
		darwin_set_errno(83); tiny := resize(zone, larger, 0); assert tiny != unsafe { nil } && size_call(zone, tiny) >= 1; heap_test_errno()
		darwin_set_errno(83); release(zone, tiny); heap_test_errno()
		assert heap_test_check(native, zone) == 1
	}
	for count in [usize(0), 1, 17]! { pointer := zero(zone, count, 13); assert pointer != unsafe { nil }; for i in usize(0) .. count * 13 { assert unsafe { *(&u8(u64(pointer) + u64(i))) } == 0 }; release(zone, pointer) }
	page := page_alloc(zone, 33); assert page != unsafe { nil } && u64(page) % mach_page_size() == 0; release(zone, page)
	for alignment in [usize(1), 4, 8, 16, 64, 4096]! {
		darwin_set_errno(83); pointer := align(zone, alignment, 17); heap_test_errno()
		if alignment < 8 { assert pointer == unsafe { nil } } else { assert pointer != unsafe { nil } && u64(pointer) % u64(alignment) == 0; release(zone, pointer) }
	}
	pointer := resize(zone, unsafe { nil }, 32); assert pointer != unsafe { nil }; release(zone, pointer)
	darwin_set_errno(83); release(zone, unsafe { nil }); assert heap_test_check(native, zone) == 1 && heap_test_check(native, unsafe { nil }) == 1; heap_test_errno()
	intro := read64(address + 96); assert intro != 0
	check := unsafe { HeapCheckCall(voidptr(read64(intro + 16))) }; assert check(zone) == 1
	stats := unsafe { HeapStatsCall(voidptr(read64(intro + 56))) }
	mut words := [u64(0x1234), 0, 0, 0, 0, 0x5678]!
	stats(zone, unsafe { voidptr(&words[1]) }); assert words[0] == 0x1234 && words[5] == 0x5678 && u32(words[1]) == 0 && words[2] == 0
	if !native {
		// Failed realloc preserves both the bytes and zone ownership.
		pointer2 := allocate(zone, 32); unsafe { C.memset(pointer2, 0x73, 32) }
		assert resize(zone, pointer2, ~usize(0)) == unsafe { nil } && unsafe { *C.ios_errno_address() } == 12
		assert heap_test_owner(false, pointer2) == zone && size_call(zone, pointer2) >= 32
		for i in 0 .. 32 { assert unsafe { *(&u8(u64(pointer2) + u64(i))) } == 0x73 }; release(zone, pointer2)
		assert zero(zone, ~usize(0), 2) == unsafe { nil } && unsafe { *C.ios_errno_address() } == 12
	}
	// Destruction owns an outstanding allocation, independent of the other zone.
	assert allocate(zone, 4096) != unsafe { nil }; kept := allocate(other, 64); unsafe { *(&u8(kept)) = 0x79 }
	heap_test_drop(native, zone); assert heap_test_owner(native, kept) == other && unsafe { *(&u8(kept)) } == 0x79
	release(other, kept); heap_test_drop(native, other)
}

fn heap_test_global() {
	default := darwin_default_zone(); assert default != unsafe { nil }
	for kind in 0 .. 4 {
		pointer := match kind { 0 { darwin_malloc(31) } 1 { darwin_calloc(1, 31) } 2 { voidptr(darwin_strdup(c'guest')) } else { darwin_realloc(unsafe { nil }, 31) } }
		assert pointer != unsafe { nil } && darwin_zone_from_pointer(pointer) == default
		new := darwin_realloc(pointer, 129); assert new != unsafe { nil } && darwin_zone_from_pointer(new) == default
		assert darwin_malloc_size(new) == darwin_zone_size(default, new)
		darwin_free(new)
	}
	mut aligned := unsafe { voidptr(0x1234) }; darwin_set_errno(83)
	assert darwin_posix_memalign(unsafe { &aligned }, 4, 31) == 22 && aligned == voidptr(0x1234); heap_test_errno()
	assert darwin_posix_memalign(unsafe { &aligned }, 64, 31) == 0 && u64(aligned) % 64 == 0; heap_test_errno()
	assert darwin_zone_from_pointer(aligned) == default; darwin_free(aligned)
	zone := heap_test_create(false); pointer := darwin_zone_malloc(zone, 31); assert pointer != unsafe { nil }
	new := darwin_realloc(pointer, 300); assert new != unsafe { nil } && darwin_zone_from_pointer(new) == zone; darwin_free(new)
	assert darwin_zone_size(zone, new) == 0 && darwin_zone_check(zone) == 1; darwin_zone_destroy(zone)
	// Host-allocated storage can still cross existing imported free/realloc.
	raw := C.malloc(31); assert raw != unsafe { nil }; raw2 := darwin_realloc(raw, 64); assert raw2 != unsafe { nil }; darwin_free(raw2)
	assert darwin_zone_from_pointer(unsafe { nil }) == unsafe { nil }
}

fn heap_test_buffer_ownership() {
	zone := heap_test_create(false)
	for free_when_done in [false, true]! {
		pointer := darwin_zone_malloc(zone, 64); assert pointer != unsafe { nil }
		pool := objc_pool_push()
		mut frame := RegisterFrame{}
		frame.x[2] = u64(pointer); frame.x[3] = 64; frame.x[4] = if free_when_done { 1 } else { 0 }
		assert propertylist_dispatch(ios_runtime.names['NSData'], 'dataWithBytesNoCopy:length:freeWhenDone:', mut frame)
		assert frame.x[0] != 0 && darwin_zone_from_pointer(pointer) == zone
		objc_pool_pop(pool)
		assert darwin_zone_from_pointer(pointer) == if free_when_done { unsafe { voidptr(nil) } } else { zone }
		if !free_when_done { darwin_free(pointer) }
	}
	pointer := darwin_zone_malloc(zone, 64); mut object := u64(0)
	assert cm_block_create(0, u64(pointer), 64, 0, 0, 0, 64, 0, unsafe { &object }) == 0
	assert darwin_zone_from_pointer(pointer) == zone; objc_release(object)
	assert darwin_zone_from_pointer(pointer) == unsafe { nil } && darwin_zone_check(zone) == 1
	darwin_zone_destroy(zone)
}

struct HeapTestWorker { zone voidptr }
fn heap_test_worker(context voidptr) voidptr {
	state := unsafe { &HeapTestWorker(context) }
	for _ in 0 .. 100 {
		pointer := darwin_zone_calloc(state.zone, 3, 17); assert pointer != unsafe { nil }
		assert darwin_zone_from_pointer(pointer) == state.zone && darwin_zone_size(state.zone, pointer) >= 51
		resized := darwin_realloc(pointer, 191); assert resized != unsafe { nil }; darwin_free(resized)
	}
	return unsafe { nil }
}
fn heap_test_threads_and_fork() {
	zone := heap_test_create(false); mut state := HeapTestWorker{zone: zone}; mut threads := [8]u64{}
	for i in 0 .. 8 { assert C.pthread_create(unsafe { voidptr(&threads[i]) }, unsafe { nil }, unsafe { voidptr(heap_test_worker) }, unsafe { voidptr(&state) }) == 0 }
	for handle in threads { assert C.pthread_join(voidptr(handle), unsafe { nil }) == 0 }
	assert darwin_zone_check(zone) == 1; assert heap_zone_find(zone).count == 0 && heap_zone_find(zone).bytes == 0
	pointer := darwin_zone_malloc(zone, 64); unsafe { *(&u8(pointer)) = 0x41 }
	image_atfork_start() or { panic(err) }; child := C.ios_fork(); assert child >= 0
	if child == 0 {
		assert darwin_zone_from_pointer(pointer) == zone && unsafe { *(&u8(pointer)) } == 0x41
		darwin_zone_free(zone, pointer); next := darwin_zone_malloc(zone, 128); assert next != unsafe { nil }
		darwin_zone_destroy(zone); assert darwin_zone_from_pointer(next) == unsafe { nil }; C._exit(0)
	}
	mut status := i32(-1); assert C.ios_waitpid(child, unsafe { &status }, 0) == child && status == 0; image_atfork_stop()
	assert darwin_zone_from_pointer(pointer) == zone && unsafe { *(&u8(pointer)) } == 0x41
	darwin_zone_destroy(zone)
}

fn test_malloc_zones() {
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!
		// ASan replaces Apple's zone entry points and loses native zone
		// identity. Native measurements run separately without interposition.
		$if macos { if os.getenv('ASAN_OPTIONS') == '' { heap_test_profile(true) } }
		heap_test_profile(false); heap_test_global(); heap_test_buffer_ownership(); heap_test_threads_and_fork()
		assert darwin_zone_create(0, 1) == unsafe { nil } && unsafe { *C.ios_errno_address() } == 45
		for symbol in ['_malloc_create_zone', '_malloc_zone_check', '_malloc_zone_free', '_malloc_zone_from_ptr', '_malloc_zone_malloc', '_malloc_zone_realloc', '_malloc_destroy_zone']! {
			assert runtime_symbol('/usr/lib/libSystem.B.dylib', symbol)! != 0
			mut rejected := false; runtime_symbol('/usr/lib/libobjc.A.dylib', symbol) or { rejected = true }; assert rejected
		}
		// Image retirement owns leaked custom/default allocations and zone headers.
		zone := heap_test_create(false); assert darwin_zone_malloc(zone, 4096) != unsafe { nil } && darwin_malloc(8192) != unsafe { nil }
		objc_stop(); system_data_stop(); assert system_data == unsafe { nil }
	}
	println('IOS-MALLOC-ZONE: native callback layout, exact ownership, zero allocations/realloc, alignment, calloc, failure preservation, default heap adapters, global free/realloc, statistics/checks, eight callers, fork and two image lifetimes passed')
}
