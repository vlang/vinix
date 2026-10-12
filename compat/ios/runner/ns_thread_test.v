// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math
import time

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_allocateClassPair(voidptr, &char, usize) voidptr
fn C.objc_registerClassPair(voidptr)
fn C.class_addMethod(voidptr, voidptr, voidptr, &char) bool
fn C.class_addIvar(voidptr, &char, usize, u8, &char) bool
type ThreadSend = fn (u64, u64, u64, u64, u64) u64
type ThreadDoubleSend = fn (u64, u64, f64)
struct ThreadApi { native bool send u64 cls u64 strings u64 }
fn (api ThreadApi) message(object u64, name &char, a u64, b u64, c u64) u64 {
	mut selector := u64(name)
	$if macos { if api.native { selector = u64(C.sel_registerName(name)) } }
	return unsafe { ThreadSend(voidptr(api.send))(object, selector, a, b, c) }
}
fn (api ThreadApi) sleep(seconds f64) {
	mut selector := u64(c'sleepForTimeInterval:')
	$if macos { if api.native { selector = u64(C.sel_registerName(c'sleepForTimeInterval:')) } }
	unsafe { ThreadDoubleSend(voidptr(api.send))(api.cls, selector, seconds) }
}
fn (api ThreadApi) pool() u64 {
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api ThreadApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'release', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api ThreadApi) release(object u64) { api.message(object, c'release', 0, 0, 0) }
fn (api ThreadApi) string(value &char) u64 { return api.message(api.strings, c'stringWithUTF8String:', u64(value), 0, 0) }
struct ThreadCapture {
mut:
	api ThreadApi
	copied i64
	disposed i64
	ready i64
	go i64
	expected u64
	main_dictionary u64
	current u64
	dictionary u64
	exit bool
}
struct ThreadDescriptor { reserved u64 size u64 copy u64 dispose u64 }
struct ThreadLiteral { isa u64 flags u32 reserved u32 invoke u64 descriptor u64 capture u64 }
fn thread_load(slot &i64) i64 { return C.ios_ref_change(slot, 0) }
fn thread_wait(slot &i64, count i64) {
	deadline := time.sys_mono_now() + 10 * time.second
	for thread_load(slot) != count { assert time.sys_mono_now() < deadline, 'thread handshake timed out'; time.sleep(time.millisecond) }
}
fn thread_test_copy(dst u64, src u64) {
	cap := unsafe { &ThreadCapture(read64(src + 32)) }
	C.ios_ref_change(unsafe { &cap.copied }, 1)
	unsafe { *(&u64(dst + 32)) = u64(cap) }
}
fn thread_test_dispose(block u64) { cap := unsafe { &ThreadCapture(read64(block + 32)) }; C.ios_ref_change(unsafe { &cap.disposed }, 1) }
fn thread_test_body(block u64) {
	mut cap := unsafe { &ThreadCapture(read64(block + 32)) }
	api := cap.api; pool := api.pool()
	cap.current = api.message(api.cls, c'currentThread', 0, 0, 0)
	assert cap.current == api.message(api.cls, c'currentThread', 0, 0, 0)
	if cap.expected != 0 { assert cap.current == cap.expected }
	assert api.message(api.cls, c'isMainThread', 0, 0, 0) == 0
	assert api.message(cap.current, c'isMainThread', 0, 0, 0) == 0
	assert api.message(cap.current, c'isExecuting', 0, 0, 0) == 1
	cap.dictionary = api.message(cap.current, c'threadDictionary', 0, 0, 0)
	assert cap.dictionary != cap.main_dictionary && cap.dictionary == api.message(cap.current, c'threadDictionary', 0, 0, 0)
	key := api.string(c'ThreadKey'); value := api.string(c'ThreadValue')
	api.message(cap.dictionary, c'setObject:forKey:', value, key, 0)
	assert api.message(cap.dictionary, c'objectForKey:', key, 0, 0) == value
	C.ios_ref_change(unsafe { &cap.ready }, 1)
	if cap.exit { api.message(api.cls, c'exit', 0, 0, 0); assert false }
	thread_wait(unsafe { &cap.go }, 1)
	api.drain(pool)
}
fn thread_finished(api ThreadApi, object u64) {
	deadline := time.sys_mono_now() + 10 * time.second
	for api.message(object, c'isFinished', 0, 0, 0) == 0 { assert time.sys_mono_now() < deadline; time.sleep(time.millisecond) }
	assert api.message(object, c'isExecuting', 0, 0, 0) == 0
}
fn thread_cases(api ThreadApi) {
	pool := api.pool()
	main_object := api.message(api.cls, c'mainThread', 0, 0, 0)
	assert main_object != 0 && main_object == api.message(api.cls, c'currentThread', 0, 0, 0)
	assert api.message(api.cls, c'isMainThread', 0, 0, 0) == 1 && api.message(main_object, c'isMainThread', 0, 0, 0) == 1
	assert api.message(main_object, c'isExecuting', 0, 0, 0) == 1 && api.message(main_object, c'isFinished', 0, 0, 0) == 0
	dictionary := api.message(main_object, c'threadDictionary', 0, 0, 0)
	assert dictionary == api.message(main_object, c'threadDictionary', 0, 0, 0)
	for _ in 0 .. 50 {
		worker_object := api.message(api.cls, c'new', 0, 0, 0)
		assert api.message(worker_object, c'isExecuting', 0, 0, 0) == 0 && api.message(worker_object, c'isFinished', 0, 0, 0) == 0 && api.message(worker_object, c'isCancelled', 0, 0, 0) == 0
		assert api.message(worker_object, c'isMainThread', 0, 0, 0) == 0 && api.message(worker_object, c'name', 0, 0, 0) == 0 && api.message(worker_object, c'stackSize', 0, 0, 0) == 524288
		name := api.string(c'Foundation Worker'); api.message(worker_object, c'setName:', name, 0, 0)
		assert ctext(api.message(api.message(worker_object, c'name', 0, 0, 0), c'UTF8String', 0, 0, 0)) == 'Foundation Worker'
		api.message(worker_object, c'setName:', 0, 0, 0); assert api.message(worker_object, c'name', 0, 0, 0) == 0
		api.message(worker_object, c'setStackSize:', 1048576, 0, 0); assert api.message(worker_object, c'stackSize', 0, 0, 0) == 1048576
		api.message(worker_object, c'cancel', 0, 0, 0); assert api.message(worker_object, c'isCancelled', 0, 0, 0) == 1
		api.release(worker_object)
	}
	descriptor := ThreadDescriptor{0, sizeof(ThreadLiteral), u64(unsafe { voidptr(thread_test_copy) }), u64(unsafe { voidptr(thread_test_dispose) })}
	mut isa := block_isa(0)
	$if macos { if api.native { isa = u64(C.dlsym(unsafe { voidptr(-2) }, c'_NSConcreteStackBlock')) } }
	for scenario in 0 .. 4 {
		if api.native && scenario == 1 {
			// This Mac retains the captured block even after a cancelled-before-
			// start thread is released. Probe that separately, without keeping a
			// callback into stack capture storage in the shared sanitizer fixture.
			idle := api.message(api.cls, c'new', 0, 0, 0)
			api.message(idle, c'cancel', 0, 0, 0); api.message(idle, c'start', 0, 0, 0); thread_finished(api, idle); api.release(idle)
			continue
		}
		println('IOS-THREAD-CASE: native=${api.native} scenario=${scenario}')
		case_pool := api.pool()
		mut cap := unsafe { &ThreadCapture(C.calloc(1, sizeof(ThreadCapture))) }
		cap.api = api; cap.main_dictionary = dictionary; cap.exit = scenario == 2
		literal := ThreadLiteral{isa, u32(1) << 25, 0, u64(unsafe { voidptr(thread_test_body) }), u64(unsafe { &descriptor }), u64(cap)}
		worker_object := if scenario == 3 { u64(0) } else { api.message(api.message(api.cls, c'alloc', 0, 0, 0), c'initWithBlock:', u64(unsafe { &literal }), 0, 0) }
		cap.expected = worker_object
		assert thread_load(unsafe { &cap.copied }) == if scenario == 3 { 0 } else { 1 }
		if scenario == 1 { api.message(worker_object, c'cancel', 0, 0, 0) }
		if scenario == 3 { api.message(api.cls, c'detachNewThreadWithBlock:', u64(unsafe { &literal }), 0, 0) }
		else { api.message(worker_object, c'start', 0, 0, 0) }
		if scenario != 1 {
			thread_wait(unsafe { &cap.ready }, 1)
			if scenario == 0 { api.message(worker_object, c'cancel', 0, 0, 0); assert api.message(worker_object, c'isExecuting', 0, 0, 0) == 1 && api.message(worker_object, c'isCancelled', 0, 0, 0) == 1 }
			C.ios_ref_change(unsafe { &cap.go }, 1)
		}
		if scenario != 3 { thread_finished(api, worker_object) }
		if scenario == 1 { assert thread_load(unsafe { &cap.ready }) == 0 }
		if scenario != 3 { api.release(worker_object) }
		api.drain(case_pool)
		thread_wait(unsafe { &cap.disposed }, 1)
		if !api.native { ns_threads_reap(false) }
		C.free(cap)
	}
	assert api.message(api.cls, c'isMultiThreaded', 0, 0, 0) == 1
	for seconds in [f64(-1), 0, 0.01]! { before := time.sys_mono_now(); api.sleep(seconds); elapsed := time.sys_mono_now() - before; assert elapsed < time.second; if seconds > 0 { assert elapsed > time.millisecond } }
	api.message(api.cls, c'sleepUntilDate:', 0, 0, 0)
	api.drain(pool)
}

fn thread_test_target(object u64, selector &char, argument u64) {
	_ = selector
	mut cap := unsafe { &ThreadCapture(read64(object + 8)) }
	api := cap.api; pool := api.pool()
	cap.current = api.message(api.cls, c'currentThread', 0, 0, 0)
	if cap.expected != 0 { assert cap.current == cap.expected }
	assert ctext(api.message(argument, c'UTF8String', 0, 0, 0)) == 'Retained argument'
	api.drain(pool)
	C.ios_ref_change(unsafe { &cap.ready }, 1)
}

fn thread_target_class(api ThreadApi) u64 {
	$if macos { if api.native {
		cls := C.objc_allocateClassPair(C.objc_getClass(c'NSObject'), c'VinixThreadTargetFixture', 0); assert cls != unsafe { nil }
		assert C.class_addIvar(cls, c'context', 8, 3, c'^v')
		assert C.class_addMethod(cls, C.sel_registerName(c'run:'), unsafe { voidptr(thread_test_target) }, c'v24@0:8@16')
		C.objc_registerClassPair(cls); return u64(cls)
	} }
	cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixThreadTargetFixture', 0)
	assert objc_add_ivar(cls, c'context', 8, 3, c'^v')
	assert objc_add_method(cls, u64(c'run:'), u64(unsafe { voidptr(thread_test_target) }), c'v24@0:8@16')
	objc_register_class(cls); return cls
}

fn thread_target_cases(api ThreadApi) {
	cls := thread_target_class(api)
	for detached in [false, true]! {
		pool := api.pool(); mut cap := unsafe { &ThreadCapture(C.calloc(1, sizeof(ThreadCapture))) }; cap.api = api
		target := api.message(cls, c'new', 0, 0, 0); unsafe { *(&u64(target + 8)) = u64(cap) }
		argument := api.message(api.string(c'Retained argument'), c'retain', 0, 0, 0)
		mut selector := u64(c'run:')
		$if macos { if api.native { selector = u64(C.sel_registerName(c'run:')) } }
		if detached {
			api.message(api.cls, c'detachNewThreadSelector:toTarget:withObject:', selector, target, argument)
			api.release(target); api.release(argument)
			thread_wait(unsafe { &cap.ready }, 1)
			if !api.native { ns_threads_reap(false) }
		} else {
			worker_object := api.message(api.message(api.cls, c'alloc', 0, 0, 0), c'initWithTarget:selector:object:', target, selector, argument)
			cap.expected = worker_object
			api.release(target); api.release(argument)
			api.message(worker_object, c'start', 0, 0, 0)
			thread_finished(api, worker_object); thread_wait(unsafe { &cap.ready }, 1); api.release(worker_object)
			if !api.native { ns_threads_reap(false) }
		}
		api.drain(pool); C.free(cap)
	}
}

fn thread_foreign(api ThreadApi, pointer &ThreadCapture) {
	mut cap := unsafe { pointer }
	pool := api.pool()
	cap.current = api.message(api.message(api.cls, c'currentThread', 0, 0, 0), c'retain', 0, 0, 0)
	assert api.message(api.cls, c'mainThread', 0, 0, 0) != cap.current
	assert api.message(cap.current, c'isExecuting', 0, 0, 0) == 1
	cap.dictionary = api.message(cap.current, c'threadDictionary', 0, 0, 0)
	C.ios_ref_change(unsafe { &cap.ready }, 1); thread_wait(unsafe { &cap.go }, 1); api.drain(pool)
}

fn thread_foreign_cases(api ThreadApi) {
	a := unsafe { &ThreadCapture(C.calloc(1, sizeof(ThreadCapture))) }; b := unsafe { &ThreadCapture(C.calloc(1, sizeof(ThreadCapture))) }
	first := spawn thread_foreign(api, a); second := spawn thread_foreign(api, b)
	thread_wait(unsafe { &a.ready }, 1); thread_wait(unsafe { &b.ready }, 1)
	assert a.current != b.current && a.dictionary != b.dictionary
	C.ios_ref_change(unsafe { &a.go }, 1); C.ios_ref_change(unsafe { &b.go }, 1); first.wait(); second.wait()
	assert api.message(a.current, c'isFinished', 0, 0, 0) == 1 && api.message(b.current, c'isFinished', 0, 0, 0) == 1
	api.release(a.current); api.release(b.current); C.free(a); C.free(b)
}
fn thread_runtime_api() ThreadApi { return ThreadApi{send: u64(unsafe { voidptr(C.ios_objc_builtin) }), cls: ios_runtime.names['NSThread'], strings: ios_runtime.names['NSString']} }
fn test_thread_native_reference() {
	$if macos {
		objc_start()
		api := ThreadApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), cls: u64(C.objc_getClass(c'NSThread')), strings: u64(C.objc_getClass(c'NSString'))}
		thread_cases(api); thread_target_cases(api); thread_foreign_cases(api); assert ios_runtime.live == 0; objc_stop()
		println('IOS-THREAD-NATIVE: stable identities/dictionaries, defaults, names, stack size, block copy/disposal, cooperative and pre-start cancellation, detach, explicit exit and sleeps passed')
	}
}
fn test_thread_runtime_storage_and_shutdown() {
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!; api := thread_runtime_api()
		assert objc_class_size(api.cls) == 64 && objc_class_parent(api.cls) == ios_runtime.names['NSObject']
		assert objc_ivar_offset(objc_find_ivar(api.cls, c'_private')) == 8 && objc_ivar_offset(objc_find_ivar(api.cls, c'_bytes')) == 16
		assert ctext(u64(objc_method_types(objc_instance_method(api.cls, u64(c'initWithBlock:'))))) == '@24@0:8@?16'
		assert runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', '_OBJC_CLASS_$_NSThread') or { panic(err) } == api.cls
		thread_cases(api)
		thread_target_cases(api); thread_foreign_cases(api)
		for _ in 0 .. 100 { object := objc_new(api.cls); api.message(object, c'setName:', objc_autorelease(owned_string('owned')), 0, 0); api.message(object, c'threadDictionary', 0, 0, 0); objc_set_class(object, ios_runtime.names['NSObject']); objc_release(object) }
		storage := u64(C.calloc(1, 64)); assert objc_construct_instance(api.cls, storage) == storage
		api.message(storage, c'init', 0, 0, 0); assert objc_destruct_instance(storage) == storage; C.free(unsafe { voidptr(storage) })
		objc_stop(); assert ios_runtime.live == 0 && ios_runtime.block_refs.len == 0 && ios_runtime.foundation_worker_count == 0 && ios_runtime.foundation_thread_count == 0
		system_data_stop()
	}
	println('IOS-THREAD: shared native cases, measured metadata, TLS exit cleanup, native worker joins, isa-independent state, caller storage and two clean runtime cycles passed')
}
fn test_thread_profile_rejections() {
	for mode in ['restart', 'stack-small', 'stack-active', 'nil-block', 'qos', 'sleep-nan', 'uninitialized']! {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := darwin_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			objc_start(); system_data_start() or { panic(err) }; api := thread_runtime_api(); object := objc_new(api.cls)
			match mode {
				'restart' { api.message(object, c'cancel', 0, 0, 0); api.message(object, c'start', 0, 0, 0); thread_finished(api, object); api.message(object, c'start', 0, 0, 0) }
				'stack-small' { api.message(object, c'setStackSize:', 4096, 0, 0) }
				'stack-active' { api.message(api.message(api.cls, c'currentThread', 0, 0, 0), c'setStackSize:', 524288, 0, 0) }
				'nil-block' { api.message(objc_allocate(api.cls), c'initWithBlock:', 0, 0, 0) }
				'qos' { api.message(object, c'setQualityOfService:', 33, 0, 0) }
				'sleep-nan' { api.sleep(math.nan()) }
				else { api.message(objc_allocate(api.cls), c'start', 0, 0, 0) }
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert darwin_waitpid(pid, unsafe { &status }, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }; expected := match mode {
			'restart', 'uninitialized' { 'thread cannot be started' }
			'stack-small', 'stack-active' { 'Foundation stack requires an unstarted thread' }
			'nil-block' { 'nil Foundation thread block' }
			'qos' { 'thread scheduling, run loops and stack introspection are outside the implemented profile' }
			else { 'thread sleep is outside the finite one-day profile' }
		}
		assert output.contains(expected), output
		assert !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output
	}
	println('IOS-THREAD-REJECT: restart, invalid/active stack, nil block, unsupported QoS, nonfinite sleep and uninitialized start rejected')
}
