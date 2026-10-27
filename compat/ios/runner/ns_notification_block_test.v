// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
	#include <dlfcn.h>
	fn C.objc_getClass(&char) voidptr
	fn C.sel_registerName(&char) voidptr
	fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
	fn C.method_getTypeEncoding(voidptr) &char
	fn C.dlsym(voidptr, &char) voidptr
}

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
	copies int
	disposals int
	calls int
	last u64
	thread usize
	center u64
	token u64
	self_remove bool
	unlocked bool
	descriptor [4]u64
}

fn note_block_lock_reader() { C.ios_objc_initialize_lock(); C.ios_objc_initialize_unlock() }

fn note_block_copy(destination u64, source u64) {
	state := unsafe { &NoteBlockState(read64(source + 32)) }
	write64(destination + 40, state.api.retain(read64(source + 40)))
	unsafe { state.copies++ }
	if state.unlocked { worker := spawn note_block_lock_reader(); worker.wait() }
}

fn note_block_dispose(source u64) {
	state := unsafe { &NoteBlockState(read64(source + 32)) }
	state.api.release(read64(source + 40))
	unsafe { state.disposals++ }
	if state.unlocked { worker := spawn note_block_lock_reader(); worker.wait() }
}

fn note_block_receive(block u64, note u64) {
	mut state := unsafe { &NoteBlockState(read64(block + 32)) }
	assert state.thread == usize(C.pthread_self())
	state.calls++
	state.api.release(state.last)
	state.last = state.api.retain(note)
	if state.unlocked { worker := spawn note_block_lock_reader(); worker.wait() }
	if state.self_remove {
		state.api.msg(state.center, c'removeObserver:', state.token, 0, 0, 0)
		state.api.msg(state.center, c'postNotification:', note, 0, 0, 0)
	}
}

fn note_block_add(mut state NoteBlockState, name u64, sender u64, capture u64) u64 {
	// A copied block keeps its descriptor pointer, so the descriptor must outlive it.
	state.descriptor = [u64(0), 48, u64(unsafe { voidptr(note_block_copy) }), u64(unsafe { voidptr(note_block_dispose) })]!
	mut literal := [state.api.stack, u64(1) << 25, u64(unsafe { voidptr(note_block_receive) }),
		u64(unsafe { &state.descriptor[0] }), u64(unsafe { &state }), capture]!
	return state.api.msg(state.center, c'addObserverForName:object:queue:usingBlock:', name, sender, 0, u64(unsafe { &literal[0] }))
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
}
