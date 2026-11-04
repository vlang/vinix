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
	#include <dlfcn.h>
	fn C.objc_getClass(&char) voidptr
	fn C.sel_registerName(&char) voidptr
	fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
	fn C.method_getTypeEncoding(voidptr) &char
	fn C.dlsym(voidptr, &char) voidptr
}
fn C.CFRunLoopRunInMode(voidptr, f64, bool) i32
fn C.__atomic_load_n(&u64, int) u64
fn C.__atomic_store_n(&u64, u64, int)
fn C.__atomic_fetch_add(&u64, u64, int) u64

type NoteBlockSend = fn (u64, u64, u64, u64, u64, u64) u64

struct NoteBlockApi {
	native bool
	send u64
	stack u64
}

fn (api NoteBlockApi) cls(name string) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name.str)) } }
	return ios_runtime.names[name]
}

fn (api NoteBlockApi) sel(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}

fn (api NoteBlockApi) msg(object u64, name &char, a u64, b u64, c u64, d u64) u64 {
	return unsafe { NoteBlockSend(voidptr(api.send))(object, api.sel(name), a, b, c, d) }
}

fn (api NoteBlockApi) retain(object u64) u64 { return api.msg(object, c'retain', 0, 0, 0, 0) }
fn (api NoteBlockApi) release(object u64) { api.msg(object, c'release', 0, 0, 0, 0) }
fn (api NoteBlockApi) string(text string) u64 { return api.msg(api.cls('NSString'), c'stringWithUTF8String:', u64(text.str), 0, 0, 0) }
fn (api NoteBlockApi) pool() u64 {
	if api.native { return api.msg(api.cls('NSAutoreleasePool'), c'new', 0, 0, 0, 0) }
	return objc_pool_push()
}
fn (api NoteBlockApi) pop(pool u64) {
	if api.native { api.msg(pool, c'drain', 0, 0, 0, 0) } else { objc_pool_pop(pool) }
}

struct NoteBlockState {
	api NoteBlockApi
mut:
	copies u64
	disposals u64
	calls u64
	last u64
	thread usize
	center u64
	token u64
	queue u64
	worker bool
	nested bool
	self_remove bool
	unlocked bool
	descriptor [4]u64
}

fn note_block_lock_reader() { C.ios_objc_initialize_lock(); C.ios_objc_initialize_unlock() }

fn note_block_copy(destination u64, source u64) {
	state := unsafe { &NoteBlockState(read64(source + 32)) }
	write64(destination + 40, state.api.retain(read64(source + 40)))
	C.__atomic_fetch_add(unsafe { &state.copies }, 1, 5)
	if state.unlocked { worker := spawn note_block_lock_reader(); worker.wait() }
}

fn note_block_dispose(source u64) {
	state := unsafe { &NoteBlockState(read64(source + 32)) }
	state.api.release(read64(source + 40))
	if state.unlocked { worker := spawn note_block_lock_reader(); worker.wait() }
	C.__atomic_fetch_add(unsafe { &state.disposals }, 1, 5)
}

fn note_block_receive(block u64, note u64) {
	mut state := unsafe { &NoteBlockState(read64(block + 32)) }
	assert (state.thread == usize(C.pthread_self())) != state.worker
	if state.queue != 0 { assert state.api.msg(state.api.cls('NSOperationQueue'), c'currentQueue', 0, 0, 0, 0) == state.queue }
	C.__atomic_fetch_add(unsafe { &state.calls }, 1, 5)
	state.api.release(state.last)
	state.last = state.api.retain(note)
	if state.unlocked { worker := spawn note_block_lock_reader(); worker.wait() }
	if state.self_remove {
		state.api.msg(state.center, c'removeObserver:', state.token, 0, 0, 0)
		state.api.msg(state.center, c'postNotification:', note, 0, 0, 0)
	}
	if state.nested {
		state.nested = false
		state.api.msg(state.center, c'postNotification:', note, 0, 0, 0)
	}
}

fn note_block_add(mut state NoteBlockState, name u64, sender u64, capture u64) u64 {
	// A copied block keeps its descriptor pointer, so the descriptor must outlive it.
	state.descriptor = [u64(0), 48, u64(unsafe { voidptr(note_block_copy) }), u64(unsafe { voidptr(note_block_dispose) })]!
	mut literal := [state.api.stack, u64(1) << 25, u64(unsafe { voidptr(note_block_receive) }),
		u64(unsafe { &state.descriptor[0] }), u64(unsafe { &state }), capture]!
	return state.api.msg(state.center, c'addObserverForName:object:queue:usingBlock:', name, sender, state.queue, u64(unsafe { &literal[0] }))
}

struct NoteQueuedPost {
	api NoteBlockApi
	center u64
	name u64
mut:
	entered u64
	returned u64
}
fn note_queued_post_worker(post &NoteQueuedPost) {
	pool := post.api.pool()
	C.__atomic_store_n(unsafe { &post.entered }, 1, 5)
	post.api.msg(post.center, c'postNotificationName:object:', post.name, 0, 0, 0)
	C.__atomic_store_n(unsafe { &post.returned }, 1, 5)
	post.api.pop(pool)
}
fn note_queued_wait_pending(api NoteBlockApi, queue u64, post &NoteQueuedPost) {
	deadline := time.sys_mono_now() + 5 * time.second
	for api.msg(queue, c'operationCount', 0, 0, 0, 0) == 0 {
		assert time.sys_mono_now() < deadline;
		time.sleep(time.millisecond)
	}
	assert C.__atomic_load_n(unsafe { &post.entered }, 5) == 1 && C.__atomic_load_n(unsafe { &post.returned }, 5) == 0;
}
fn note_queued_pump(api NoteBlockApi) {
	$if macos { if api.native {
		cell := C.dlsym(unsafe { voidptr(-2) }, c'kCFRunLoopDefaultMode')
		C.CFRunLoopRunInMode(unsafe { voidptr(*(&u64(cell))) }, 0.001, false)
		return
	} }
	dispatch_main_drain()
}
fn note_queued_outer(block u64) {
	state := unsafe { &NoteBlockState(read64(block + 32)) }
	state.api.msg(state.center, c'postNotificationName:object:', state.api.string('Queued'), 0, 0, 0)
	assert state.calls == 2;
}
fn note_queued_watchdog(done &u64) {
	deadline := time.sys_mono_now() + 30 * time.second
	for C.__atomic_load_n(done, 5) == 0 {
		if time.sys_mono_now() >= deadline { eprintln('IOS-NOTIFICATION-QUEUED: callback/post deadlock'); C._exit(124) }
		time.sleep(10 * time.millisecond)
	}
}

struct NoteQueuedTail {
mut:
	entered u64
	gate u64 = 1
}
fn note_queued_tail(block u64) {
	tail := unsafe { &NoteQueuedTail(read64(block + 32)) }
	C.__atomic_store_n(unsafe { &tail.entered }, 1, 5)
	for C.__atomic_load_n(unsafe { &tail.gate }, 5) != 0 { time.sleep(time.millisecond) }
}

fn note_queued_own_wait(api NoteBlockApi, center u64, queue u64, name u64) {
	pool := api.pool()
	mut state := NoteBlockState{api: api, center: center, queue: queue, thread: usize(C.pthread_self()), worker: true}
	state.token = note_block_add(mut state, name, 0, 0)
	api.msg(queue, c'setSuspended:', 1, 0, 0, 0)
	mut post := NoteQueuedPost{api: api, center: center, name: name}
	poster := spawn note_queued_post_worker(unsafe { &post })
	note_queued_wait_pending(api, queue, unsafe { &post })
	mut tail := NoteQueuedTail{}
	descriptor := [u64(0), u64(40)]!
	literal := [api.stack, u64(0), u64(unsafe { voidptr(note_queued_tail) }), u64(unsafe { &descriptor[0] }), u64(unsafe { &tail })]!
	api.msg(queue, c'addOperationWithBlock:', u64(unsafe { &literal[0] }), 0, 0, 0)
	api.msg(queue, c'setSuspended:', 0, 0, 0, 0)
	deadline := time.sys_mono_now() + 5 * time.second
	for C.__atomic_load_n(unsafe { &tail.entered }, 5) == 0 { assert time.sys_mono_now() < deadline; time.sleep(time.millisecond) }
	until := time.sys_mono_now() + time.second
	for C.__atomic_load_n(unsafe { &post.returned }, 5) == 0 && time.sys_mono_now() < until { time.sleep(time.millisecond) }
	returned := C.__atomic_load_n(unsafe { &post.returned }, 5) != 0
	C.__atomic_store_n(unsafe { &tail.gate }, 0, 5)
	poster.wait()
	api.msg(queue, c'waitUntilAllOperationsAreFinished', 0, 0, 0, 0)
	api.msg(center, c'removeObserver:', state.token, 0, 0, 0)
	api.release(state.last)
	api.pop(pool)
	note_queued_wait_disposed(unsafe { &state })
	assert returned && state.calls == 1; // Later unrelated work must not hold up post.
}

fn note_queued_wait_disposed(state &NoteBlockState) {
	deadline := time.sys_mono_now() + 5 * time.second
	for C.__atomic_load_n(unsafe { &state.copies }, 5) != C.__atomic_load_n(unsafe { &state.disposals }, 5) {
		assert time.sys_mono_now() < deadline;
		time.sleep(time.millisecond)
	}
}

fn note_queued_case(api NoteBlockApi) {
	mut done := u64(0)
	watchdog := spawn note_queued_watchdog(unsafe { &done })
	defer { C.__atomic_store_n(unsafe { &done }, 1, 5); watchdog.wait() }
	pool := api.pool()
	center := api.msg(api.cls('NSNotificationCenter'), c'new', 0, 0, 0, 0)
	queue := api.msg(api.cls('NSOperationQueue'), c'new', 0, 0, 0, 0)
	api.msg(queue, c'setMaxConcurrentOperationCount:', 1, 0, 0, 0)
	name := api.string('Queued')
	mut direct := NoteBlockState{api: api, center: center, queue: queue, thread: usize(C.pthread_self()), worker: true, unlocked: true}
	direct.token = note_block_add(mut direct, name, 0, 0)
	api.msg(center, c'postNotificationName:object:', api.string('Wrong'), 0, 0, 0)
	assert direct.calls == 0;
	api.msg(center, c'postNotificationName:object:', name, 0, 0, 0)
	assert direct.calls == 1; // Posting waits for this queue's callback.
	api.msg(center, c'removeObserver:', direct.token, 0, 0, 0)
	api.release(direct.last)

	// Reposting from the requested serial queue must run inline, not wait on
	// an operation queued behind itself. Exercise nested notification delivery.
	mut nested := NoteBlockState{api: api, center: center, queue: queue, thread: usize(C.pthread_self()), worker: true, nested: true, unlocked: true}
	nested.token = note_block_add(mut nested, name, 0, 0)
	mut outer := [api.stack, u64(1) << 25, u64(unsafe { voidptr(note_queued_outer) }), u64(unsafe { &nested.descriptor[0] }), u64(unsafe { &nested }), u64(0)]!
	api.msg(queue, c'addOperationWithBlock:', u64(unsafe { &outer[0] }), 0, 0, 0)
	api.msg(queue, c'waitUntilAllOperationsAreFinished', 0, 0, 0, 0)
	assert nested.calls == 2;
	api.msg(center, c'removeObserver:', nested.token, 0, 0, 0)
	api.release(nested.last)

	main_queue := api.msg(api.cls('NSOperationQueue'), c'mainQueue', 0, 0, 0, 0)
	mut on_main := NoteBlockState{api: api, center: center, queue: main_queue, thread: usize(C.pthread_self()), self_remove: true, unlocked: true}
	on_main.token = note_block_add(mut on_main, name, 0, 0)
	api.msg(center, c'postNotificationName:object:', name, 0, 0, 0)
	assert on_main.calls == 1; // Main-thread posts must not enqueue and deadlock.
	api.release(on_main.last)
	mut delivered := NoteBlockState{api: api, center: center, queue: main_queue, thread: usize(C.pthread_self()), unlocked: true}
	delivered.token = note_block_add(mut delivered, name, 0, 0)
	mut posted := NoteQueuedPost{api: api, center: center, name: name}
	poster := spawn note_queued_post_worker(unsafe { &posted })
	note_queued_wait_pending(api, main_queue, unsafe { &posted })
	assert delivered.calls == 0;
	deadline := time.sys_mono_now() + 5 * time.second
	for C.__atomic_load_n(unsafe { &posted.returned }, 5) == 0 {
		assert time.sys_mono_now() < deadline;
		note_queued_pump(api)
	}
	poster.wait()
	assert delivered.calls == 1;
	api.msg(center, c'removeObserver:', delivered.token, 0, 0, 0)
	api.release(delivered.last)

	// Removing a pending registration suppresses delivery. The posting thread
	// still waits for its queued operation to retire and release its capture.
	api.msg(queue, c'setSuspended:', 1, 0, 0, 0)
	mut pending := NoteBlockState{api: api, center: center, queue: queue, thread: usize(C.pthread_self()), worker: true, unlocked: true}
	pending.token = note_block_add(mut pending, name, 0, 0)
	mut waiting := NoteQueuedPost{api: api, center: center, name: name}
	blocked := spawn note_queued_post_worker(unsafe { &waiting })
	note_queued_wait_pending(api, queue, unsafe { &waiting })
	api.msg(center, c'removeObserver:', pending.token, 0, 0, 0)
	assert pending.calls == 0 && pending.disposals == 0;
	api.msg(queue, c'setSuspended:', 0, 0, 0, 0)
	blocked.wait()
	api.msg(queue, c'waitUntilAllOperationsAreFinished', 0, 0, 0, 0)
	assert pending.calls == 0;
	api.release(pending.last)
	note_queued_own_wait(api, center, queue, name)
	api.release(queue)
	api.release(center)
	api.pop(pool)
	for state in [unsafe { &direct }, unsafe { &nested }, unsafe { &on_main }, unsafe { &delivered }, unsafe { &pending }]! { note_queued_wait_disposed(state) }
	assert direct.copies == direct.disposals && nested.copies == nested.disposals && on_main.copies == on_main.disposals && delivered.copies == delivered.disposals && pending.copies == pending.disposals;
}

fn note_queued_runtime_edges(api NoteBlockApi) {
	pool := api.pool()
	center := api.msg(api.cls('NSNotificationCenter'), c'new', 0, 0, 0, 0)
	queue := api.msg(api.cls('NSOperationQueue'), c'new', 0, 0, 0, 0)
	mut state := NoteBlockState{api: api, center: center, queue: queue, thread: usize(C.pthread_self()), worker: true, unlocked: true}
	token := note_block_add(mut state, 0, 0, 0)
	mut weak := u64(0); objc_store_weak(unsafe { &weak }, queue)
	api.release(queue)
	assert weak == queue; // The registration owns its requested queue.
	api.msg(center, c'removeObserver:', token, 0, 0, 0)
	assert weak == 0 && state.disposals == 1;
	objc_destroy_weak(unsafe { &weak })

	main_queue := api.msg(api.cls('NSOperationQueue'), c'mainQueue', 0, 0, 0, 0)
	mut stopped := NoteBlockState{api: api, center: center, queue: main_queue, thread: usize(C.pthread_self()), unlocked: true}
	stopped.token = note_block_add(mut stopped, 0, 0, 0)
	mut post := NoteQueuedPost{api: api, center: center, name: api.string('Stop')}
	poster := spawn note_queued_post_worker(unsafe { &post })
	note_queued_wait_pending(api, main_queue, unsafe { &post })
	// Join the external posting thread before tearing down Foundation. Discard
	// must wake its private completion even though the callback never executes.
	dispatch_stop()
	poster.wait()
	assert stopped.calls == 0 && C.__atomic_load_n(unsafe { &post.returned }, 5) == 1;
	api.msg(center, c'removeObserver:', stopped.token, 0, 0, 0)
	assert stopped.disposals == 1 && api.msg(main_queue, c'operationCount', 0, 0, 0, 0) == 0;
	api.release(center)
	api.pop(pool)
}

fn note_block_case(api NoteBlockApi) {
	pool := api.pool()
	center := api.msg(api.cls('NSNotificationCenter'), c'new', 0, 0, 0, 0)
	other := api.msg(api.cls('NSNotificationCenter'), c'new', 0, 0, 0, 0)
	sender := api.msg(api.cls('NSObject'), c'new', 0, 0, 0, 0)
	info := api.msg(api.cls('NSDictionary'), c'dictionary', 0, 0, 0, 0)
	name := api.string('Vinix.通知')
	equal := api.string('Vinix.通知')
	wrong := api.string('Vinix.Other')
	mut state := NoteBlockState{api: api, center: center, thread: usize(C.pthread_self()), unlocked: true}
	token := note_block_add(mut state, name, sender, sender)
	assert token != 0 && state.copies == 1 && state.disposals == 0
	api.retain(token)
	api.msg(center, c'postNotificationName:object:userInfo:', wrong, sender, info, 0)
	api.msg(center, c'postNotificationName:object:userInfo:', name, other, info, 0)
	api.msg(other, c'postNotificationName:object:userInfo:', name, sender, info, 0)
	assert state.calls == 0
	api.msg(center, c'postNotificationName:object:userInfo:', equal, sender, info, 0)
	assert state.calls == 1
	assert api.msg(state.last, c'object', 0, 0, 0, 0) == sender
	assert api.msg(state.last, c'userInfo', 0, 0, 0, 0) == info
	api.msg(center, c'postNotificationName:object:', equal, sender, 0, 0)
	assert state.calls == 2
	api.msg(center, c'removeObserver:name:object:', token, equal, sender, 0)
	assert state.disposals == 1 // A retained token must not prolong its capture.
	api.msg(center, c'postNotificationName:object:', name, sender, 0, 0)
	assert state.calls == 2
	api.release(token)
	api.release(state.last)
	state.last = 0
	api.release(sender)
	api.release(other)
	api.release(center)
	api.pop(pool)
	assert state.disposals == 1

	// Nil filters, no caller ownership of the token, removal during delivery.
	inner := api.pool()
	c := api.msg(api.cls('NSNotificationCenter'), c'new', 0, 0, 0, 0)
	mut once := NoteBlockState{api: api, center: c, thread: usize(C.pthread_self()), self_remove: true, unlocked: true}
	once.token = note_block_add(mut once, 0, 0, 0)
	api.pop(inner) // The center must still own the registration and copied block.
	next := api.pool()
	api.msg(c, c'postNotificationName:object:', api.string('OneShot'), 0, 0, 0)
	assert once.calls == 1 && once.copies == 1 && once.disposals == 1
	api.release(once.last)
	api.release(c)
	api.pop(next)

	// Destroying a non-default center must release outstanding registrations.
	if !api.native {
		last_pool := api.pool()
		last_center := api.msg(api.cls('NSNotificationCenter'), c'new', 0, 0, 0, 0)
		mut last := NoteBlockState{api: api, center: last_center, thread: usize(C.pthread_self()), unlocked: true}
		note_block_add(mut last, 0, 0, 0)
		api.release(last_center)
		api.pop(last_pool)
		assert last.copies == 1 && last.disposals == 1
	}
	// Opaque tokens remove their own registration regardless of these arguments.
	for variant in 0 .. 3 {
		p := api.pool()
		a := api.msg(api.cls('NSNotificationCenter'), c'new', 0, 0, 0, 0)
		b := api.msg(api.cls('NSNotificationCenter'), c'new', 0, 0, 0, 0)
		n := api.string('Removal')
		mut check := NoteBlockState{api: api, center: a, thread: usize(C.pthread_self())}
		t := note_block_add(mut check, n, a, 0)
		api.retain(t)
		if variant == 0 { api.msg(a, c'removeObserver:name:object:', t, api.string('Wrong'), a, 0) }
		if variant == 1 { api.msg(a, c'removeObserver:name:object:', t, n, b, 0) }
		if variant == 2 { api.msg(b, c'removeObserver:', t, 0, 0, 0) }
		api.msg(a, c'postNotificationName:object:', n, a, 0, 0)
		assert check.calls == 0 && check.disposals == 1
		api.msg(a, c'removeObserver:', t, 0, 0, 0)
		api.release(t)
		api.release(check.last)
		api.release(a); api.release(b); api.pop(p)
	}
}

fn note_block_worker(api NoteBlockApi, center u64, index int) {
	pool := api.pool()
	name := api.string('Vinix.Worker.' + index.str())
	for _ in 0 .. 32 {
		mut state := NoteBlockState{api: api, center: center, thread: usize(C.pthread_self())}
		token := note_block_add(mut state, name, 0, 0)
		api.msg(center, c'postNotificationName:object:', name, 0, 0, 0)
		assert state.calls == 1
		api.msg(center, c'removeObserver:', token, 0, 0, 0)
		api.release(state.last)
		// Native Foundation may autorelease its opaque token.
		if !api.native { assert state.disposals == 1 }
	}
	api.pop(pool)
}

fn test_ns_notification_block() {
	$if macos {
		send := C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')
		stack := C.dlsym(unsafe { voidptr(-2) }, c'_NSConcreteStackBlock')
		assert send != unsafe { nil } && stack != unsafe { nil }
		api := NoteBlockApi{native: true, send: u64(send), stack: u64(stack)}
		method := C.class_getInstanceMethod(unsafe { voidptr(api.cls('NSNotificationCenter')) }, unsafe { voidptr(api.sel(c'addObserverForName:object:queue:usingBlock:')) })
		assert unsafe { cstring_to_vstring(C.method_getTypeEncoding(method)) } == '@48@0:8@16@24@32@?40'
		note_block_case(api)
		note_queued_case(api)
		println('IOS-NOTIFICATION-QUEUED-NATIVE: synchronous posting, worker/main affinity, same-queue nested delivery and pending removal PASS')
		println('IOS-NOTIFICATION-BLOCK-NATIVE: nil-queue synchronous delivery, filters, copied captures, owned tokens and removal during callbacks PASS')
	}
	for _ in 0 .. 2 {
		objc_start()
		api := NoteBlockApi{send: u64(unsafe { voidptr(C.ios_objc_builtin) }), stack: block_isa(0)}
		cls := api.cls('NSNotificationCenter')
		method := objc_instance_method(cls, u64(c'addObserverForName:object:queue:usingBlock:'))
		assert method != 0 && ctext(u64(objc_method_types(method))) == '@48@0:8@16@24@32@?40'
		note_block_case(api)
		pool := api.pool()
		center := api.msg(cls, c'new', 0, 0, 0, 0)
		assert api.msg(center, c'respondsToSelector:', u64(c'addObserverForName:object:queue:usingBlock:'), 0, 0, 0) != 0
		mut workers := []thread{}
		for i in 0 .. 8 { workers << spawn note_block_worker(api, center, i) }
		workers.wait()
		unsafe { workers.free() }
		api.release(center)
		api.pop(pool)
		assert ios_runtime.observers.len == 0 && ios_runtime.block_refs.len == 0
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		objc_stop()
	}
	println('IOS-NOTIFICATION-BLOCK: nil-queue callbacks, name and sender filters, block/token ownership, reentrant removal, unlocked captures, center cleanup, eight concurrent workers and two drained runtimes PASS')
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!
		api := NoteBlockApi{send: u64(unsafe { voidptr(C.ios_objc_builtin) }), stack: block_isa(0)}
		note_queued_case(api)
		note_queued_runtime_edges(api)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.block_refs.len == 0;
		system_data_stop()
	}
	println('IOS-NOTIFICATION-QUEUED: synchronous queue delivery, own-job wait, main-thread pump, reentrant posting/removal, retained queues, pending removal, shutdown wakeup and two clean lifetimes PASS')
}
