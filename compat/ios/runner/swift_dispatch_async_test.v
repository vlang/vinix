// SPDX-License-Identifier: GPL-2.0-or-later
module main
import time
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.mincore(voidptr, usize, &u8) i32
type AsyncProbe = fn (u64, u64, u64, u64, u64, u64, u64, &u64)
type AsyncQueueCreate = fn (&char, u64) u64
type AsyncQueueControl = fn (u64)
type AsyncQueueSync = fn (u64, voidptr, DispatchFunction)
type AsyncBlockCopy = fn (u64) u64
type AsyncRetain = fn (u64) u64
type AsyncRelease = fn (u64)
__global async_fixture_descriptor = [4]u64{}
struct AsyncApi {
	native bool
	entry u64
	queue u64
	stack_isa u64
	global_isa u64
	qos u64
	flags u64
	guard u64
	@[required]
	probe AsyncProbe
	@[required]
	retain_queue AsyncRetain
	@[required]
	release_queue AsyncRelease
	@[required]
	copy_block AsyncBlockCopy
	@[required]
	release_block AsyncRelease
}
struct AsyncCapture {
	api AsyncApi
	reentrant bool
	stop_in_copy bool
mut:
	copies i64
	disposes i64
	calls i64
	observed u64
}
fn async_counter(value &i64) u64 { return C.ios_load_pointer(unsafe { &u64(value) }) }
fn async_helper_reader(queue u64) bool {
	known := dispatch_objc_is_queue(queue)
	C.ios_objc_initialize_lock(); C.ios_objc_initialize_unlock()
	return known
}
fn async_fixture_copy(destination u64, source u64) {
	mut state := unsafe { &AsyncCapture(read64(source + 32)) }
	unsafe { *(&u64(destination + 32)) = u64(state) }
	C.ios_ref_change(unsafe { &state.copies }, 1)
	assert state.api.retain_queue(state.api.queue) == state.api.queue
	if !state.api.native {
		worker := spawn async_helper_reader(state.api.queue); assert worker.wait()
		if state.stop_in_copy { dispatch_stop() }
	}
}
fn async_fixture_dispose(block u64) {
	mut state := unsafe { &AsyncCapture(read64(block + 32)) }
	if !state.api.native { worker := spawn async_helper_reader(state.api.queue); assert worker.wait() }
	state.api.release_queue(state.api.queue)
	// Publish completion after the helper's last access to the borrowed state.
	C.ios_ref_change(unsafe { &state.disposes }, 1)
}
fn (api AsyncApi) submit(block u64) {
	mut result := [u64(0xcafe), 0, 0, 0xbeef]!
	api.probe(api.entry, 0, api.qos, api.flags, block, api.queue, api.guard, unsafe { &result[1] })
	assert result == [u64(0xcafe), api.queue, 0x5021, 0xbeef]!
}
fn async_fixture_body(block u64) {
	mut state := unsafe { &AsyncCapture(read64(block + 32)) }
	state.observed = block; C.ios_ref_change(unsafe { &state.calls }, 1)
	if !state.api.native { assert u64(C.pthread_self()) == ios_runtime.main_thread }
	if state.reentrant && async_counter(unsafe { &state.calls }) == 1 {
		mut literal := [state.api.stack_isa, u64(1) << 25, u64(unsafe { voidptr(async_fixture_body) }), u64(unsafe { &async_fixture_descriptor[0] }), u64(state)]!
		state.api.submit(u64(unsafe { &literal[0] }))
	}
}
fn async_native_noop(_context voidptr) {}
fn async_queue_refs(queue u64) int {
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	registered := dispatch_runtime.queues[queue] or { panic('missing fixture queue') }
	return registered.refs
}
fn async_fixture_case(api AsyncApi, kind int) {
	mut state := AsyncCapture{api: api, reentrant: kind == 3, stop_in_copy: kind == 5}
	mut literal := [if kind == 1 { api.global_isa } else { api.stack_isa },
		if kind == 1 { u64(1) << 28 } else { u64(1) << 25 },
		u64(unsafe { voidptr(async_fixture_body) }), u64(unsafe { &async_fixture_descriptor[0] }), u64(unsafe { &state })]!
	stack := u64(unsafe { &literal[0] }); input := if kind == 2 { api.copy_block(stack) } else { stack }
	$if macos { if api.native { suspend_queue := unsafe { AsyncQueueControl(C.dlsym(voidptr(-2), c'dispatch_suspend')) }; suspend_queue(api.queue) } }
	api.submit(input)
	assert async_counter(unsafe { &state.calls }) == 0
	assert async_counter(unsafe { &state.copies }) == if kind == 1 { u64(0) } else { u64(1) }
	if kind == 2 { api.release_block(input) }
	if kind != 1 { literal[4] = api.guard } // Promoted captures must survive stack mutation.
	if api.native {
		$if macos {
			resume_queue := unsafe { AsyncQueueControl(C.dlsym(voidptr(-2), c'dispatch_resume')) }
			flush_queue := unsafe { AsyncQueueSync(C.dlsym(voidptr(-2), c'dispatch_sync_f')) }
			resume_queue(api.queue); flush_queue(api.queue, unsafe { nil }, async_native_noop)
			limit := time.sys_mono_now() + 3_000_000_000
			for async_counter(unsafe { &state.calls }) != if kind == 3 { u64(2) } else { u64(1) }
				|| async_counter(unsafe { &state.disposes }) != if kind == 1 { u64(0) } else if kind == 3 { u64(2) } else { u64(1) } {
				assert time.sys_mono_now() < limit; time.sleep(time.millisecond)
			}
		}
	} else if kind in [4, 5]! {
		if kind == 4 { dispatch_stop() }
		assert async_counter(unsafe { &state.calls }) == 0 && async_counter(unsafe { &state.disposes }) == 1
		assert ios_runtime.block_refs.len == 0 && async_queue_refs(api.queue) == 1
	} else {
		assert async_queue_refs(api.queue) == if kind == 1 { 2 } else { 3 }
		assert ios_runtime.block_refs.len == if kind == 1 { 0 } else { 1 }
		assert dispatch_main_drain() && async_counter(unsafe { &state.calls }) == 1
		if kind == 3 {
			assert async_counter(unsafe { &state.copies }) == 2 && async_counter(unsafe { &state.disposes }) == 1
			assert dispatch_main_drain() && async_counter(unsafe { &state.calls }) == 2
		}
		assert !dispatch_main_drain() && ios_runtime.block_refs.len == 0 && async_queue_refs(api.queue) == 1
	}
	if kind != 1 && kind !in [4, 5]! { assert state.observed != stack }
	if kind == 1 { assert state.observed == stack }
	api.release_queue(api.queue)
	if !api.native { assert !dispatch_objc_is_queue(api.queue) }
}
fn async_worker() u64 {
	mut entry := u64(0)
	for _ in 0 .. 128 { entry = runtime_symbol('/usr/lib/swift/libswiftDispatch.dylib', '_$sSo17OS_dispatch_queueC8DispatchE5async5group3qos5flags7executeySo0a1_b1_F0CSg_AC0D3QoSVAC0D13WorkItemFlagsVyyXBtF') or { panic(err) } }
	return entry
}
fn async_reject(group u64, qos u64, flags u64, block u64, queue u64) {
	mut rejected := false
	swift_dispatch_async_checked(group, qos, flags, block, queue) or { rejected = true }
	assert rejected
}
fn test_swift_dispatch_async() {
	// The Block ABI borrows this descriptor for the lifetime of every copy.
	async_fixture_descriptor = [u64(0), 40, u64(unsafe { voidptr(async_fixture_copy) }), u64(unsafe { voidptr(async_fixture_dispose) })]!
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	values := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1) && values != u64(-1)
	qos := values + u64(page) - 16; guard := values + u64(page); flags := values + u64(page * 3) - 8
	unsafe { *(&u64(qos)) = 0x8877665544332205; *(&u64(qos + 8)) = 0; *(&u64(flags)) = 0 }
	assert C.mprotect(voidptr(values), page, C.PROT_READ) == 0 && C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	assert C.mprotect(voidptr(guard + u64(page)), page, C.PROT_READ) == 0
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0703f3,
		0xaa0503f4, 0xd28a0435, 0xaa0603e8, 0xaa0103e0, 0xaa0203e1, 0xaa0303e2,
		0xaa0403e3, 0xaa0603e4, 0xd63f0200, 0xa9005674, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 76)); assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { AsyncProbe(voidptr(code)) }
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftDispatch.dylib', 2); core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		dispatch := C.dlopen(c'/usr/lib/system/libdispatch.dylib', 2); assert lib != unsafe { nil } && core != unsafe { nil } && dispatch != unsafe { nil }
		entry := u64(C.dlsym(lib, c'$sSo17OS_dispatch_queueC8DispatchE5async5group3qos5flags7executeySo0a1_b1_F0CSg_AC0D3QoSVAC0D13WorkItemFlagsVyyXBtF'))
		create_queue := unsafe { AsyncQueueCreate(C.dlsym(dispatch, c'dispatch_queue_create')) }; assert entry != 0
		for kind in 0 .. 4 {
			api := AsyncApi{native: true, entry: entry, queue: create_queue(c'vinix.swift.async.native', 0),
				stack_isa: u64(C.dlsym(dispatch, c'_NSConcreteStackBlock')), global_isa: u64(C.dlsym(dispatch, c'_NSConcreteGlobalBlock')),
				qos: qos, flags: flags, guard: guard, probe: probe,
				retain_queue: unsafe { AsyncRetain(C.dlsym(core, c'swift_unknownObjectRetain')) }, release_queue: unsafe { AsyncRelease(C.dlsym(core, c'swift_unknownObjectRelease')) },
				copy_block: unsafe { AsyncBlockCopy(C.dlsym(dispatch, c'_Block_copy')) }, release_block: unsafe { AsyncRelease(C.dlsym(dispatch, c'_Block_release')) }}
			assert api.queue != 0 && api.stack_isa != 0 && api.global_isa != 0; async_fixture_case(api, kind)
		}
		println('IOS-DISPATCH-ASYNC-NATIVE: x0 group/x1 QoS/x2 flags/x3 borrowed block/x20 queue, protected readonly values and unused x8, x20/x21 preservation, copied stack captures/global identity/heap ownership, balanced queue capture ARC and reentrant serial callbacks')
	}
	async_reject(guard, guard, guard, guard, guard)
	for _ in 0 .. 2 {
		objc_start(); async_reject(guard, guard, guard, guard, guard)
		if _ := swift_dispatch_symbol('_$sSo17OS_dispatch_queueC8DispatchE5async5group3qos5flags7executeySo0a1_b1_F0CSg_AC0D3QoSVAC0D13WorkItemFlagsVyyXBtF') { assert false }
		assert ios_runtime.swift_dispatch_flags_arena == 0; system_data_start()!
		if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSo17OS_dispatch_queueC8DispatchE5async5group3qos5flags7executeySo0a1_b1_F0CSg_AC0D3QoSVAC0D13WorkItemFlagsVyyXBtF') { assert false }
		if _ := swift_dispatch_symbol('_$sSo17OS_dispatch_queueC8DispatchE11asyncUnsafe5group3qos5flags7executeySo0a1_b1_G0CSg_AC0D3QoSVAC0D13WorkItemFlagsVyyXBtF') { assert false }
		assert ios_runtime.swift_dispatch_flags_arena == 0
		mut workers := []thread u64{}; for _ in 0 .. 8 { workers << spawn async_worker() }; entries := workers.wait(); entry := entries[0]
		for other in entries { assert other == entry }
		main_queue := darwin_dispatch_get_main_queue()
		for args in [[guard, guard, guard, guard, main_queue]!, [u64(0), guard, guard, guard, guard]!,
			[u64(0), 0, flags, guard, main_queue]!, [u64(0), qos, 0, guard, main_queue]!, [u64(0), qos, flags, 0, main_queue]!]! { async_reject(args[0], args[1], args[2], args[3], args[4]) }
		for tag in [u64(0), 1, 2, 3, 4, 6, 255]! { mut invalid := [tag, u64(0)]!; async_reject(0, u64(unsafe { &invalid[0] }), guard, guard, main_queue) }
		mut invalid_priority := [u64(5), 1]!; async_reject(0, u64(unsafe { &invalid_priority[0] }), guard, guard, main_queue)
		for bits in [u64(1), 2, 4, 8, 16, 32, 1 << 63, ~u64(0)]! { mut invalid := bits; async_reject(0, qos, u64(unsafe { &invalid }), guard, main_queue) }
		assert ios_runtime.block_refs.len == 0 && dispatch_runtime.jobs.len == 0
		for kind in 0 .. 5 {
			api := AsyncApi{entry: entry, queue: darwin_dispatch_queue_create_with_target(c'vinix.swift.async', 0, main_queue), stack_isa: block_isa(0), global_isa: block_isa(1),
				qos: qos, flags: flags, guard: guard, probe: probe, retain_queue: swift_unknown_retain, release_queue: swift_unknown_release, copy_block: block_copy, release_block: block_release}
			async_fixture_case(api, kind)
		}
		async_reject(guard, guard, guard, guard, main_queue)
		arena := ios_runtime.swift_dispatch_flags_arena; objc_stop(); async_reject(guard, guard, guard, guard, guard)
		assert ios_runtime.swift_dispatch_flags_retired && ios_runtime.swift_dispatch_flags_arena == 0 && ios_runtime.block_refs.len == 0 && ios_runtime.live == 0
		$if macos { assert C.mprotect(voidptr(arena), page * 2, C.PROT_READ) == -1 }
		$else { mut resident := [u8(0), 0]!; assert C.mincore(voidptr(arena), page * 2, unsafe { &resident[0] }) == -1 }
		system_data_stop()
	}
	// A stop requested by a copy helper cancels the copy outside both locks.
	objc_start(); system_data_start()!; entry := async_worker()
	api := AsyncApi{entry: entry, queue: darwin_dispatch_queue_create_with_target(c'vinix.swift.async.copy-stop', 0, darwin_dispatch_get_main_queue()), stack_isa: block_isa(0), global_isa: block_isa(1),
		qos: qos, flags: flags, guard: guard, probe: probe, retain_queue: swift_unknown_retain, release_queue: swift_unknown_release, copy_block: block_copy, release_block: block_release}
	async_fixture_case(api, 5); objc_stop(); system_data_stop()
	assert C.munmap(voidptr(code), page) == 0 && C.munmap(voidptr(values), page * 3) == 0
	println('IOS-DISPATCH-ASYNC: exact Dispatch-only default profile, native Swift ABI, borrowed block ownership and captured queue ARC, unlocked copy/dispose helper reentry, main-thread deferred/reentrant turns, cancellation and stop during copy, protected unsupported/lifetime rejection, eight-worker shared publication and unmapped lifetimes')
}
