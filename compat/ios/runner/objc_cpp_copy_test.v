// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32
fn C.sched_yield() i32
type CppCopyAtomic = fn (u64, u64, u64)

__global cpp_copy_seen_destination = u64(0)
__global cpp_copy_seen_source = u64(0)
__global cpp_copy_seen_calls = 0
fn cpp_copy_observe(destination u64, source u64) {
	cpp_copy_seen_destination = destination
	cpp_copy_seen_source = source
	cpp_copy_seen_calls++
}
fn cpp_copy_opaque(api CppCopyAtomic) {
	page := usize(C.getpagesize())
	guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert guard != u64(-1)
	before := cpp_copy_seen_calls
	for destination in [u64(0), 1, ~u64(0), guard, guard + u64(page) - 1]! {
		for source in [u64(0), 1, ~u64(0), guard, guard + u64(page) - 1]! {
			calls := cpp_copy_seen_calls
			api(destination, source, u64(unsafe { voidptr(cpp_copy_observe) }))
			assert cpp_copy_seen_calls == calls + 1 && cpp_copy_seen_destination == destination && cpp_copy_seen_source == source
		}
	}
	assert cpp_copy_seen_calls == before + 25 && C.munmap(voidptr(guard), page) == 0
}

struct CppCopyResource {
mut:
	refs i64
	value u64
}
__global cpp_copy_destroyed = i64(0)
__global cpp_copy_assignments = i64(0)
fn cpp_copy_resource(value u64) u64 {
	mut resource := unsafe { &CppCopyResource(C.calloc(1, sizeof(CppCopyResource))) }; assert resource != unsafe { nil }
	resource.refs = 1; resource.value = value
	return u64(resource)
}
fn cpp_copy_drop(resource u64) {
	if resource == 0 { return }
	if C.ios_ref_change(unsafe { &(&CppCopyResource(resource)).refs }, -1) == 1 {
		C.ios_ref_change(unsafe { &cpp_copy_destroyed }, 1)
		C.free(unsafe { voidptr(resource) })
	}
}
fn cpp_copy_assign(destination u64, source u64) {
	value := read64(source); tag := read64(source + 8); old := read64(destination)
	if value != 0 { C.ios_ref_change(unsafe { &(&CppCopyResource(value)).refs }, 1) }
	unsafe { *(&u64(destination)) = value; *(&u64(destination + 8)) = tag + 7 }
	cpp_copy_drop(old)
	C.ios_ref_change(unsafe { &cpp_copy_assignments }, 1)
}
fn cpp_copy_ownership(api CppCopyAtomic) {
	before := cpp_copy_destroyed; copies := cpp_copy_assignments
	for _ in 0 .. 100 {
		resource := cpp_copy_resource(1234); previous := cpp_copy_resource(5678)
		mut source := [u64(0xaaaa), resource, 40, 0xbbbb]!
		mut destination := [u64(0xcccc), previous, 99, 0xdddd]!
		src := u64(unsafe { &source[1] }); dst := u64(unsafe { &destination[1] })
		api(dst, src, u64(unsafe { voidptr(cpp_copy_assign) }))
		assert destination[1] == resource && destination[2] == 47 && unsafe { (&CppCopyResource(resource)).refs } == 2
		api(dst, dst, u64(unsafe { voidptr(cpp_copy_assign) }))
		assert destination[2] == 54 && unsafe { (&CppCopyResource(resource)).refs } == 2
		api(src, dst, u64(unsafe { voidptr(cpp_copy_assign) }))
		assert source[2] == 61 && unsafe { (&CppCopyResource(resource)).value } == 1234
		assert source[0] == 0xaaaa && source[3] == 0xbbbb && destination[0] == 0xcccc && destination[3] == 0xdddd
		cpp_copy_drop(source[1]); cpp_copy_drop(destination[1])
	}
	assert cpp_copy_destroyed == before + 200 && cpp_copy_assignments == copies + 300
}

fn cpp_copy_pair(destination u64, source u64) {
	value := read64(source)
	C.sched_yield()
	check := read64(source + 8); assert check == ~value
	unsafe { *(&u64(destination)) = value }
	C.sched_yield()
	unsafe { *(&u64(destination + 8)) = check }
}
fn cpp_copy_slots(base u64) [9]u64 {
	mut slots := [9]u64{}
	for i in 0 .. 512 {
		address := base + u64(i * 32); index := objc_cpp_copy_index(address)
		if slots[index] == 0 { slots[index] = address }
	}
	for i in 0 .. 8 { assert slots[i] != 0 }
	// A 64-stripe collision also collides with Apple's eight-stripe iOS table.
	key := ((slots[0] >> 4) ^ (slots[0] >> 9)) & 63
	for i in 0 .. 512 { address := base + u64(i * 32); if address != slots[0] && (((address >> 4) ^ (address >> 9)) & 63) == key { slots[8] = address; break } }
	assert slots[8] != 0
	for i, address in slots { unsafe { *(&u64(address)) = u64(i + 1); *(&u64(address + 8)) = ~u64(i + 1) } }
	return slots
}
fn cpp_copy_wait(slot &i64, value i64) {
	deadline := time.sys_mono_now() + 30 * time.second
	for C.ios_ref_change(slot, 0) != value { assert time.sys_mono_now() < deadline; time.sleep(time.millisecond) }
}
fn cpp_copy_worker(api CppCopyAtomic, first u64, second u64, index int, ready &i64, gate &i64, done &i64) {
	mut input := [u64(index + 100), ~u64(index + 100)]!
	mut output := [u64(0), ~u64(0)]!
	C.ios_ref_change(ready, 1); cpp_copy_wait(gate, 1)
	for _ in 0 .. 200 {
		input[0]++; input[1] = ~input[0]
		api(first, u64(unsafe { &input[0] }), u64(unsafe { voidptr(cpp_copy_pair) }))
		api(u64(unsafe { &output[0] }), first, u64(unsafe { voidptr(cpp_copy_pair) }))
		assert output[1] == ~output[0]
		api(if index & 1 == 0 { first } else { second }, if index & 1 == 0 { second } else { first }, u64(unsafe { voidptr(cpp_copy_pair) }))
	}
	C.ios_ref_change(done, 1)
}
fn cpp_copy_stress(api CppCopyAtomic, slots [9]u64) {
	mut ready := i64(0); mut gate := i64(0); mut done := i64(0); mut workers := []thread{}
	for index in 0 .. 8 { workers << spawn cpp_copy_worker(api, slots[0], slots[1], index, unsafe { &ready }, unsafe { &gate }, unsafe { &done }) }
	cpp_copy_wait(unsafe { &ready }, 8); C.ios_ref_change(unsafe { &gate }, 1)
	cpp_copy_wait(unsafe { &done }, 8); workers.wait(); unsafe { workers.free() }
	assert read64(slots[0] + 8) == ~read64(slots[0]) && read64(slots[1] + 8) == ~read64(slots[1])
	// Two distinct addresses hashing to one stripe must lock it only once.
	api(slots[0], slots[8], u64(unsafe { voidptr(cpp_copy_pair) }))
	api(slots[8], slots[0], u64(unsafe { voidptr(cpp_copy_pair) }))
}

struct CppCopyProgress {
	@[required]
	api CppCopyAtomic
	slots [9]u64
mut:
	done i64
}
__global cpp_copy_progress = &CppCopyProgress(unsafe { nil })
fn cpp_copy_independent(state &CppCopyProgress) {
	C.ios_objc_initialize_lock(); C.ios_objc_initialize_unlock()
	state.api(state.slots[2], state.slots[3], u64(unsafe { voidptr(cpp_copy_pair) }))
	C.ios_ref_change(unsafe { &state.done }, 1)
}
fn cpp_copy_nested(destination u64, source u64) {
	state := cpp_copy_progress
	state.api(state.slots[4], state.slots[5], u64(unsafe { voidptr(cpp_copy_pair) }))
	worker := spawn cpp_copy_independent(state)
	cpp_copy_wait(unsafe { &state.done }, 1); worker.wait()
	cpp_copy_pair(destination, source)
}
fn cpp_copy_progress_case(api CppCopyAtomic, slots [9]u64) {
	mut state := CppCopyProgress{api: api, slots: slots}
	cpp_copy_progress = unsafe { &state }
	api(slots[0], slots[1], u64(unsafe { voidptr(cpp_copy_nested) }))
	assert state.done == 1
	cpp_copy_progress = unsafe { nil }
}
fn cpp_copy_cases(api CppCopyAtomic) {
	cpp_copy_opaque(api); cpp_copy_ownership(api)
	base := u64(C.calloc(1, 16384)); assert base != 0
	slots := cpp_copy_slots(base)
	cpp_copy_stress(api, slots); cpp_copy_progress_case(api, slots)
	C.free(unsafe { voidptr(base) })
}
fn cpp_copy_cold(api CppCopyAtomic) {
	mut source := [u64(7), ~u64(7)]!; mut destination := [u64(0), ~u64(0)]!
	api(u64(unsafe { &destination[0] }), u64(unsafe { &source[0] }), u64(unsafe { voidptr(cpp_copy_pair) }))
	assert destination == source
}
fn cpp_copy_cold_worker(api CppCopyAtomic, ready &i64, gate &i64) {
	C.ios_ref_change(ready, 1); cpp_copy_wait(gate, 1)
	cpp_copy_cold(api)
}
fn cpp_copy_resolve() u64 { return runtime_symbol('/usr/lib/libobjc.A.dylib', '_objc_copyCppObjectAtomic') or { panic(err) } }
__global cpp_copy_teardown_calls = 0
fn cpp_copy_teardown(object u64, selector u64) {
	cpp_copy_cold(unsafe { CppCopyAtomic(voidptr(cpp_copy_resolve())) }); cpp_copy_teardown_calls++
}
fn test_objc_cpp_copy() {
	$if macos {
		library := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2); assert library != unsafe { nil }
		api := unsafe { CppCopyAtomic(C.dlsym(library, c'objc_copyCppObjectAtomic')) }
		cpp_copy_cases(api); assert C.dlclose(library) == 0
		println('NATIVE-OBJC-CPP-COPY: exact callback arguments including self/null/protected identities, callback-managed C++ ownership, torn-copy stress and opposing pairs, collision deduplication, nested disjoint copy and independent-thread progress')
	}
	entry := cpp_copy_resolve(); api := unsafe { CppCopyAtomic(voidptr(entry)) }
	assert !objc_cpp_copy_initialized
	mut ready := i64(0); mut gate := i64(0); mut cold := []thread{}
	for _ in 0 .. 8 { cold << spawn cpp_copy_cold_worker(api, unsafe { &ready }, unsafe { &gate }) }
	cpp_copy_wait(unsafe { &ready }, 8); C.ios_ref_change(unsafe { &gate }, 1)
	cold.wait(); unsafe { cold.free() }
	assert objc_cpp_copy_initialized && sizeof(ObjCppCopyLock) == 128 && sizeof(objc_cpp_copy_locks) == 1024
	for symbol in ['objc_copyCppObjectAtomic', '_objc_copyCppObjectAtomicExtra', '_objc_copyStruct']! { if _ := objc_runtime_symbol(symbol) { assert false } }
	for _ in 0 .. 2 {
		objc_start()
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/libc++.1.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation']! { if _ := runtime_symbol(library, '_objc_copyCppObjectAtomic') { assert false } }
		cpp_copy_cases(api)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.block_refs.len == 0
		for i in 0 .. 8 { assert C.pthread_mutex_trylock(objc_cpp_copy_lock(i)) == 0 && C.pthread_mutex_unlock(objc_cpp_copy_lock(i)) == 0 }
		cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixCppCopyTeardown', 0)
		assert cls != 0 && objc_add_method(cls, u64(c'dealloc'), u64(unsafe { voidptr(cpp_copy_teardown) }), c'v16@0:8')
		objc_register_class(cls); objc_autorelease(objc_new(cls)); before := cpp_copy_teardown_calls
		objc_stop(); assert cpp_copy_teardown_calls == before + 1 && ios_runtime.live == 0 && cpp_copy_resolve() == entry
		cpp_copy_cold(api)
	}
	println('IOS-OBJC-CPP-COPY: eight cold callers, fixed 1 KiB process-lifetime locks, exact opaque callback forwarding and self-copy, callback-managed ownership, eight-worker torn-copy/opposing-pair stress, collision deduplication, nested disjoint and registry/independent-thread progress, shutdown callbacks and two drained runtimes; no per-copy allocation or implicit Objective-C ownership')
}
