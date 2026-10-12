// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr

type TaskAllocCall = fn (u64) u64
type TaskDeallocCall = fn (u64)
type TaskCurrentCall = fn () u64
type TaskAllocProbe = fn (u64, u64, u64, u64, u64, &u64)

struct TaskAllocApi { alloc u64 dealloc u64 current u64 }

fn task_alloc_probe(api TaskAllocApi, probe TaskAllocProbe, input u64, freeing bool, context u64) u64 {
	mut output := [u64(0x1234), 0, 0, 0, 0, 0x5678]!
	probe(input, if freeing { api.dealloc } else { api.alloc }, context, context + 8,
		context + 16, unsafe { &output[1] })
	assert output[0] == 0x1234 && output[5] == 0x5678
	assert output[2] == context && output[3] == context + 8 && output[4] == context + 16
	return output[1]
}

fn task_alloc_pattern(pointer u64, length u64, seed u8, verify bool) {
	for i in u64(0) .. length {
		wanted := u8(i) ^ seed
		if verify { assert unsafe { *(&u8(pointer + i)) } == wanted }
		else { unsafe { *(&u8(pointer + i)) = wanted } }
	}
}

fn task_alloc_sequence(api TaskAllocApi, probe TaskAllocProbe, context u64) {
	// Native's fallback is shared, so whole nested sequences must serialize.
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if api.current != 0 { current := unsafe { TaskCurrentCall(voidptr(api.current)) }; assert current() == 0 }
	sizes := [u64(0), 1, 15, 16, 17, 31, 32, 33, 63, 64, 65, 255, 256, 257,
		511, 512, 513, 1007, 1008, 1009, 1023, 1024, 1025, 4095, 4096, 4097, 65537, 1048577]!
	mut pointers := [28]u64{}
	for i, size in sizes {
		pointer := task_alloc_probe(api, probe, size, false, context)
		assert pointer != 0 && pointer & 15 == 0
		for j in 0 .. i {
			assert pointer != pointers[j]
			if size > 0 && sizes[j] > 0 { assert pointer + size <= pointers[j] || pointers[j] + sizes[j] <= pointer }
		}
		pointers[i] = pointer
		task_alloc_pattern(pointer, size, u8(i), false)
	}
	for i := sizes.len - 1; i >= 0; i-- {
		task_alloc_pattern(pointers[i], sizes[i], u8(i), true)
		task_alloc_probe(api, probe, pointers[i], true, context)
	}
	if api.current != 0 { current := unsafe { TaskCurrentCall(voidptr(api.current)) }; assert current() == 0 }
}

fn task_alloc_worker(api TaskAllocApi, size u64) u64 {
	if api.current != 0 { current := unsafe { TaskCurrentCall(voidptr(api.current)) }; assert current() == 0 }
	allocate := unsafe { TaskAllocCall(voidptr(api.alloc)) }
	return allocate(size)
}

fn task_dealloc_worker(api TaskAllocApi, c u64, b u64) {
	if api.current != 0 { current := unsafe { TaskCurrentCall(voidptr(api.current)) }; assert current() == 0 }
	free_value := unsafe { TaskDeallocCall(voidptr(api.dealloc)) }
	free_value(c); free_value(b)
}

fn task_alloc_transfer(api TaskAllocApi) {
	allocate := unsafe { TaskAllocCall(voidptr(api.alloc)) }
	free_value := unsafe { TaskDeallocCall(voidptr(api.dealloc)) }
	a := allocate(128); task_alloc_pattern(a, 128, 0xa5, false)
	worker := spawn task_alloc_worker(api, 256)
	b := worker.wait(); task_alloc_pattern(b, 256, 0x5a, false)
	c := allocate(513); task_alloc_pattern(c, 513, 0x3c, false)
	task_alloc_pattern(a, 128, 0xa5, true); task_alloc_pattern(b, 256, 0x5a, true)
	task_alloc_pattern(c, 513, 0x3c, true)
	remover := spawn task_dealloc_worker(api, c, b)
	remover.wait(); task_alloc_pattern(a, 128, 0xa5, true); free_value(a)
}

fn task_alloc_resolver() TaskAllocApi {
	alloc := runtime_symbol('/usr/lib/swift/libswift_Concurrency.dylib', '_swift_task_alloc') or { panic(err) }
	dealloc := runtime_symbol('/usr/lib/swift/libswift_Concurrency.dylib', '_swift_task_dealloc') or { panic(err) }
	for _ in 0 .. 128 {
		assert runtime_symbol('/usr/lib/swift/libswift_Concurrency.dylib', '_swift_task_alloc') or { panic(err) } == alloc
		assert runtime_symbol('/usr/lib/swift/libswift_Concurrency.dylib', '_swift_task_dealloc') or { panic(err) } == dealloc
	}
	return TaskAllocApi{ alloc: alloc, dealloc: dealloc }
}

fn task_alloc_invalid(context u64) {
	a := swift_task_allocate_checked(17) or { panic(err) }
	b := swift_task_allocate_checked(33) or { panic(err) }
	assert read64(a - 8) == 32 && read64(b - 8) == 48
	// The documented rounding makes the whole rounded payload writable.
	task_alloc_pattern(a, 32, 0xab, false); task_alloc_pattern(b, 48, 0xcd, false)
	top := ios_runtime.swift_task_alloc_top
	for size in [u64(0x7fffffffffffffe1), 0x7fffffffffffffff, 0x8000000000000000, ~u64(0)]! {
		if _ := swift_task_allocate_checked(size) { assert false }
		assert ios_runtime.swift_task_alloc_top == top && ios_runtime.swift_task_alloc_count == 2
	}
	for pointer in [u64(0), a, a + 1, b + 1, b - 16, context, context + 16, ~u64(0)]! {
		if _ := swift_task_deallocate_checked(pointer) { assert false }
		assert ios_runtime.swift_task_alloc_top == top && ios_runtime.swift_task_alloc_count == 2
		task_alloc_pattern(a, 32, 0xab, true); task_alloc_pattern(b, 48, 0xcd, true)
	}
	if _ := swift_task_allocator_drain_checked() { assert false }
	assert ios_runtime.swift_task_alloc_top == top && ios_runtime.swift_task_alloc_count == 2
	swift_task_deallocate_checked(b) or { panic(err) }
	if _ := swift_task_deallocate_checked(b) { assert false }
	assert ios_runtime.swift_task_alloc_count == 1 && ios_runtime.swift_task_alloc_top == a - 16
	task_alloc_pattern(a, 32, 0xab, true)
	swift_task_deallocate_checked(a) or { panic(err) }
	if _ := swift_task_deallocate_checked(a) { assert false }
	for _ in 0 .. 512 {
		x := swift_task_allocate_checked(0) or { panic(err) }
		y := swift_task_allocate_checked(1) or { panic(err) }
		assert x != 0 && y != 0 && x != y && x & 15 == 0 && y & 15 == 0
		unsafe { *(&u8(y)) = 42 }; assert unsafe { *(&u8(y)) } == 42
		swift_task_deallocate_checked(y) or { panic(err) }
		swift_task_deallocate_checked(x) or { panic(err) }
		assert ios_runtime.swift_task_alloc_count == 0 && ios_runtime.swift_task_alloc_top == 0
	}
}

fn test_swift_task_alloc() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	context := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1) && context != u64(-1)
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0503f3, 0xaa0203f4,
		0xaa0303f5, 0xaa0403f6, 0xaa0103f0, 0xd63f0200, 0xf9000260, 0xa900d674,
		0xf9000e76, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	C.__builtin___clear_cache(unsafe { voidptr(code) }, unsafe { voidptr(code + 64) })
	assert C.mprotect(unsafe { voidptr(code) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { TaskAllocProbe(voidptr(code)) }
	$if macos {
		library := C.dlopen(c'/usr/lib/swift/libswift_Concurrency.dylib', C.RTLD_NOW)
		assert library != unsafe { nil }
		api := TaskAllocApi{ alloc: u64(C.dlsym(library, c'swift_task_alloc')),
			dealloc: u64(C.dlsym(library, c'swift_task_dealloc')), current: u64(C.dlsym(library, c'swift_task_getCurrent')) }
		assert api.alloc != 0 && api.dealloc != 0 && api.current != 0
		for _ in 0 .. 8 { task_alloc_sequence(api, probe, context) }
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn task_alloc_sequence(api, probe, context) }
		workers.wait(); task_alloc_transfer(api)
		println('IOS-SWIFT-TASK-ALLOC-NATIVE: nil-current-task fallback; 28 nested sizes through 1048577 bytes, 16-byte alignment, distinct writable payloads, reverse frees, guarded borrowed x20/x21/x22; eight serialized workers and cross-thread LIFO transfer. No task creation or scheduling.')
	}
	if _ := swift_task_allocate_checked(0) { assert false }
	if _ := swift_task_deallocate_checked(context) { assert false }
	if _ := swift_task_alloc_symbol('_swift_task_alloc') { assert false }
	for _ in 0 .. 2 {
		objc_start()
		for symbol in ['_swift_task_cancel',
			'_swift_task_alloc_specific', '_swift_task_dealloc_specific', '_swift_task_deallocThrough', '_swift_job_alloc']! {
			if _ := runtime_symbol('/usr/lib/swift/libswift_Concurrency.dylib', symbol) { assert false }
		}
		for library in ['/usr/lib/swift/libswiftCore.dylib', '/usr/lib/libSystem.B.dylib']! {
			if _ := runtime_symbol(library, '_swift_task_alloc') { assert false }
			if _ := runtime_symbol(library, '_swift_task_dealloc') { assert false }
		}
		mut resolvers := []thread TaskAllocApi{}
		for _ in 0 .. 8 { resolvers << spawn task_alloc_resolver() }
		addresses := resolvers.wait(); api := addresses[0]
		for address in addresses { assert address.alloc == api.alloc && address.dealloc == api.dealloc }
		assert api.alloc == u64(voidptr(swift_task_allocate)) && api.dealloc == u64(voidptr(swift_task_deallocate))
		assert ios_runtime.swift_concurrency_code == 0 && ios_runtime.swift_task_priority_arena == 0
		assert ios_runtime.swift_task_alloc_top == 0 && ios_runtime.swift_task_alloc_count == 0
		for _ in 0 .. 8 { task_alloc_sequence(api, probe, context) }
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn task_alloc_sequence(api, probe, context) }
		workers.wait(); task_alloc_transfer(api); task_alloc_invalid(context)
		swift_task_allocator_drain_checked() or { panic(err) }
		assert ios_runtime.swift_task_alloc_top == 0 && ios_runtime.swift_task_alloc_count == 0
		assert ios_runtime.live == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0
		assert ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_strings.len == 0
		objc_stop()
		assert ios_runtime.swift_concurrency_retired
		if _ := swift_task_allocate_checked(0) { assert false }
		if _ := swift_task_deallocate_checked(context) { assert false }
		if _ := swift_task_alloc_symbol('_swift_task_alloc') { assert false }
		if _ := swift_task_alloc_symbol('_swift_task_dealloc') { assert false }
	}
	assert C.munmap(unsafe { voidptr(code) }, page) == 0
	assert C.munmap(unsafe { voidptr(context) }, page) == 0
	println('IOS-SWIFT-TASK-ALLOC: aligned shared fallback, nested payloads and rounded tails, LIFO frees, zero-size and overflow checks, non-top/interior/foreign/protected/double-free rejection before reads, refused live drain, cross-thread transfer, preserved protected x20/x21/x22, eight resolvers/workers, two drained lifetimes; no task creation or scheduling')
}
