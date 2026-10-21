// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
$if macos {
	#include <objc/runtime.h>
}
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
type WeakBinary = fn (u64, u64) u64
type WeakUnary = fn (u64) u64
type WeakDestroy = fn (u64)
type WeakAllocate = fn (i64, u64) SwiftArrayAllocation
struct WeakApi {
	native bool
	entries [9]u64
	integer u64
	@[required]
	allocate WeakAllocate
	@[required]
	release WeakDestroy
	@[required]
	retain_count WeakUnary
}
fn weak_send(owner u64, selector &char) u64 {
	return unsafe { WeakBinary(C.dlsym(voidptr(-2), c'objc_msgSend'))(owner, u64(C.sel_registerName(selector))) }
}
fn weak_api(native bool) WeakApi {
	mut entries := [13]u64{}
	for i, name in ['_swift_unknownObjectWeakInit', '_swift_unknownObjectWeakAssign',
		'_swift_unknownObjectWeakCopyInit', '_swift_unknownObjectWeakTakeInit',
		'_swift_unknownObjectWeakCopyAssign', '_swift_unknownObjectWeakTakeAssign',
		'_swift_unknownObjectWeakLoadStrong', '_swift_unknownObjectWeakTakeStrong',
		'_swift_unknownObjectWeakDestroy', '_$ss27_allocateUninitializedArrayySayxG_BptBwlF',
		'_$sSiN', '_swift_unknownObjectRelease', '_swift_retainCount']! {
		if native {
			lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW); assert lib != unsafe { nil }
			entries[i] = u64(C.dlsym(lib, name[1..].str))
		} else if i != 12 { entries[i] = runtime_symbol('/usr/lib/swift/libswiftCore.dylib', name) or { panic(err) } }
		assert entries[i] != 0 || (!native && i == 12)
	}
	mut operations := [9]u64{}; for i in 0 .. 9 { operations[i] = entries[i] }
	return WeakApi{ native: native, entries: operations, integer: entries[10],
		allocate: unsafe { WeakAllocate(voidptr(entries[9])) }, release: unsafe { WeakDestroy(voidptr(entries[11])) },
		retain_count: unsafe { WeakUnary(voidptr(entries[12])) } }
}
fn (api WeakApi) binary(slot int, destination u64, source u64) {
	call := unsafe { WeakBinary(voidptr(api.entries[slot])) }
	assert call(destination, source) == destination
}
fn (api WeakApi) load(location u64, taking bool) u64 {
	call := unsafe { WeakUnary(voidptr(api.entries[if taking { 7 } else { 6 }])) }; return call(location)
}
fn (api WeakApi) destroy(location u64) {
	call := unsafe { WeakDestroy(voidptr(api.entries[8])) }; call(location)
}
fn (api WeakApi) owner(native_heap bool) u64 {
	if native_heap {
		value := api.allocate(1, api.integer); unsafe { *(&u64(value.bytes)) = 42 }; return value.owner
	}
	$if macos { if api.native { return weak_send(u64(C.objc_getClass(c'NSObject')), c'new') } }
	return objc_allocate(ios_runtime.names['NSObject'])
}
fn (api WeakApi) refs(owner u64, native_heap bool) u64 {
	if native_heap {
		if api.native { return api.retain_count(owner) }
		return (read64(owner + 8) >> 33) + 1
	}
	$if macos { if api.native { return weak_send(owner, c'retainCount') } }
	return u64(obj_header(owner).refs)
}
fn weak_ownership(api WeakApi, native_heap bool) {
	owner := api.owner(native_heap)
	mut source := [u64(0x1234), 0xa5a5a5a5a5a5a5a5, 0x5678]!
	mut destination := [u64(0x1234), 0xa5a5a5a5a5a5a5a5, 0x5678]!
	src := u64(unsafe { &source[1] }); dst := u64(unsafe { &destination[1] })
	api.binary(0, src, owner); assert api.refs(owner, native_heap) == 1
	api.binary(2, dst, src); assert api.refs(owner, native_heap) == 1
	for location in [src, dst]! {
		assert api.load(location, false) == owner && api.refs(owner, native_heap) == 2
		api.release(owner); assert api.refs(owner, native_heap) == 1
	}
	api.binary(4, src, src) // Self copy assignment preserves ownership.
	other := api.owner(!native_heap)
	api.binary(1, dst, other); assert api.refs(other, !native_heap) == 1
	api.binary(4, dst, src); api.release(other)
	assert api.load(dst, false) == owner; api.release(owner)
	api.destroy(dst)
	api.binary(3, dst, src) // Take initialization consumes source, not the object.
	api.binary(0, src, 0); assert api.load(src, false) == 0
	api.binary(5, src, dst)
	assert api.refs(owner, native_heap) == 1
	api.binary(0, dst, 0)
	api.binary(4, dst, src)
	api.release(owner) // All independent copies become nil without retaining.
	assert api.load(src, false) == 0 && api.load(dst, false) == 0
	api.destroy(src); assert api.load(dst, true) == 0
	owner2 := api.owner(native_heap)
	api.binary(0, src, owner2)
	assert api.load(src, true) == owner2 && api.refs(owner2, native_heap) == 2
	api.release(owner2); assert api.refs(owner2, native_heap) == 1
	api.release(owner2)
	assert source[0] == 0x1234 && source[2] == 0x5678 && destination[0] == 0x1234 && destination[2] == 0x5678
}
fn weak_worker(api WeakApi, source u64) {
	for _ in 0 .. 400 {
		mut word := u64(0xa5a5a5a5a5a5a5a5); location := u64(unsafe { &word })
		api.binary(2, location, source)
		value := api.load(location, false); api.release(value)
		value2 := api.load(location, true); api.release(value2)
	}
}
fn weak_concurrent(api WeakApi, native_heap bool) {
	owner := api.owner(native_heap); mut word := u64(0); source := u64(unsafe { &word })
	api.binary(0, source, owner)
	mut workers := []thread{}; for _ in 0 .. 8 { workers << spawn weak_worker(api, source) }
	api.release(owner); workers.wait()
	assert api.load(source, false) == 0; api.destroy(source)
}
fn weak_empty(api WeakApi) {
	mut source := u64(0); mut destination := u64(0)
	src := u64(unsafe { &source }); dst := u64(unsafe { &destination })
	// Valid zero-initialized global weak storage needs no separate init call.
	api.binary(4, dst, src); assert api.load(dst, false) == 0
	api.destroy(dst); api.destroy(src)
	mut cls := u64(0)
	$if macos { if api.native { cls = u64(C.objc_getClass(c'NSObject')) } }
	if !api.native { cls = ios_runtime.names['NSObject'] }
	api.binary(0, src, cls); assert api.load(src, false) == cls; api.release(cls); api.destroy(src)
	if !api.native {
		api.binary(0, src, 0x8000000000000000); api.binary(2, dst, src)
		assert api.load(dst, true) == 0x8000000000000000; api.destroy(src)
	}
}
fn weak_boundary(api WeakApi) {
	page := usize(C.getpagesize())
	base := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert base != u64(-1)
	assert C.mprotect(voidptr(base), page, C.PROT_NONE) == 0
	assert C.mprotect(voidptr(base + u64(page * 2)), page, C.PROT_NONE) == 0
	src := base + u64(page); dst := base + u64(page * 2) - 8
	owner := api.owner(true); api.binary(0, src, owner); api.binary(2, dst, src)
	api.release(owner); assert api.load(src, false) == 0 && api.load(dst, false) == 0
	api.destroy(src); api.destroy(dst); assert C.munmap(voidptr(base), page * 3) == 0
}
struct WeakReentry { location u64 mut: calls int }
fn weak_reentry_reader(location u64) { assert swift_unknown_weak_load(location) == 0 }
fn weak_reentry_dealloc(owner u64, _selector &char) {
	mut state := unsafe { &WeakReentry(obj_header(owner).tag) }
	assert state.calls == 0; worker := spawn weak_reentry_reader(state.location); worker.wait(); state.calls++
}
fn weak_heap_callback(owner u64) {
	location := read64(owner + 16)
	assert swift_unknown_weak_load(location) == 0
	worker := spawn weak_reentry_reader(location); worker.wait()
	swift_heap_deallocate(owner, 32, 15)
}
fn weak_lifetimes(api WeakApi) {
	mut word := u64(0); location := u64(unsafe { &word })
	cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixUnknownWeakReentry', 0)
	assert cls != 0; objc_register_class(cls)
	objc_replace_method(cls, objc_selector(c'dealloc'), u64(unsafe { voidptr(weak_reentry_dealloc) }), c'v16@0:8')
	mut state := WeakReentry{ location: location }; owner := objc_allocate(cls); obj_header(owner).tag = i64(unsafe { &state })
	api.binary(0, location, owner); api.release(owner); assert state.calls == 1; api.destroy(location)
	mut bytes := [64]u64{}; borrowed := u64(unsafe { &bytes[0] })
	assert objc_construct_instance(ios_runtime.names['NSObject'], borrowed) == borrowed
	api.binary(0, location, borrowed); assert objc_destruct_instance(borrowed) == borrowed
	assert api.load(location, false) == 0; api.destroy(location)
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert code != u64(-1)
	for i, instruction in [u32(0xaa1403e0), 0x58000070, 0xd61f0200, 0xd503201f]! { write32(code + u64(i * 4), instruction) }
	unsafe { *(&u64(code + 16)) = u64(voidptr(weak_heap_callback)) }
	// A consumed void-task body clears the result/error and invokes its continuation.
	for i, instruction in [u32(0xd2800014), 0xd2800015, 0xf94006d0, 0xd61f0200]! { write32(code + 32 + u64(i * 4), instruction) }
	write32(code + 64, u32(i32(-32))); write32(code + 68, 16)
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 72)); assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	mut metadata_words := [u64(0), code, 0, 0x400]!
	metadata := u64(unsafe { &metadata_words[3] })
	for mode in 0 .. 3 {
		heap := swift_heap_allocate(metadata, 32, 15); unsafe { *(&u64(heap + 16)) = location }
		api.binary(0, location, heap)
		if mode == 0 { swift_release(heap) }
		else if mode == 1 { swift_set_deallocating(heap); assert api.load(location, false) == 0; swift_heap_deallocate(heap, 32, 15) }
		else { swift_heap_deallocate_uninitialized(heap, 32, 15) }
		assert api.load(location, false) == 0; api.destroy(location)
	}
	task := swift_task_create_checked(0xc000, 0, 0, code + 64, 0) or { panic(err) }
	api.binary(0, location, task.task)
	swift_retain(task.task); swift_task_run(task.task, 0, 0)
	assert api.load(location, false) == task.task; api.release(task.task)
	api.release(task.task); assert api.load(location, false) == 0; api.destroy(location)
	assert C.munmap(voidptr(code), page) == 0
}
fn weak_rejections(api WeakApi) {
	page := usize(C.getpagesize())
	protected := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert protected != u64(-1)
	mut word := u64(0x12345678); location := u64(unsafe { &word })
	for owner in [u64(1), 7, protected, ~u64(0) >> 1]! {
		if _ := swift_unknown_weak_update_checked(location, 0, owner, .initialize) { assert false }
		assert word == 0x12345678 && location !in ios_runtime.swift_unknown_weak
	}
	for bad in [u64(0), 1, 7, ~u64(0) - 7]! { if _ := swift_unknown_weak_address(bad) { assert false } }
	if _ := swift_unknown_weak_load_checked(location, false) { assert false }
	if _ := swift_unknown_weak_destroy_checked(location) { assert false }
	api.binary(0, location, 0)
	if _ := swift_unknown_weak_update_checked(location, 0, 0, .initialize) { assert false }
	if _ := swift_unknown_weak_update_checked(location, location, 0, .take_assign) { assert false }
	word = protected
	if _ := swift_unknown_weak_load_checked(location, false) { assert false }
	word = 0; api.destroy(location)
	assert C.munmap(voidptr(protected), page) == 0
	assert swift_unknown_weak_symbol('__swift_unknownObjectWeakInit') == none
	if _ := runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', '_swift_unknownObjectWeakInit') { assert false }
}
fn weak_suite(api WeakApi) {
	for native_heap in [false, true]! {
		for _ in 0 .. 64 { weak_ownership(api, native_heap) }
		weak_concurrent(api, native_heap)
	}
	weak_empty(api); weak_boundary(api)
	if !api.native { weak_lifetimes(api); weak_rejections(api) }
}
fn test_swift_unknown_weak() {
	$if macos {
		weak_suite(weak_api(true))
		println('IOS-SWIFT-UNKNOWN-WEAK-NATIVE: all nine exports, destination returns, cross-domain copy/move, retained loads, zeroing, guarded cells and concurrent release')
	}
	for _ in 0 .. 2 {
		objc_start(); weak_suite(weak_api(false))
		assert ios_runtime.swift_unknown_weak.len == 0 && ios_runtime.swift_heap.len == 0
		assert ios_runtime.swift_arrays.len == 0 && ios_runtime.live == 0
		objc_stop(); assert ios_runtime.swift_unknown_weak.len == 0
	}
	println('IOS-SWIFT-UNKNOWN-WEAK: native parity, nine exports, nonowning copies/moves, retained loads/takes, zeroing before destructor reentry, explicit teardown, guarded pointers, eight workers and two drained lifetimes')
}
