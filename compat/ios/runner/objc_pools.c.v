// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct ObjPool {
mut:
	objects []u64
	frames []ObjPoolFrame
	draining_all bool
}

struct ObjPoolFrame {
mut:
	token u64
	offset int
	object u64 // One NSAutoreleasePool constructor reference, or zero for C scopes.
	draining bool
}

fn objc_pool() &ObjPool {
	mut pointer := C.pthread_getspecific(ios_runtime.pool_key)
	if pointer == unsafe { nil } {
		mut pool := unsafe { &ObjPool(C.calloc(1, sizeof(ObjPool))) }
		if pool == unsafe { nil } { panic('iOS: cannot allocate autorelease pool') }
		pool.objects = []u64{}
		pool.objects.flags |= .noslices
		pool.frames = []ObjPoolFrame{}
		pool.frames.flags |= .noslices
		pointer = pool
		if C.pthread_setspecific(ios_runtime.pool_key, pointer) != 0 {
			unsafe { pool.objects.free(); pool.frames.free() }; C.free(pointer)
			panic('iOS: cannot set autorelease TLS')
		}
	}
	return unsafe { &ObjPool(pointer) }
}

fn objc_pool_free(pointer voidptr) {
	if pointer == unsafe { nil } { return }
	mut pool := unsafe { &ObjPool(pointer) }
	// A destructor may itself autorelease. Keep this pool available until its
	// releases finish; pthread clears the key before invoking a destructor.
	C.pthread_setspecific(ios_runtime.pool_key, pointer)
	objc_pool_drain_all()
	C.pthread_setspecific(ios_runtime.pool_key, unsafe { nil })
	unsafe { pool.objects.free(); pool.frames.free() }
	C.free(pointer)
}

fn objc_autorelease(object u64) u64 {
	if swift_data_bridge_is_zero(object) { return object }
	ns_pool_reject_ownership(object)
	if object != 0 { mut pool := objc_pool(); pool.objects << object }
	return object
}

fn objc_pool_push_object(object u64) u64 {
	mut pool := objc_pool()
	if pool.frames.len >= 1024 { panic('iOS: autorelease pool nesting exceeds limit') }
	token := C.ios_ref_change(unsafe { &ios_runtime.pool_sequence }, 1)
	if token <= 1 || token == 9223372036854775807 { panic('iOS: autorelease pool token space exhausted') }
	mut frame := ObjPoolFrame{token: u64(token), offset: pool.objects.len, object: object}
	pool.frames << frame
	return u64(token)
}

fn objc_pool_push() u64 { return objc_pool_push_object(0) }

fn objc_pool_pop(token u64) {
	mut pool := objc_pool()
	mut target := -1
	for i, frame in pool.frames { if frame.token == token { target = i; break } }
	if target < 0 { panic('iOS: invalid or foreign autorelease pool token') }
	for i := target + 1; i < pool.frames.len; i++ {
		if pool.frames[i].draining { panic('iOS: reentrant autorelease pool drainage is not implemented') }
	}
	if target >= 0 {
		if pool.frames[target].draining { panic('iOS: reentrant autorelease pool drainage is not implemented') }
		pool.frames[target].draining = true
	}
	for pool.frames.len > target && pool.frames.len > 0 {
		index := pool.frames.len - 1
		pool.frames[index].draining = true
		offset := pool.frames[index].offset
		if pool.objects.len > offset { objc_release(pool.objects.pop()); continue }
		frame := pool.frames.pop()
		if frame.object != 0 { ns_pool_retire(frame.object) }
	}
}

fn objc_pool_drain_all() {
	mut pool := objc_pool()
	if pool.draining_all { panic('iOS: reentrant autorelease pool teardown is not implemented') }
	pool.draining_all = true
	defer { pool.draining_all = false }
	for pool.objects.len > 0 || pool.frames.len > 0 {
		if pool.frames.len > 0 { objc_pool_pop(pool.frames[0].token) }
		else { objc_release(pool.objects.pop()) }
	}
}
