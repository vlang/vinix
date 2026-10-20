// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32
type StructCopy = fn (u64, u64, i64, bool, bool)

fn struct_copy_guard() u64 {
	page := usize(C.getpagesize())
	base := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert base != u64(-1)
	assert C.mprotect(voidptr(base + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
	return base + u64(page)
}
fn struct_copy_source_byte(index int) u8 { return u8((index * 37 + 11) % 251) }
fn struct_copy_destination_byte(index int) u8 { return u8((index * 13 + 91) % 251) }
fn struct_copy_boundaries(api StructCopy) {
	page := int(C.getpagesize()); source := struct_copy_guard(); destination := struct_copy_guard()
	for flags in 0 .. 4 { for side in 0 .. 2 { for alignment in [0, 1, 7]! {
		for length in [0, 1, 7, 8, 15, 16, 17, 31, 32, 63, 64, 257, page - 1, page]! {
			if length + alignment > page { continue }
			for i in 0 .. page { unsafe { *(&u8(source + u64(i))) = struct_copy_source_byte(i); *(&u8(destination + u64(i))) = struct_copy_destination_byte(i) } }
			src := if side == 0 { alignment } else { page - length - alignment }
			dst := if side == 0 { page - length - alignment } else { alignment }
			api(destination + u64(dst), source + u64(src), i64(length), flags & 1 != 0, flags & 2 != 0)
			for i in 0 .. page {
				expected := if i >= dst && i < dst + length { struct_copy_source_byte(src + i - dst) } else { struct_copy_destination_byte(i) }
				assert unsafe { *(&u8(destination + u64(i))) } == expected
				assert unsafe { *(&u8(source + u64(i))) } == struct_copy_source_byte(i)
			}
		}
	} } }
	// Zero bytes at inaccessible boundaries must not read or write either page.
	for is_atomic in [false, true]! { for strong in [false, true]! { api(destination + u64(page), source - 1, 0, is_atomic, strong) } }
	// hasStrong is obsolete: these pointer-shaped bytes are never object owners.
	for is_atomic in [false, true]! { for strong in [false, true]! {
		mut src := [u64(1), source - 1, ~u64(0), 0]!
		mut dst := [source - 1, u64(1), 0xdeadbeef, ~u64(0)]!
		api(u64(unsafe { &dst[0] }), u64(unsafe { &src[0] }), 32, is_atomic, strong); assert dst == src
	} }
	assert C.munmap(voidptr(source - u64(page)), usize(page * 3)) == 0 && C.munmap(voidptr(destination - u64(page)), usize(page * 3)) == 0
}
fn struct_copy_overlap(api StructCopy) {
	for flags in 0 .. 4 { for shift in [-17, -1, 0, 1, 17]! { for length in [0, 1, 7, 16, 31, 32, 63, 64, 127]! {
		mut bytes := [256]u8{}
		for i in 0 .. 256 { bytes[i] = struct_copy_source_byte(i) }
		src := 64; dst := src + shift; base := u64(unsafe { &bytes[0] })
		api(base + u64(dst), base + u64(src), i64(length), flags & 1 != 0, flags & 2 != 0)
		for i in 0 .. 256 { assert bytes[i] == struct_copy_source_byte(if i >= dst && i < dst + length { src + i - dst } else { i }) }
	} } }
}

const struct_copy_bytes = 16384
fn struct_copy_fill(address u64, seed u64) {
	for i in 0 .. struct_copy_bytes / 8 { unsafe { *(&u64(address + u64(i * 8))) = seed ^ (u64(i) * 17) } }
}
fn struct_copy_verify(address u64) {
	seed := read64(address)
	for i in 0 .. struct_copy_bytes / 8 { assert read64(address + u64(i * 8)) == (seed ^ (u64(i) * 17)) }
}
fn struct_copy_slots(base u64) [9]u64 {
	mut slots := [9]u64{}
	for i in 0 .. 9 {
		region := base + u64(i * (struct_copy_bytes + 1024))
		mask := if i < 8 { u64(7) } else { u64(63) }
		wanted := if i < 8 { u64(i) } else { ((slots[0] >> 4) ^ (slots[0] >> 9)) & 63 }
		for j in 0 .. 64 { address := region + u64(j * 16); if (((address >> 4) ^ (address >> 9)) & mask) == wanted { slots[i] = address; break } }
		assert slots[i] != 0; struct_copy_fill(slots[i], u64(i + 1))
	}
	return slots
}
fn struct_copy_wait(slot &i64, value i64) {
	deadline := time.sys_mono_now() + 30 * time.second
	for C.ios_ref_change(slot, 0) != value { assert time.sys_mono_now() < deadline; time.sleep(time.millisecond) }
}
fn struct_copy_worker(api StructCopy, first u64, second u64, index int, ready &i64, gate &i64, done &i64) {
	input := u64(C.calloc(1, struct_copy_bytes)); output := u64(C.calloc(1, struct_copy_bytes)); assert input != 0 && output != 0
	C.ios_ref_change(ready, 1); struct_copy_wait(gate, 1)
	for iteration in 0 .. 200 {
		struct_copy_fill(input, (u64(index + 1) << 48) | u64(iteration))
		api(first, input, struct_copy_bytes, true, index & 1 != 0)
		api(output, first, struct_copy_bytes, true, index & 1 != 0); struct_copy_verify(output)
		api(if index & 1 == 0 { first } else { second }, if index & 1 == 0 { second } else { first }, struct_copy_bytes, true, false)
	}
	C.free(voidptr(input)); C.free(voidptr(output)); C.ios_ref_change(done, 1)
}
fn struct_copy_stress(api StructCopy, slots [9]u64) {
	mut ready := i64(0); mut gate := i64(0); mut done := i64(0); mut workers := []thread{}
	for index in 0 .. 8 { workers << spawn struct_copy_worker(api, slots[0], slots[1], index, unsafe { &ready }, unsafe { &gate }, unsafe { &done }) }
	struct_copy_wait(unsafe { &ready }, 8); C.ios_ref_change(unsafe { &gate }, 1)
	struct_copy_wait(unsafe { &done }, 8); workers.wait(); unsafe { workers.free() }
	struct_copy_verify(slots[0]); struct_copy_verify(slots[1])
	api(slots[0], slots[8], struct_copy_bytes, true, true)
	api(slots[8], slots[0], struct_copy_bytes, true, false)
	struct_copy_verify(slots[0]); struct_copy_verify(slots[8])
}
fn struct_copy_one(api StructCopy, destination u64, source u64, is_atomic bool, done &i64) {
	api(destination, source, struct_copy_bytes, is_atomic, true); struct_copy_verify(destination); C.ios_ref_change(done, 1)
}
fn struct_copy_noop(destination u64, source u64) {}
fn struct_copy_progress(api StructCopy, slots [9]u64) {
	// Nonatomic copying must bypass both the registry and every struct stripe.
	C.ios_objc_initialize_lock()
	for i in 0 .. 8 { assert C.pthread_mutex_lock(objc_struct_copy_lock(i)) == 0 }
	mut done := i64(0); worker := spawn struct_copy_one(api, slots[0], slots[1], false, unsafe { &done })
	struct_copy_wait(unsafe { &done }, 1); worker.wait()
	for i in 0 .. 8 { assert C.pthread_mutex_unlock(objc_struct_copy_lock(i)) == 0 }
	C.ios_objc_initialize_unlock()
	// C++ callback copies have an independent table, even for identical keys.
	objc_copy_cpp_atomic(slots[0], slots[1], u64(unsafe { voidptr(struct_copy_noop) }))
	for i in 0 .. 8 { assert C.pthread_mutex_lock(objc_cpp_copy_lock(i)) == 0 }
	done = 0; cpp_worker := spawn struct_copy_one(api, slots[0], slots[1], true, unsafe { &done })
	struct_copy_wait(unsafe { &done }, 1); cpp_worker.wait()
	for i in 0 .. 8 { assert C.pthread_mutex_unlock(objc_cpp_copy_lock(i)) == 0 }
	// Holding two struct stripes cannot stop a copy through unrelated stripes.
	for i in 0 .. 2 { assert C.pthread_mutex_lock(objc_struct_copy_lock(i)) == 0 }
	done = 0; independent := spawn struct_copy_one(api, slots[2], slots[3], true, unsafe { &done })
	struct_copy_wait(unsafe { &done }, 1); independent.wait()
	for i in 0 .. 2 { assert C.pthread_mutex_unlock(objc_struct_copy_lock(i)) == 0 }
}
fn struct_copy_cases(api StructCopy, progress bool) {
	struct_copy_boundaries(api); struct_copy_overlap(api)
	base := u64(C.calloc(9, struct_copy_bytes + 1024)); assert base != 0
	slots := struct_copy_slots(base); struct_copy_stress(api, slots)
	if progress { struct_copy_progress(api, slots) }
	C.free(voidptr(base))
}
fn struct_copy_small(api StructCopy, is_atomic bool) {
	mut source := [u64(7), 17, 27, 37]!; mut destination := [u64(0), 0, 0, 0]!
	api(u64(unsafe { &destination[0] }), u64(unsafe { &source[0] }), 32, is_atomic, true); assert destination == source
}
fn struct_copy_cold(api StructCopy, ready &i64, gate &i64) {
	C.ios_ref_change(ready, 1); struct_copy_wait(gate, 1); struct_copy_small(api, true)
}
fn struct_copy_resolve() u64 { return runtime_symbol('/usr/lib/libobjc.A.dylib', '_objc_copyStruct') or { panic(err) } }
__global struct_copy_teardown_calls = 0
fn struct_copy_teardown(object u64, selector u64) {
	struct_copy_small(unsafe { StructCopy(voidptr(struct_copy_resolve())) }, true); struct_copy_teardown_calls++
}
fn test_objc_struct_copy() {
	$if macos {
		library := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2); assert library != unsafe { nil }
		api := unsafe { StructCopy(C.dlsym(library, c'objc_copyStruct')) }
		struct_copy_cases(api, false); assert C.dlclose(library) == 0
		println('NATIVE-OBJC-STRUCT-COPY: guarded lengths and unaligned endpoints, zero-byte protected boundaries, self/overlapping moves, ignored hasStrong with opaque pointer bytes, eight-worker torn-copy and opposing-pair stress, collision deduplication')
	}
	entry := struct_copy_resolve(); api := unsafe { StructCopy(voidptr(entry)) }
	assert !objc_struct_copy_initialized; struct_copy_small(api, false); assert !objc_struct_copy_initialized
	mut ready := i64(0); mut gate := i64(0); mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn struct_copy_cold(api, unsafe { &ready }, unsafe { &gate }) }
	struct_copy_wait(unsafe { &ready }, 8); C.ios_ref_change(unsafe { &gate }, 1); workers.wait(); unsafe { workers.free() }
	assert objc_struct_copy_initialized && sizeof(ObjStructCopyLock) == 128 && sizeof(objc_struct_copy_locks) == 1024
	for symbol in ['objc_copyStruct', '_objc_copyStructExtra', '_objc_copyStruct_atomic']! { if _ := objc_runtime_symbol(symbol) { assert false } }
	for _ in 0 .. 2 {
		objc_start()
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/libc++.1.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation']! { if _ := runtime_symbol(library, '_objc_copyStruct') { assert false } }
		struct_copy_cases(api, true)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.block_refs.len == 0
		for i in 0 .. 8 { assert C.pthread_mutex_trylock(objc_struct_copy_lock(i)) == 0 && C.pthread_mutex_unlock(objc_struct_copy_lock(i)) == 0 }
		cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixStructCopyTeardown', 0)
		assert cls != 0 && objc_add_method(cls, u64(c'dealloc'), u64(unsafe { voidptr(struct_copy_teardown) }), c'v16@0:8')
		objc_register_class(cls); objc_autorelease(objc_new(cls)); before := struct_copy_teardown_calls
		objc_stop(); assert struct_copy_teardown_calls == before + 1 && ios_runtime.live == 0 && struct_copy_resolve() == entry
		struct_copy_small(api, true)
	}
	println('IOS-OBJC-STRUCT-COPY: guarded and overlapping memmove, ignored hasStrong and no implicit ownership, eight cold callers, fixed independent 1 KiB process-lifetime table, eight-worker 16 KiB torn-copy/opposing-pair stress, collision deduplication, nonatomic bypass of all locks, independent C++/struct stripe progress, shutdown callbacks and two drained runtimes; no per-copy allocation')
}
