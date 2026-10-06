// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct ObjPool {
mut:
	objects []u64
}

fn objc_pool() &ObjPool {
	mut pointer := C.pthread_getspecific(ios_runtime.pool_key)
	if pointer == unsafe { nil } {
		mut pool := unsafe { &ObjPool(C.calloc(1, sizeof(ObjPool))) }
		if pool == unsafe { nil } { panic('iOS: cannot allocate autorelease pool') }
		pool.objects = []u64{}
		pool.objects.flags |= .noslices
		pointer = pool
		if C.pthread_setspecific(ios_runtime.pool_key, pointer) != 0 { panic('iOS: cannot set autorelease TLS') }
	}
	return unsafe { &ObjPool(pointer) }
}

fn objc_pool_free(pointer voidptr) {
	if pointer == unsafe { nil } { return }
	mut pool := unsafe { &ObjPool(pointer) }
	// A destructor may itself autorelease. Keep this pool available until its
	// releases finish; pthread clears the key before invoking a destructor.
	C.pthread_setspecific(ios_runtime.pool_key, pointer)
	for pool.objects.len > 0 { objc_release(pool.objects.pop()) }
	C.pthread_setspecific(ios_runtime.pool_key, unsafe { nil })
	unsafe { pool.objects.free() }
	C.free(pointer)
}

fn objc_autorelease(object u64) u64 {
	if object != 0 { mut pool := objc_pool(); pool.objects << object }
	return object
}

fn objc_pool_push() u64 { return u64(objc_pool().objects.len) + 1 }

fn objc_pool_pop(token u64) {
	mut pool := objc_pool()
	if token == 0 || token > u64(pool.objects.len) + 1 { panic('iOS: invalid autorelease pool') }
	for pool.objects.len >= int(token) { objc_release(pool.objects.pop()) }
}
