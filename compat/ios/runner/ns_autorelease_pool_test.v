// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.objc_allocateClassPair(voidptr, &char, usize) voidptr
fn C.objc_registerClassPair(voidptr)
fn C.class_addMethod(voidptr, voidptr, voidptr, &char) bool
fn C.object_dispose(voidptr) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
type PoolSend = fn (u64, u64, u64) u64
type PoolPush = fn () u64
type PoolPop = fn (u64)
struct PoolApi { native bool send u64 cls u64 probe u64 push u64 pop u64 }
__global pool_destroyed = i64(0)
__global pool_reentrant = i64(0)
__global native_pool_probe = u64(0)
__global runtime_pool_probe = u64(0)
__global pool_rejection_target = u64(0)
fn (api PoolApi) message(object u64, name &char, argument u64) u64 {
	mut selector := u64(name)
	$if macos { if api.native { selector = u64(C.sel_registerName(name)) } }
	return unsafe { PoolSend(voidptr(api.send))(object, selector, argument) }
}
fn (api PoolApi) scope() u64 { return unsafe { PoolPush(voidptr(api.push))() } }
fn (api PoolApi) pop(token u64) { unsafe { PoolPop(voidptr(api.pop))(token) } }
fn (api PoolApi) object() u64 { return api.message(api.probe, c'new', 0) }
fn (api PoolApi) pool() u64 { return api.message(api.cls, c'new', 0) }
fn pool_count() i64 { return C.ios_ref_change(unsafe { &pool_destroyed }, 0) }
fn native_pool_dealloc(object u64, selector u64) {
	$if macos {
		C.ios_ref_change(unsafe { &pool_destroyed }, 1)
		if C.ios_ref_change(unsafe { &pool_reentrant }, 0) > 0 {
			C.ios_ref_change(unsafe { &pool_reentrant }, -1)
			api := PoolApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), probe: native_pool_probe}
			api.message(api.object(), c'autorelease', 0)
		}
		C.object_dispose(unsafe { voidptr(object) })
	}
}
fn runtime_pool_dealloc(object u64, selector &char) {
	C.ios_ref_change(unsafe { &pool_destroyed }, 1)
	if pool_rejection_target != 0 { ns_pool_release(pool_rejection_target) }
	if C.ios_ref_change(unsafe { &pool_reentrant }, 0) > 0 {
		C.ios_ref_change(unsafe { &pool_reentrant }, -1)
		objc_autorelease(objc_new(runtime_pool_probe))
	}
}
fn pool_runtime_api() PoolApi {
	probe := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixPoolRuntimeProbe', 0)
	assert probe != 0;
	assert objc_add_method(probe, u64(c'dealloc'), u64(unsafe { voidptr(runtime_pool_dealloc) }), c'v16@0:8');
	objc_register_class(probe); runtime_pool_probe = probe
	return PoolApi{send: u64(unsafe { voidptr(C.ios_objc_msgsend) }), cls: ios_runtime.names['NSAutoreleasePool'], probe: probe, push: u64(unsafe { voidptr(objc_pool_push) }), pop: u64(unsafe { voidptr(objc_pool_pop) })}
}

fn pool_shared_cases(api PoolApi) {
	start := pool_count()
	pool := api.pool(); assert api.message(pool, c'retainCount', 0) == 1;
	api.message(api.object(), c'autorelease', 0)
	api.message(pool, c'addObject:', api.object()); api.message(api.cls, c'addObject:', api.object())
	assert pool_count() == start;
	api.message(pool, c'drain', 0); assert pool_count() == start + 3;
	outer := api.pool(); api.message(api.object(), c'autorelease', 0)
	inner := api.pool(); api.message(outer, c'addObject:', api.object())
	api.message(inner, c'release', 0); assert pool_count() == start + 4;
	api.message(outer, c'drain', 0); assert pool_count() == start + 5;
	capacity := api.message(api.message(api.cls, c'alloc', 0), c'initWithCapacity:', 128)
	api.message(capacity, c'addObject:', api.object()); api.message(capacity, c'release', 0)
	assert pool_count() == start + 6;
	a := api.pool(); api.message(api.object(), c'autorelease', 0)
	api.pool(); api.message(api.object(), c'autorelease', 0)
	api.scope(); api.message(api.object(), c'autorelease', 0)
	api.message(a, c'drain', 0); assert pool_count() == start + 9;
	root := api.scope(); api.pool(); api.message(api.object(), c'autorelease', 0)
	api.pop(root); assert pool_count() == start + 10;
	b := api.pool(); nested := api.scope(); api.message(api.object(), c'autorelease', 0)
	api.pop(nested); assert pool_count() == start + 11;
	api.message(api.object(), c'autorelease', 0); api.message(b, c'release', 0)
	assert pool_count() == start + 12;
	c := api.pool(); pool_reentrant = 3; api.message(api.object(), c'autorelease', 0)
	api.message(c, c'drain', 0); assert pool_count() == start + 16 && pool_reentrant == 0;
	for _ in 0 .. 250 { x := api.scope(); y := api.scope(); assert x != y; api.pop(y); api.pop(x) }
}

fn pool_worker(api PoolApi, abandon bool) {
	for _ in 0 .. if abandon { 1 } else { 100 } {
		pool := api.pool(); api.message(api.object(), c'autorelease', 0)
		if !abandon { api.message(pool, c'drain', 0) }
	}
}
fn pool_thread_cases(api PoolApi) {
	start := pool_count(); mut workers := []thread{}
	for _ in 0 .. 4 { workers << spawn pool_worker(api, false) }
	workers.wait(); assert pool_count() == start + 400;
	mut abandoned := []thread{}
	for _ in 0 .. 4 { abandoned << spawn pool_worker(api, true) }
	abandoned.wait(); assert pool_count() == start + 404;
}
fn test_autorelease_pool_native() {
	$if macos {
		probe := C.objc_allocateClassPair(C.objc_getClass(c'NSObject'), c'VinixPoolNativeProbe', 0)
		assert probe != unsafe { nil };
		assert C.class_addMethod(probe, C.sel_registerName(c'dealloc'), unsafe { voidptr(native_pool_dealloc) }, c'v16@0:8');
		C.objc_registerClassPair(probe); native_pool_probe = u64(probe)
		api := PoolApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), cls: u64(C.objc_getClass(c'NSAutoreleasePool')), probe: u64(probe), push: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_autoreleasePoolPush')), pop: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_autoreleasePoolPop'))}
		pool_shared_cases(api); pool_thread_cases(api)
		println('IOS-AUTOPOOL-NATIVE: drain/release, current-pool routing, capacity hints, nested C/class scopes, destructor autoreleases,500 empty boundaries and404 threaded object retirements')
	}
}
fn test_autorelease_pool_runtime() {
	assert objc_retain(0) == 0 && objc_autorelease(0) == 0;
	for _ in 0 .. 2 {
		objc_start(); api := pool_runtime_api()
		library := '/System/Library/Frameworks/Foundation.framework/Foundation'
		assert runtime_symbol(library, '_OBJC_CLASS_$_NSAutoreleasePool')! == api.cls;
		assert runtime_symbol(library, '_OBJC_METACLASS_$_NSAutoreleasePool')! == read64(api.cls);
		assert objc_class_size(api.cls) == 40;
		pool_shared_cases(api); pool_thread_cases(api)
		assert ios_runtime.live == 0;
		for _ in 0 .. 100 {
			pool := api.pool(); api.message(api.object(), c'autorelease', 0)
			mut weak := u64(0); objc_store_weak(unsafe { &weak }, pool)
			objc_set_class(pool, ios_runtime.names['NSObject']); objc_release(pool)
			assert weak == 0; objc_destroy_weak(unsafe { &weak })
		}
		mut storage := [40]u8{}
		caller := objc_construct_instance(api.cls, u64(unsafe { &storage[0] }))
		assert objc_destruct_instance(caller) == caller;
		uninitialized := api.message(api.cls, c'alloc', 0); api.message(uninitialized, c'release', 0)
		api.pool(); api.message(api.object(), c'autorelease', 0)
		objc_stop(); assert ios_runtime.live == 0 && ios_runtime.block_refs.len == 0;
	}
	println('IOS-AUTOPOOL: shared lifetimes, unique boundaries, thread exit cleanup,100 isa changes, uninitialized caller storage and two zero-live-object shutdowns')
}

fn pool_foreign_token(token u64) { objc_pool_pop(token) }
fn pool_foreign_object(object u64) { ns_pool_release(object) }
fn test_autorelease_pool_rejections() {
	objc_start(); api := pool_runtime_api()
	for mode in ['retain', 'autorelease', 'copy', 'reinitialize', 'uninitialized-drain', 'caller-init', 'subclass', 'active-destruct', 'foreign-token', 'foreign-object', 'reentrant-drain', 'weak-load', 'nil-add']! {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0;
		pid := C.fork(); assert pid >= 0;
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			if mode == 'caller-init' { mut storage := [40]u8{}; object := objc_construct_instance(api.cls, u64(unsafe { &storage[0] })); ns_pool_initialize(object) }
			if mode == 'subclass' { sub := objc_allocate_class(api.cls, c'UnsupportedPoolSubclass', 0); objc_register_class(sub); objc_new(sub) }
			object := if mode == 'uninitialized-drain' { objc_allocate(api.cls) } else { api.pool() }
			match mode {
				'retain' { objc_retain(object) }
				'autorelease' { objc_autorelease(object) }
				'weak-load' { mut weak := u64(0); objc_store_weak(unsafe { &weak }, object); objc_load_weak(unsafe { &weak }) }
				'nil-add' { api.message(api.cls, c'addObject:', 0) }
				'copy' { api.message(object, c'copy', 0) }
				'reinitialize' { api.message(object, c'init', 0) }
				'uninitialized-drain' { api.message(object, c'drain', 0) }
				'active-destruct' { objc_destruct_instance(object) }
				'foreign-token' { t := spawn pool_foreign_token(objc_pool_push()); t.wait() }
				'foreign-object' { t := spawn pool_foreign_object(object); t.wait() }
				'reentrant-drain' { pool_rejection_target = object; api.message(api.object(), c'autorelease', 0); api.message(object, c'drain', 0) }
				else {}
			}
			C._exit(0)
		}
		C.close(fds[1]); mut buffer := [16384]u8{}; mut length := 0
		for { assert length < buffer.len; count := C.read(fds[0], unsafe { &buffer[length] }, usize(buffer.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256;
		output := unsafe { tos(&buffer[0], length) }
		reason := match mode { 'retain', 'autorelease', 'weak-load' { 'autorelease pools cannot be retained or autoreleased' } 'copy' { 'autorelease pool copies are not implemented' } 'reinitialize' { 'autorelease pool reinitialization is not implemented' } 'uninitialized-drain' { 'autorelease pool drainage requires initialization' } 'caller-init' { 'autorelease pool initialization cannot consume caller-owned storage' } 'subclass' { 'autorelease pool subclass construction is not implemented' } 'active-destruct' { 'active autorelease pool storage must be drained before destruction' } 'foreign-token' { 'invalid or foreign autorelease pool token' } 'foreign-object' { 'autorelease pool drainage requires its owner thread' } 'nil-add' { 'autorelease pool addObject must not be nil' } else { 'reentrant autorelease pool drainage is not implemented' } }
		assert output.contains('iOS: ' + reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output;
	}
	assert ios_runtime.live == 0; objc_stop()
	println('IOS-AUTOPOOL-REJECT: thirteen ownership/copy/reinit/storage/subclass/thread/reentrant/weak-load/nil-add cases fail explicitly')
}
