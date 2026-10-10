// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_getClass(&char) voidptr
fn C.class_createInstance(voidptr, usize) voidptr
fn C.sel_registerName(&char) voidptr
fn C.objc_storeWeak(&voidptr, voidptr) voidptr

type SyncCall = fn (u64) i32
type SyncRelease = fn (u64)
type SyncSend = fn (u64, u64) u64
type SyncBlockCopy = fn (u64) u64

struct SyncApi {
	native bool
	root u64
	@[required]
	enter_sync SyncCall
	@[required]
	exit_sync SyncCall
	@[required]
	release SyncRelease
}
struct SyncState {
mut:
	stage i64
	other_done i64
	value u64
	check u64 = ~u64(0)
}
fn (api SyncApi) create() u64 {
	$if macos { if api.native { return u64(C.class_createInstance(voidptr(api.root), 0)) } }
	return objc_allocate(api.root)
}
fn (api SyncApi) refs(object u64) i64 {
	$if macos {
		if api.native {
			lib := C.dlopen('/usr/lib/libobjc.A.dylib'.str, C.RTLD_NOW)
			send := unsafe { SyncSend(C.dlsym(lib, c'objc_msgSend')) }
			return i64(send(object, u64(C.sel_registerName(c'retainCount'))))
		}
	}
	return C.ios_ref_change(unsafe { &obj_header(object).refs }, 0)
}
fn (api SyncApi) weak(slot &u64, object u64) {
	$if macos { if api.native { C.objc_storeWeak(unsafe { &voidptr(slot) }, voidptr(object)); return } }
	objc_store_weak(slot, object)
}
fn (api SyncApi) clear_weak(slot &u64) {
	$if macos { if api.native { C.objc_storeWeak(unsafe { &voidptr(slot) }, unsafe { nil }); return } }
	objc_destroy_weak(slot)
}
fn sync_wait(slot &i64, value i64) {
	deadline := time.sys_mono_now() + 30 * time.second
	for C.ios_ref_change(slot, 0) != value {
		assert time.sys_mono_now() < deadline, 'object monitor handshake timed out'
		time.sleep(time.millisecond)
	}
}
fn sync_foreign_exit(api SyncApi, object u64) i32 { return api.exit_sync(object) }
fn sync_test_lifetime(api SyncApi) {
	assert api.enter_sync(0) == 0 && api.exit_sync(0) == 0
	for _ in 0 .. 500 {
		object := api.create()
		assert api.exit_sync(object) == -1
		mut weak := u64(0)
		api.weak(unsafe { &weak }, object)
		for _ in 0 .. 64 { assert api.enter_sync(object) == 0 }
		assert api.refs(object) == 1
		if !api.native {
			assert ios_runtime.monitors.len == 1
			monitor := ios_runtime.monitors[object] or { panic('missing object monitor') }
			assert monitor.entries == 64
		}
		api.release(object)
		assert weak == 0 // A held monitor neither retains nor reads its identity.
		for _ in 0 .. 64 { assert api.exit_sync(object) == 0 }
		assert api.exit_sync(object) == -1
		api.clear_weak(unsafe { &weak })
		if !api.native { assert ios_runtime.monitors.len == 0 }
	}
	for identity in [api.root, u64(1), u64(0x123456789abcdef0)]! {
		assert api.exit_sync(identity) == -1
		assert api.enter_sync(identity) == 0 && api.enter_sync(identity) == 0
		foreign := spawn sync_foreign_exit(api, identity)
		assert foreign.wait() == -1
		assert api.exit_sync(identity) == 0 && api.exit_sync(identity) == 0
		assert api.exit_sync(identity) == -1
	}
	mut descriptor := [u64(0), 32]!
	mut isa := u64(0)
	$if macos { if api.native { isa = u64(C.dlsym(C.dlopen('/usr/lib/libSystem.B.dylib'.str, C.RTLD_NOW), c'_NSConcreteStackBlock')) } }
	if !api.native { isa = block_isa(0) }
	mut literal := [isa, u64(0), u64(unsafe { voidptr(sync_block_invoke) }), u64(unsafe { &descriptor[0] })]!
	mut copied := u64(0)
	$if macos {
		if api.native {
			copy_block := unsafe { SyncBlockCopy(C.dlsym(C.dlopen('/usr/lib/libSystem.B.dylib'.str, C.RTLD_NOW), c'_Block_copy')) }
			copied = copy_block(u64(unsafe { &literal[0] }))
		}
	}
	if !api.native { copied = block_copy(u64(unsafe { &literal[0] })) }
	assert copied != 0 && copied != u64(unsafe { &literal[0] })
	assert api.enter_sync(copied) == 0
	api.release(copied)
	assert api.exit_sync(copied) == 0 && api.exit_sync(copied) == -1
}
fn sync_block_invoke(block u64) { _ = block }
fn sync_waiter(api SyncApi, object u64, state &SyncState) {
	assert api.exit_sync(object) == -1
	C.ios_ref_change(unsafe { &state.stage }, 1)
	assert api.enter_sync(object) == 0
	assert api.enter_sync(object) == 0 && api.enter_sync(object) == 0
	unsafe { state.value = 1 }
	for _ in 0 .. 3 { assert api.exit_sync(object) == 0 }
	assert api.exit_sync(object) == -1
	C.ios_ref_change(unsafe { &state.stage }, 1)
}
fn sync_independent(api SyncApi, other u64, state &SyncState) {
	assert api.enter_sync(other) == 0 && api.enter_sync(0) == 0
	assert api.exit_sync(0) == 0 && api.exit_sync(other) == 0
	// Registry-backed object creation must also progress while another waits.
	object := api.create(); api.release(object)
	C.ios_ref_change(unsafe { &state.other_done }, 1)
}
fn sync_test_handoff(api SyncApi) {
	for _ in 0 .. 50 {
		object := api.create()
		other := api.create()
		state := &SyncState{}
		assert api.enter_sync(object) == 0 && api.enter_sync(object) == 0
		waiter := spawn sync_waiter(api, object, state)
		sync_wait(unsafe { &state.stage }, 1)
		if !api.native {
			deadline := time.sys_mono_now() + 30 * time.second
			for {
				C.ios_objc_initialize_lock()
				monitor := ios_runtime.monitors[object] or { panic('missing pinned monitor') }
				pinned := monitor.entries == 3
				C.ios_objc_initialize_unlock()
				if pinned { break }
				assert time.sys_mono_now() < deadline
				time.sleep(time.millisecond)
			}
		}
		independent := spawn sync_independent(api, other, state)
		sync_wait(unsafe { &state.other_done }, 1)
		independent.wait()
		assert C.ios_ref_change(unsafe { &state.stage }, 0) == 1 && state.value == 0
		assert api.exit_sync(object) == 0
		assert C.ios_ref_change(unsafe { &state.stage }, 0) == 1 && state.value == 0
		assert api.exit_sync(object) == 0
		sync_wait(unsafe { &state.stage }, 2)
		waiter.wait()
		assert state.value == 1
		api.release(other); api.release(object); C.free(state)
		if !api.native { assert ios_runtime.monitors.len == 0 }
	}
}
fn sync_shared_worker(api SyncApi, object u64, state &SyncState) {
	for i in 0 .. 2000 {
		assert api.enter_sync(object) == 0
		if i % 8 == 0 { assert api.enter_sync(object) == 0 }
		assert state.check == ~state.value
		unsafe { state.value++; state.check = ~state.value }
		if i % 8 == 0 { assert api.exit_sync(object) == 0 }
		assert api.exit_sync(object) == 0
	}
}
fn sync_exit_observer(api SyncApi, object u64) {
	for _ in 0 .. 16000 { assert api.exit_sync(object) == -1 }
}
fn sync_run(api SyncApi) {
	sync_test_lifetime(api)
	sync_test_handoff(api)
	object := api.create()
	state := &SyncState{}
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn sync_shared_worker(api, object, state) }
	observer := spawn sync_exit_observer(api, object)
	workers.wait(); observer.wait()
	assert state.value == 16000 && state.check == ~state.value
	api.release(object); C.free(state)
}
fn test_object_monitors_match_native_runtime() {
	$if macos {
		lib := C.dlopen('/usr/lib/libobjc.A.dylib'.str, C.RTLD_NOW)
		sync_run(SyncApi{
			native: true, root: u64(C.objc_getClass(c'NSObject'))
			enter_sync: unsafe { SyncCall(C.dlsym(lib, c'objc_sync_enter')) }
			exit_sync: unsafe { SyncCall(C.dlsym(lib, c'objc_sync_exit')) }
			release: unsafe { SyncRelease(C.dlsym(lib, c'objc_release')) }
		})
		println('IOS-SYNC-NATIVE: nil, recursion, foreign/unmatched errors, non-retaining opaque identities, released instances/blocks, independent monitors, waiter handoff and eight shared-counter workers')
	}
	for _ in 0 .. 2 {
		objc_start()
		sync_run(SyncApi{
			root: ios_runtime.names['NSObject']
			enter_sync: unsafe { SyncCall(voidptr(runtime_symbol('/usr/lib/libobjc.A.dylib', '_objc_sync_enter') or { panic(err) })) }
			exit_sync: unsafe { SyncCall(voidptr(runtime_symbol('/usr/lib/libobjc.A.dylib', '_objc_sync_exit') or { panic(err) })) }
			release: objc_release
		})
		assert ios_runtime.monitors.len == 0 && ios_runtime.objects.len == 0 && ios_runtime.live == 0 && ios_runtime.block_refs.len == 0
		objc_stop()
		assert ios_runtime.monitors.len == 0 && ios_runtime.objects.len == 0 && ios_runtime.live == 0
	}
	println('IOS-SYNC: native i32 ABI and ownership contract, recursive exclusion, pinned handoff, independent identity/registry progress, concurrent foreign exits and two empty runtime teardowns')
}
