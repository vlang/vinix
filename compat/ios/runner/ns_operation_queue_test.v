// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

$if macos {
	#flag -framework Foundation
	#flag -framework CoreFoundation
	#include <objc/runtime.h>
	#define dispatch_sync vinix_native_header_dispatch_sync
	#include <CoreFoundation/CFRunLoop.h>
	#undef dispatch_sync
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.__atomic_fetch_add(&u64, u64, int) u64
fn C.__atomic_load_n(&u64, int) u64
fn C.__atomic_store_n(&u64, u64, int)
fn C.CFRunLoopRunInMode(voidptr, f64, bool) i32
type QueueSend = fn (u64, u64, u64) u64
type QueueDispatchCreate = fn (&char, u64, u64) u64
type QueueDispatchAsync = fn (u64, voidptr, DispatchFunction)
type QueueDispatchRelease = fn (u64)
struct QueueApi { native bool send u64 }
fn (a QueueApi) cls(name &char) u64 {
	$if macos { if a.native { return u64(C.objc_getClass(name)) } }
	return ios_runtime.names[ctext(u64(name))]
}
fn (a QueueApi) msg(object u64, name &char, value u64) u64 {
	mut selector := u64(name)
	$if macos { if a.native { selector = u64(C.sel_registerName(name)) } }
	return unsafe { QueueSend(voidptr(a.send))(object, selector, value) }
}
fn (a QueueApi) pump() {
	$if macos { if a.native {
		cell := C.dlsym(unsafe { voidptr(-2) }, c'kCFRunLoopDefaultMode')
		C.CFRunLoopRunInMode(unsafe { voidptr(*(&u64(cell))) }, 0.001, false)
		return
	} }
	dispatch_main_drain()
}
struct QueueBlockDescriptor { reserved u64 size u64 copy u64 dispose u64 }
struct QueueBlock { isa u64 flags u32 reserved u32 invoke u64 descriptor u64 capture u64 }
struct QueueProbe {
	api QueueApi
	owner u64
	thread u64
	check_disposal bool
	main bool
mut:
	copies u64
	drops u64
	calls u64
	active u64
	failure u64
	entered u64
	gate u64
}
fn queue_probe_copy(destination u64, source u64) {
	write64(destination + 32, read64(source + 32))
	probe := unsafe { &QueueProbe(read64(source + 32)) }
	C.__atomic_fetch_add(unsafe { &probe.copies }, 1, 5)
}
fn queue_probe_drop(block u64) {
	probe := unsafe { &QueueProbe(read64(block + 32)) }
	if probe.check_disposal {
		if probe.api.msg(probe.owner, c'operationCount', 0) == 0 { C.__atomic_store_n(unsafe { &probe.failure }, 1, 5) }
		if probe.main && probe.api.msg(probe.api.cls(c'NSOperationQueue'), c'mainQueue', 0) != probe.owner { C.__atomic_store_n(unsafe { &probe.failure }, 7, 5) }
	}
	C.__atomic_fetch_add(unsafe { &probe.drops }, 1, 5)
}
fn queue_probe_call(block u64) {
	probe := unsafe { &QueueProbe(read64(block + 32)) }
	if C.__atomic_fetch_add(unsafe { &probe.active }, 1, 5) != 0 { C.__atomic_store_n(unsafe { &probe.failure }, 3, 5) }
	current := probe.api.msg(probe.api.cls(c'NSOperationQueue'), c'currentQueue', 0)
	on_main := u64(C.pthread_self()) == probe.thread
	if current != probe.owner || on_main != probe.main { C.__atomic_store_n(unsafe { &probe.failure }, 4, 5) }
	C.__atomic_store_n(unsafe { &probe.entered }, 1, 5)
	for C.__atomic_load_n(unsafe { &probe.gate }, 5) != 0 { time.sleep(time.millisecond) }
	C.__atomic_fetch_add(unsafe { &probe.calls }, 1, 5)
	C.__atomic_fetch_add(unsafe { &probe.active }, ~u64(0), 5)
}
fn queue_probe_wait(value &u64, expected u64) {
	deadline := time.sys_mono_now() + 5 * time.second
	for C.__atomic_load_n(value, 5) != expected {
		assert time.sys_mono_now() < deadline;
		time.sleep(time.millisecond)
	}
}
fn queue_probe_watchdog(done &u64) {
	deadline := time.sys_mono_now() + 30 * time.second
	for C.__atomic_load_n(done, 5) == 0 {
		if time.sys_mono_now() >= deadline { eprintln('IOS-OPERATION-QUEUE: FAIL callback/wait deadlock'); C._exit(124) }
		time.sleep(10 * time.millisecond)
	}
}
fn queue_probe_submit(a QueueApi, probe &QueueProbe, count int) {
	descriptor := QueueBlockDescriptor{0, sizeof(QueueBlock), u64(unsafe { voidptr(queue_probe_copy) }), u64(unsafe { voidptr(queue_probe_drop) })}
	mut isa := u64(0)
	$if macos { if a.native { isa = u64(C.dlsym(unsafe { voidptr(-2) }, c'_NSConcreteStackBlock')) } }
	if !a.native { isa = block_isa(0) }
	block := QueueBlock{isa, u32(1) << 25, 0, u64(unsafe { voidptr(queue_probe_call) }), u64(unsafe { &descriptor }), u64(probe)}
	pool := if a.native { a.msg(a.cls(c'NSAutoreleasePool'), c'new', 0) } else { u64(0) }
	// Descriptors must outlive every promoted block. Wait before returning.
	for _ in 0 .. count { a.msg(probe.owner, c'addOperationWithBlock:', u64(unsafe { &block })) }
	assert a.msg(probe.owner, c'operationCount', 0) == u64(count);
	a.msg(probe.owner, c'setSuspended:', 0)
	a.msg(probe.owner, c'waitUntilAllOperationsAreFinished', 0)
	// Native autoreleased NSBlockOperations can own the captures until the
	// submitting thread's pool drains, even after the queue reports finished.
	if pool != 0 { a.msg(pool, c'drain', 0) }
	queue_probe_wait(unsafe { &probe.drops }, u64(count))
}
fn queue_shared(a QueueApi) {
	mut done := u64(0)
	watchdog := spawn queue_probe_watchdog(unsafe { &done })
	defer { C.__atomic_store_n(unsafe { &done }, 1, 5); watchdog.wait() }
	queue := a.msg(a.cls(c'NSOperationQueue'), c'new', 0)
	a.msg(queue, c'setMaxConcurrentOperationCount:', 1)
	a.msg(queue, c'setSuspended:', 1)
	a.msg(queue, c'setSuspended:', 1) // Idempotent, not a dispatch suspension count.
	assert a.msg(queue, c'isSuspended', 0) == 1 && a.msg(queue, c'operationCount', 0) == 0;
	mut probe := QueueProbe{api: a, owner: queue, thread: u64(C.pthread_self()), check_disposal: !a.native}
	queue_probe_submit(a, unsafe { &probe }, 64)
	assert probe.copies == 64 && probe.drops == 64 && probe.calls == 64 && probe.active == 0 && probe.failure == 0, 'native=${a.native} copies=${probe.copies} drops=${probe.drops} calls=${probe.calls} failure=${probe.failure}';
	assert a.msg(queue, c'operationCount', 0) == 0 && a.msg(queue, c'isSuspended', 0) == 0;
	a.msg(queue, c'release', 0)
}

fn queue_main_lookup(a QueueApi) u64 {
	pool := if a.native { a.msg(a.cls(c'NSAutoreleasePool'), c'new', 0) } else { objc_pool_push() }
	assert a.msg(a.cls(c'NSOperationQueue'), c'currentQueue', 0) == 0;
	queue := a.msg(a.cls(c'NSOperationQueue'), c'mainQueue', 0)
	assert queue != 0;
	a.msg(queue, c'retain', 0); a.msg(queue, c'release', 0)
	if a.native { a.msg(pool, c'drain', 0) } else { objc_pool_pop(pool) }
	return queue
}

fn queue_main_submit(a QueueApi, queue u64, block u64) {
	pool := if a.native { a.msg(a.cls(c'NSAutoreleasePool'), c'new', 0) } else { objc_pool_push() }
	for _ in 0 .. 32 { a.msg(queue, c'addOperationWithBlock:', block) }
	if a.native { a.msg(pool, c'drain', 0) } else { objc_pool_pop(pool) }
}

fn queue_main_shared(a QueueApi) u64 {
	// Race the very first runtime publication from foreign threads. The cache
	// owns exactly one instance; no worker lookup may change main-thread identity.
	mut lookups := []thread u64{}
	for _ in 0 .. 8 { lookups << spawn queue_main_lookup(a) }
	identities := lookups.wait()
	queue := a.msg(a.cls(c'NSOperationQueue'), c'mainQueue', 0)
	for identity in identities { assert identity == queue; }
	unsafe { lookups.free(); identities.free() }
	assert a.msg(a.cls(c'NSOperationQueue'), c'currentQueue', 0) == queue;
	assert a.msg(queue, c'maxConcurrentOperationCount', 0) == 1;
	for count in [u64(2), ~u64(0), u64(0), u64(1)]! {
		a.msg(queue, c'setMaxConcurrentOperationCount:', count)
		assert a.msg(queue, c'maxConcurrentOperationCount', 0) == 1;
	}
	a.msg(queue, c'setSuspended:', 1)
	assert a.msg(queue, c'isSuspended', 0) == 0;
	a.msg(queue, c'setSuspended:', 0)
	name := a.msg(queue, c'name', 0)
	if a.native {
		assert ctext(a.msg(name, c'UTF8String', 0)) == 'NSOperationQueue Main Queue';
	} else { assert string_text(name) == 'NSOperationQueue Main Queue'; }
	mut probe := QueueProbe{api: a, owner: queue, thread: u64(C.pthread_self()), main: true, check_disposal: !a.native}
	descriptor := QueueBlockDescriptor{0, sizeof(QueueBlock), u64(unsafe { voidptr(queue_probe_copy) }), u64(unsafe { voidptr(queue_probe_drop) })}
	mut isa := u64(0)
	$if macos { if a.native { isa = u64(C.dlsym(unsafe { voidptr(-2) }, c'_NSConcreteStackBlock')) } }
	if !a.native { isa = block_isa(0) }
	block := QueueBlock{isa, u32(1) << 25, 0, u64(unsafe { voidptr(queue_probe_call) }), u64(unsafe { &descriptor }), u64(unsafe { &probe })}
	pool := if a.native { a.msg(a.cls(c'NSAutoreleasePool'), c'new', 0) } else { objc_pool_push() }
	submitter := spawn queue_main_submit(a, queue, u64(unsafe { &block }))
	submitter.wait()
	// Workers have time to run, but main work must remain queued until pumped.
	time.sleep(20 * time.millisecond)
	assert probe.calls == 0 && a.msg(queue, c'operationCount', 0) == 32;
	deadline := time.sys_mono_now() + 5 * time.second
	for a.msg(queue, c'operationCount', 0) != 0 {
		assert time.sys_mono_now() < deadline;
		a.pump()
	}
	a.msg(queue, c'waitUntilAllOperationsAreFinished', 0) // Empty main queue cannot deadlock.
	if a.native { a.msg(pool, c'drain', 0) } else { objc_pool_pop(pool) }
	queue_probe_wait(unsafe { &probe.drops }, 32)
	assert probe.calls == 32 && probe.copies == 32 && probe.drops == 32 && probe.active == 0 && probe.failure == 0;
	return queue
}
fn test_operation_queue_native() {
	$if macos {
		a := QueueApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		pool := a.msg(a.cls(c'NSAutoreleasePool'), c'new', 0)
		queue_main_dispatch_shared(a, queue_main_shared(a))
		queue_shared(a)
		a.msg(pool, c'drain', 0)
		println('IOS-OPERATION-QUEUE-NATIVE: main/current queue identity, immutable main scheduling policy, main-thread callbacks, suspension, serial workers, count, wait and capture retirement')
	}
}
fn queue_noop(_ voidptr) {}
fn queue_context_run(context voidptr) {
	probe := unsafe { &QueueProbe(context) }
	if ns_operation_queue_current() != probe.owner || C.__atomic_fetch_add(unsafe { &probe.active }, 1, 5) != 0 {
		C.__atomic_store_n(unsafe { &probe.failure }, 5, 5)
	}
	C.__atomic_fetch_add(unsafe { &probe.calls }, 1, 5)
	C.__atomic_fetch_add(unsafe { &probe.active }, ~u64(0), 5)
}
fn queue_context_drop(context voidptr) {
	probe := unsafe { &QueueProbe(context) }
	if probe.api.msg(probe.owner, c'operationCount', 0) == 0 { C.__atomic_store_n(unsafe { &probe.failure }, 6, 5) }
	C.__atomic_fetch_add(unsafe { &probe.drops }, 1, 5)
}
fn queue_context_producer(queue u64, context voidptr) {
	for _ in 0 .. 16 { ns_operation_queue_submit(queue, context, queue_context_run, queue_context_drop) }
}
fn queue_raw_main(context voidptr) {
	mut probe := unsafe { &QueueProbe(context) }
	assert probe.api.msg(probe.api.cls(c'NSOperationQueue'), c'currentQueue', 0) == probe.owner;
	assert u64(C.pthread_self()) == probe.thread;
	probe.calls++
}
fn queue_main_dispatch_shared(a QueueApi, main_queue u64) {
	mut raw := QueueProbe{api: a, owner: main_queue, thread: u64(C.pthread_self())}
	mut main_backing := u64(0)
	mut create := QueueDispatchCreate(darwin_dispatch_queue_create_with_target)
	mut submit := QueueDispatchAsync(darwin_dispatch_async_f)
	mut release := QueueDispatchRelease(darwin_dispatch_release)
	$if macos { if a.native {
		main_backing = u64(C.dlsym(unsafe { voidptr(-2) }, c'_dispatch_main_q'))
		create = unsafe { QueueDispatchCreate(C.dlsym(voidptr(-2), c'dispatch_queue_create_with_target')) }
		submit = unsafe { QueueDispatchAsync(C.dlsym(voidptr(-2), c'dispatch_async_f')) }
		release = unsafe { QueueDispatchRelease(C.dlsym(voidptr(-2), c'dispatch_release')) }
	} }
	if !a.native { main_backing = darwin_dispatch_get_main_queue() }
	targeted := create(c'org.vinix.main-operation-identity', 0, main_backing)
	for backing in [targeted, main_backing]! { submit(backing, unsafe { &raw }, queue_raw_main) }
	assert raw.calls == 0;
	deadline := time.sys_mono_now() + 5 * time.second
	for raw.calls != 2 { assert time.sys_mono_now() < deadline; a.pump() }
	assert a.msg(main_queue, c'operationCount', 0) == 0;
	release(targeted)
}
fn test_operation_queue_runtime() {
	a := QueueApi{send: u64(unsafe { voidptr(C.ios_objc_msgsend) })}
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!
		main_queue := queue_main_shared(a)
		assert obj_header(main_queue).operation_queue.backing == darwin_dispatch_get_main_queue();
		queue_main_dispatch_shared(a, main_queue)
		base := a.cls(c'NSOperationQueue')
		subclass := objc_allocate_class(base, c'VinixMainOperationQueue', 0)
		objc_register_class(subclass)
		for cls in [base, subclass]! {
			for selector in [c'mainQueue', c'currentQueue']! {
				assert a.msg(cls, selector, 0) == main_queue;
				assert a.msg(cls, c'respondsToSelector:', u64(selector)) == 1;
				method := objc_class_method(cls, u64(selector))
				assert method != 0 && ctext(u64(objc_method_types(method))) == '@16@0:8';
				imp := objc_method_imp(method)
				assert unsafe { QueueSend(voidptr(imp))(cls, u64(selector), 0) } == main_queue;
			}
		}
		assert objc_class_method(a.cls(c'NSObject'), u64(c'mainQueue')) == 0;
		queue_shared(a)
		parallel := a.msg(a.cls(c'NSOperationQueue'), c'new', 0)
		a.msg(parallel, c'setSuspended:', 1)
		mut concurrent := QueueProbe{api: a, owner: parallel}
		mut producers := []thread{}
		for _ in 0 .. 8 { producers << spawn queue_context_producer(parallel, unsafe { &concurrent }) }
		producers.wait(); unsafe { producers.free() }
		assert a.msg(parallel, c'operationCount', 0) == 128;
		a.msg(parallel, c'setSuspended:', 0)
		a.msg(parallel, c'waitUntilAllOperationsAreFinished', 0)
		assert concurrent.calls == 128 && concurrent.drops == 128 && concurrent.active == 0 && concurrent.failure == 0;
		a.msg(parallel, c'release', 0)
		queue := a.msg(a.cls(c'NSOperationQueue'), c'new', 0)
		method := objc_instance_method(a.cls(c'NSOperationQueue'), u64(c'addOperationWithBlock:'))
		assert method != 0 && ctext(u64(objc_method_types(method))) == 'v24@0:8@?16';
		assert objc_instance_method(a.cls(c'NSObject'), u64(c'addOperationWithBlock:')) == 0;
		// A pending job keeps its queue alive after the caller drops ownership,
		// even if its isa changes before the job's cleanup executes.
		mut probe := QueueProbe{api: a, owner: queue, thread: u64(C.pthread_self()), gate: 1}
		descriptor := QueueBlockDescriptor{0, sizeof(QueueBlock), u64(unsafe { voidptr(queue_probe_copy) }), u64(unsafe { voidptr(queue_probe_drop) })}
		block := QueueBlock{block_isa(0), u32(1) << 25, 0, u64(unsafe { voidptr(queue_probe_call) }), u64(unsafe { &descriptor }), u64(unsafe { &probe })}
		imp := objc_method_implementation(a.cls(c'NSOperationQueue'), u64(c'addOperationWithBlock:'))
		unsafe { QueueSend(voidptr(imp))(queue, u64(c'addOperationWithBlock:'), u64(&block)) }
		queue_probe_wait(unsafe { &probe.entered }, 1)
		backing := obj_header(queue).operation_queue.backing
		darwin_dispatch_retain(backing)
		mut weak := u64(0); objc_store_weak(unsafe { &weak }, queue)
		objc_set_class(queue, a.cls(c'NSObject')); a.msg(queue, c'release', 0)
		assert weak == queue;
		C.__atomic_store_n(unsafe { &probe.gate }, 0, 5)
		darwin_dispatch_sync_f(backing, unsafe { nil }, queue_noop)
		assert probe.calls == 1 && probe.drops == 1 && probe.failure == 0 && weak == 0;
		objc_destroy_weak(unsafe { &weak }); darwin_dispatch_release(backing)
		// Stop discards suspended work, releases every capture and queue pin,
		// and never mistakes discarded jobs for executed operations.
		pending := a.msg(a.cls(c'NSOperationQueue'), c'new', 0)
		a.msg(pending, c'setSuspended:', 1)
		mut stopped := QueueProbe{api: a, owner: pending, thread: u64(C.pthread_self()), check_disposal: true}
		stopped_block := QueueBlock{block_isa(0), u32(1) << 25, 0, u64(unsafe { voidptr(queue_probe_call) }), u64(unsafe { &descriptor }), u64(unsafe { &stopped })}
		for _ in 0 .. 32 { a.msg(pending, c'addOperationWithBlock:', u64(unsafe { &stopped_block })) }
		a.msg(pending, c'release', 0)
		mut stopped_main := QueueProbe{api: a, owner: main_queue, main: true, thread: u64(C.pthread_self()), check_disposal: true}
		main_block := QueueBlock{block_isa(0), u32(1) << 25, 0, u64(unsafe { voidptr(queue_probe_call) }), u64(unsafe { &descriptor }), u64(unsafe { &stopped_main })}
		for _ in 0 .. 32 { a.msg(main_queue, c'addOperationWithBlock:', u64(unsafe { &main_block })) }
		mut weak_main := u64(0); objc_store_weak(unsafe { &weak_main }, main_queue)
		objc_stop()
		assert stopped_main.copies == 32 && stopped_main.drops == 32 && stopped_main.calls == 0 && stopped_main.failure == 0;
		assert weak_main == 0 && ios_runtime.main_operation_queue == 0 && ns_operation_queue_main() == 0;
		objc_destroy_weak(unsafe { &weak_main })
		assert stopped.copies == 32 && stopped.drops == 32 && stopped.calls == 0 && stopped.failure == 0;
		assert ios_runtime.live == 0 && ios_runtime.block_refs.len == 0;
		system_data_stop()
	}
	println('IOS-OPERATION-QUEUE: raced main singleton, inherited main/current IMPs, main-thread drain, serial workers, suspension, wait, ownership, shutdown discard and two clean lifetimes')
}
