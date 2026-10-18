// SPDX-License-Identifier: GPL-2.0-or-later
module main

type DyldImageCallback = fn (voidptr, i64)

// One process-lifetime native recursive mutex protects registration, callback
// delivery and registry retirement, including callers waiting across teardown.
// It is independent of the Objective-C lock: a callback may use other threads
// which enter that runtime. All per-application callback storage is retired.
__global dyld_callbacks_mutex = dyld_callbacks_mutex_create()

fn dyld_callbacks_mutex_create() voidptr {
	mutex := C.calloc(1, C.ios_sizeof_mutex())
	if mutex == unsafe { nil } || C.ios_mutex_create(mutex, 2) != 0 {
		panic('iOS: cannot create dyld callback mutex')
	}
	return mutex
}

fn dyld_callbacks_lock() {
	if C.pthread_mutex_lock(dyld_callbacks_mutex) != 0 { panic('iOS: cannot lock dyld callbacks') }
}

fn dyld_callbacks_unlock() {
	if C.pthread_mutex_unlock(dyld_callbacks_mutex) != 0 {
		panic('iOS: cannot unlock dyld callbacks')
	}
}

fn dyld_callback_invoke(address u64, loaded &LoadedModule) {
	header := dyld_mapped_header(loaded)
	if header == 0 { panic('iOS: dyld callback image has no mapped header') }
	callback := unsafe { DyldImageCallback(voidptr(address)) }
	callback(unsafe { voidptr(header) }, i64(loaded.base - loaded.layout.base))
}

fn darwin_dyld_register_func_for_add_image(callback DyldImageCallback) {
	dyld_callbacks_lock()
	defer { dyld_callbacks_unlock() }
	if module_runtime == unsafe { nil } || module_runtime.auditing || module_runtime.dyld_retired {
		return
	}
	if callback == unsafe { nil } { panic('iOS: null dyld add-image callback') }
	address := u64(unsafe { voidptr(callback) })
	// Native dyld appends after replay, retaining duplicates. Reentrant
	// registrations replay immediately and enter the future list first.
	count := module_runtime.modules.len
	for i in 0 .. count {
		loaded := module_runtime.modules[i]
		if loaded.dyld_published { dyld_callback_invoke(address, loaded) }
	}
	module_runtime.dyld_add << address
}

fn darwin_dyld_register_func_for_remove_image(callback DyldImageCallback) {
	dyld_callbacks_lock()
	defer { dyld_callbacks_unlock() }
	if module_runtime == unsafe { nil } || module_runtime.auditing || module_runtime.dyld_retired {
		return
	}
	if callback == unsafe { nil } { panic('iOS: null dyld remove-image callback') }
	module_runtime.dyld_remove << u64(unsafe { voidptr(callback) })
}

// Publish a fully bound, protected batch before any +load or initializer.
// Registration during a notification replays the whole published set, so the
// current batch uses its original callback count instead of redelivering it.
fn dyld_images_publish() {
	dyld_callbacks_lock()
	defer { dyld_callbacks_unlock() }
	if module_runtime == unsafe { nil } || module_runtime.auditing || module_runtime.dyld_retired {
		return
	}
	mut added := [64]int{}
	mut count := 0
	for i, mut loaded in module_runtime.modules {
		if loaded.dyld_published { continue }
		if count == added.len { panic('iOS: dyld image publication exceeds limit') }
		loaded.dyld_published = true
		added[count] = i
		count++
	}
	callbacks := module_runtime.dyld_add.len
	for i in 0 .. count {
		loaded := module_runtime.modules[added[i]]
		for j in 0 .. callbacks { dyld_callback_invoke(module_runtime.dyld_add[j], loaded) }
	}
}

// Linked libraries stay mapped across dlclose. Actual runner retirement
// notifies in reverse initialization order after terminators, while every
// header, path, Objective-C object and TLS descriptor is still available.
fn dyld_images_retire() {
	dyld_callbacks_lock()
	defer { dyld_callbacks_unlock() }
	if module_runtime == unsafe { nil } || module_runtime.auditing
		|| module_runtime.dyld_retired || module_runtime.dyld_retiring {
		return
	}
	module_runtime.dyld_retiring = true
	callbacks := module_runtime.dyld_remove.len
	count := if module_runtime.order.len != 0 {
		module_runtime.order.len
	} else {
		module_runtime.modules.len
	}
	for i := count - 1; i >= 0; i-- {
		index := if module_runtime.order.len != 0 { module_runtime.order[i] } else { i }
		loaded := module_runtime.modules[index]
		if !loaded.dyld_published { continue }
		for j in 0 .. callbacks { dyld_callback_invoke(module_runtime.dyld_remove[j], loaded) }
	}
	module_runtime.dyld_retired = true
}
