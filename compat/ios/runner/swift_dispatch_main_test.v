// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#include <dlfcn.h>
}
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.mincore(voidptr, usize, &u8) i32
type MainQueueProbe = fn (u64, u64, &u64)
type MainQueueGetter = fn () u64
type MainQueueRetain = fn (u64) u64
type MainQueueRelease = fn (u64)
type MainQueueCopy = fn (u64, u64, u64) u64
type MainQueueDestroy = fn (u64, u64)

fn main_queue_call(probe MainQueueProbe, entry u64, guard u64, identity u64) {
	mut result := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	probe(entry, guard, unsafe { &result[1] })
	assert result[0] == 0xcafe && result[1] == identity && result[3] == guard
		&& result[4] == 0x5021 && result[5] == 0xbeef
}
fn main_queue_values(table u64, identity u64, guard u64) {
	for slot in [u64(0), 2, 3, 4, 5]! {
		mut source := [u64(0xcafe), identity, 0xbeef]!
		mut destination := [u64(0xcafe), 0, 0xbeef]!
		transfer := unsafe { MainQueueCopy(voidptr(read64(table + slot * 8) & 0x0000ffffffffffff)) }
		assert transfer(u64(unsafe { &destination[1] }), u64(unsafe { &source[1] }), guard) == u64(unsafe { &destination[1] })
		assert source == [u64(0xcafe), identity, 0xbeef]! && destination == source
		destroy := unsafe { MainQueueDestroy(voidptr(read64(table + 8) & 0x0000ffffffffffff)) }
		destroy(u64(unsafe { &destination[1] }), guard)
	}
}
fn main_queue_worker() u64 {
	mut entry := u64(0)
	for _ in 0 .. 256 {
		entry = runtime_symbol('/usr/lib/swift/libswiftDispatch.dylib', '_$sSo17OS_dispatch_queueC8DispatchE4mainABvgZ') or { panic(err) }
		getter := unsafe { MainQueueGetter(voidptr(entry)) }
		identity := getter()
		assert identity == darwin_dispatch_get_main_queue() && !swift_unknown_is_native(identity)
		assert swift_unknown_retain(identity) == identity
		swift_unknown_release(identity); objc_release(identity)
	}
	return entry
}
struct MainQueueTurn {
	identity u64
	thread u64
mut:
	turns int
}
fn main_queue_turn(context voidptr) {
	mut state := unsafe { &MainQueueTurn(context) }
	assert u64(C.pthread_self()) == state.thread
	state.turns++
	if state.turns == 1 { darwin_dispatch_async_f(state.identity, context, main_queue_turn) }
}
fn main_queue_refs(identity u64) int {
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	return dispatch_runtime.queues[identity].refs
}
fn main_queue_unavailable() {
	if _ := swift_dispatch_main_queue_checked() { assert false }
	if _ := runtime_symbol('/usr/lib/swift/libswiftDispatch.dylib', '_$sSo17OS_dispatch_queueC8DispatchE4mainABvgZ') { assert false }
}
fn test_swift_dispatch_main() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1) && guard != u64(-1)
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0203f3, 0xaa0003f0,
		0xaa0103f4, 0xaa0103e0, 0xaa0103e8, 0xd28a0435, 0xd63f0200, 0xa9000660,
		0xa9015674, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 64))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { MainQueueProbe(voidptr(code)) }
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftDispatch.dylib', 2)
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		dispatch := C.dlopen(c'/usr/lib/system/libdispatch.dylib', 2)
		assert lib != unsafe { nil } && core != unsafe { nil } && dispatch != unsafe { nil }
		entry := u64(C.dlsym(lib, c'$sSo17OS_dispatch_queueC8DispatchE4mainABvgZ'))
		identity := u64(C.dlsym(dispatch, c'_dispatch_main_q'))
		table := u64(C.dlsym(core, c'$sBOWV'))
		retain_queue := unsafe { MainQueueRetain(C.dlsym(core, c'swift_unknownObjectRetain')) }
		release_queue := unsafe { MainQueueRelease(C.dlsym(core, c'swift_unknownObjectRelease')) }
		assert entry != 0 && identity != 0 && table != 0
		for _ in 0 .. 256 {
			main_queue_call(probe, entry, guard, identity)
			assert retain_queue(identity) == identity; release_queue(identity); release_queue(identity)
		}
		main_queue_values(table, identity, guard)
		println('IOS-DISPATCH-MAIN-NATIVE: canonical _dispatch_main_q, direct owned x0 result, protected unused x0/x8/context and x20/x21 preservation, repeated unknown-object ARC and all copy/take/assignment/destruction witnesses')
	}
	main_queue_unavailable(); assert !dispatch_objc_is_queue(guard)
	for _ in 0 .. 2 {
		objc_start(); main_queue_unavailable(); assert ios_runtime.swift_dispatch_flags_arena == 0
		system_data_start()!
		assert !dispatch_objc_is_queue(guard) && !dispatch_objc_is_queue(0)
		// Unknown library/symbol rejection must not publish the Dispatch arena.
		if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSo17OS_dispatch_queueC8DispatchE4mainABvgZ') { assert false }
		if _ := runtime_symbol('/usr/lib/swift/libswiftDispatch.dylib', '_$sSo17OS_dispatch_queueCMa') { assert false }
		assert ios_runtime.swift_dispatch_flags_arena == 0
		mut workers := []thread u64{}
		for _ in 0 .. 8 { workers << spawn main_queue_worker() }
		entries := workers.wait(); entry := entries[0]
		for other in entries { assert other == entry }
		identity := darwin_dispatch_get_main_queue()
		assert dispatch_objc_is_queue(identity) && main_queue_refs(identity) == 1
		main_queue_call(probe, entry, guard, identity); objc_release(identity)
		main_queue_values(swift_unknown_value_witnesses(), identity, guard)
		assert main_queue_refs(identity) == 1 && ios_runtime.swift_heap.len == 0 && ios_runtime.live == 0
		// An ordinary queue must use its scheduler reference count, not a header.
		child := darwin_dispatch_queue_create_with_target(c'swift.arc.queue', 0, identity)
		assert dispatch_objc_is_queue(child) && main_queue_refs(child) == 1
		assert swift_unknown_retain(child) == child && main_queue_refs(child) == 2
		swift_unknown_release(child); assert main_queue_refs(child) == 1
		swift_unknown_release(child); assert !dispatch_objc_is_queue(child)
		mut state := MainQueueTurn{identity: identity, thread: u64(C.pthread_self())}
		darwin_dispatch_async_f(identity, unsafe { &state }, main_queue_turn)
		assert state.turns == 0 && dispatch_main_drain() && state.turns == 1
		assert dispatch_main_drain() && state.turns == 2 && !dispatch_main_drain()
		darwin_dispatch_async_f(identity, unsafe { &state }, main_queue_turn)
		dispatch_stop(); main_queue_unavailable(); assert state.turns == 2
		// Queue ARC remains valid while quiescing, until system data is freed.
		assert swift_unknown_retain(identity) == identity; swift_unknown_release(identity)
		arena := ios_runtime.swift_dispatch_flags_arena
		objc_stop(); main_queue_unavailable()
		assert ios_runtime.swift_dispatch_flags_retired && ios_runtime.swift_dispatch_flags_arena == 0
		$if macos { assert C.mprotect(voidptr(arena), page * 2, C.PROT_READ) == -1 }
		$else { mut resident := [u8(0), 0]!; assert C.mincore(voidptr(arena), page * 2, unsafe { &resident[0] }) == -1 }
		system_data_stop(); main_queue_unavailable(); assert !dispatch_objc_is_queue(identity)
	}
	assert C.munmap(voidptr(code), page) == 0 && C.munmap(voidptr(guard), page) == 0
	println('IOS-DISPATCH-MAIN: exact Dispatch-only getter, canonical owned main queue with no reference churn, registered queue unknown-object ARC, sealed shared arena/eight-worker publication, main-thread callbacks/reentrant turns/shutdown cancellation, startup/retired guards and two unmapped lifetimes')
}
