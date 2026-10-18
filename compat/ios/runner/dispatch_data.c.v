// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Immutable nodes retain their two children; leaf buffers with custom
// destructors remain borrowed. Retirement is iterative, including long ropes.
struct DispatchData {
mut:
	isa u64
	refs u64 = 1
	size u64
	buffer u64
	owned bool
	immortal bool
	left &DispatchData = unsafe { nil }
	right &DispatchData = unsafe { nil }
	block u64
	queue u64
	called bool
	next &DispatchData = unsafe { nil }
}

fn dispatch_data_allocate() &DispatchData {
	mut data := unsafe { &DispatchData(C.calloc(1, sizeof(DispatchData))) }
	if data == unsafe { nil } { panic('iOS: cannot allocate dispatch data') }
	data.refs = 1
	data.isa = dispatch_runtime.data_classes[0]
	return data
}

fn dispatch_data_start() {
	mut empty := dispatch_data_allocate()
	empty.immortal = true
	dispatch_runtime.empty_data = empty
	dispatch_runtime.data[u64(empty)] = empty
}

fn dispatch_data_locked(identity u64) &DispatchData {
	return dispatch_runtime.data[identity] or { panic('iOS: invalid or released dispatch data') }
}

fn dispatch_data_retain_locked(mut data DispatchData) {
	if !data.immortal { data.refs++ }
}

fn dispatch_data_drop_locked(mut data DispatchData) {
	if data.immortal { return }
	if data.refs == 0 { panic('iOS: dispatch data over-release') }
	data.refs--
	if data.refs != 0 || dispatch_runtime.data_stopping { return }
	dispatch_runtime.data.delete(u64(&data))
	data.next = dispatch_runtime.data_retired
	dispatch_runtime.data_retired = &data
}

fn dispatch_data_destructor(context voidptr) {
	mut data := unsafe { &DispatchData(context) }
	data.called = true
	block_invoke_void(data.block)
}

// Cancellation at image shutdown still invokes an owned data destructor.
// Callbacks and block dispose helpers never run under the scheduler mutex.
fn dispatch_data_cleanup(context voidptr) {
	data := unsafe { &DispatchData(context) }
	if data.block != 0 {
		if !data.called { block_invoke_void(data.block) }
		block_release(data.block)
	}
	if data.owned { C.free(unsafe { voidptr(data.buffer) }) }
	if data.queue != 0 { darwin_dispatch_release(data.queue) }
	C.free(data)
}

fn dispatch_data_retire() {
	for {
		C.pthread_mutex_lock(dispatch_runtime.mutex)
		data := dispatch_runtime.data_retired
		if data == unsafe { nil } { C.pthread_mutex_unlock(dispatch_runtime.mutex); return }
		dispatch_runtime.data_retired = data.next
		if data.left != unsafe { nil } { dispatch_data_drop_locked(mut data.left) }
		if data.right != unsafe { nil } { dispatch_data_drop_locked(mut data.right) }
		C.pthread_mutex_unlock(dispatch_runtime.mutex)
		if data.block != 0 {
			dispatch_submit_owned(data.queue, data, dispatch_data_destructor, dispatch_data_cleanup)
		} else {
			dispatch_data_cleanup(data)
		}
	}
}

fn darwin_dispatch_data_create(buffer u64, size u64, queue u64, destructor u64) u64 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	if dispatch_runtime == unsafe { nil } { panic('iOS: dispatch data outside runtime lifetime') }
	if size != 0 && (buffer == 0 || buffer > ~u64(0) - size) { panic('iOS: invalid dispatch data buffer') }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	if dispatch_runtime.stopping || dispatch_runtime.data_stopping { panic('iOS: dispatch data created during image shutdown') }
	mut data := dispatch_data_allocate()
	data.size = size
	if destructor != 0 {
		if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { panic('iOS: dispatch data block outside Objective-C lifetime') }
		mut target := if queue == 0 { dispatch_global_locked(2) } else { dispatch_queue_locked(queue) }
		if !target.immortal { target.refs++ }
		data.queue = target.identity
	}
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
	if destructor == 0 {
		if size != 0 {
			data.buffer = u64(C.malloc(usize(size)))
			if data.buffer == 0 { panic('iOS: cannot copy dispatch data') }
			data.owned = true
			unsafe { C.memcpy(voidptr(data.buffer), voidptr(buffer), usize(size)) }
		}
	} else {
		data.buffer = buffer
		data.block = block_copy(destructor)
	}
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	stopped := dispatch_runtime.stopping || dispatch_runtime.data_stopping
	if !stopped && size != 0 { dispatch_runtime.data[u64(data)] = data }
	empty := u64(dispatch_runtime.empty_data)
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
	if stopped || size == 0 {
		if data.block != 0 { dispatch_submit_owned(data.queue, data, dispatch_data_destructor, dispatch_data_cleanup) }
		else { dispatch_data_cleanup(data) }
		if stopped { panic('iOS: dispatch data creation interrupted by image shutdown') }
		return empty
	}
	return u64(data)
}

fn darwin_dispatch_data_get_size(identity u64) u64 {
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	return dispatch_data_locked(identity).size
}

fn darwin_dispatch_data_create_concat(first u64, second u64) u64 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	if dispatch_runtime.stopping || dispatch_runtime.data_stopping { panic('iOS: dispatch data concatenated during image shutdown') }
	mut left := dispatch_data_locked(first)
	mut right := dispatch_data_locked(second)
	if left.size == 0 { dispatch_data_retain_locked(mut right); return second }
	if right.size == 0 { dispatch_data_retain_locked(mut left); return first }
	if left.size > ~u64(0) - right.size { panic('iOS: dispatch data size overflow') }
	mut data := dispatch_data_allocate()
	data.left = left
	data.right = right
	data.size = left.size + right.size
	dispatch_data_retain_locked(mut left)
	dispatch_data_retain_locked(mut right)
	dispatch_runtime.data[u64(data)] = data
	return u64(data)
}

fn darwin_dispatch_data_create_map(identity u64, buffer &u64, size &u64) u64 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	mut source := dispatch_data_locked(identity)
	if dispatch_runtime.stopping || dispatch_runtime.data_stopping { panic('iOS: dispatch data mapped during image shutdown') }
	if source.left == unsafe { nil } {
		dispatch_data_retain_locked(mut source)
		C.pthread_mutex_unlock(dispatch_runtime.mutex)
		if buffer != unsafe { nil } { unsafe { *buffer = source.buffer } }
		if size != unsafe { nil } { unsafe { *size = source.size } }
		return identity
	}
	// Keep the graph alive independently while copying outside the mutex.
	dispatch_data_retain_locked(mut source)
	mut mapped := dispatch_data_allocate()
	mapped.size = source.size
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
	mapped.buffer = u64(C.malloc(usize(mapped.size)))
	if mapped.buffer == 0 { panic('iOS: cannot map dispatch data') }
	mapped.owned = true
	mut pending := []&DispatchData{cap: 16}
	pending.flags |= .noslices
	pending << source
	mut offset := u64(0)
	for pending.len != 0 {
		part := pending.pop()
		if part.left != unsafe { nil } { pending << part.right; pending << part.left; continue }
		if part.size != 0 { unsafe { C.memcpy(voidptr(mapped.buffer + offset), voidptr(part.buffer), usize(part.size)) } }
		offset += part.size
	}
	unsafe { pending.free() }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	dispatch_runtime.data[u64(mapped)] = mapped
	dispatch_data_drop_locked(mut source)
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
	dispatch_data_retire()
	if buffer != unsafe { nil } { unsafe { *buffer = mapped.buffer } }
	if size != unsafe { nil } { unsafe { *size = mapped.size } }
	return u64(mapped)
}

// After workers join and pools drain, destroy remaining captures while every
// data buffer is still valid. A dispose helper may release another data node.
fn dispatch_data_stop() {
	if dispatch_runtime == unsafe { nil } || dispatch_runtime.data_stopping { return }
	dispatch_runtime.data_stopping = true
	for _, mut data in dispatch_runtime.data {
		block := data.block
		queue := data.queue
		data.block = 0
		data.queue = 0
		if block != 0 { block_invoke_void(block); block_release(block) }
		if queue != 0 { darwin_dispatch_release(queue) }
	}
}

fn dispatch_data_free() {
	if dispatch_runtime == unsafe { nil } { return }
	for _, data in dispatch_runtime.data {
		if data.immortal { continue }
		if data.owned { C.free(unsafe { voidptr(data.buffer) }) }
		C.free(data)
	}
	dispatch_runtime.data.clear()
	dispatch_runtime.data[u64(dispatch_runtime.empty_data)] = dispatch_runtime.empty_data
}

fn dispatch_data_symbol(symbol string) ?u64 {
	return match symbol {
		'_dispatch_data_create' { u64(unsafe { voidptr(darwin_dispatch_data_create) }) }
		'_dispatch_data_create_concat' { u64(unsafe { voidptr(darwin_dispatch_data_create_concat) }) }
		'_dispatch_data_create_map' { u64(unsafe { voidptr(darwin_dispatch_data_create_map) }) }
		'_dispatch_data_get_size' { u64(unsafe { voidptr(darwin_dispatch_data_get_size) }) }
		'__dispatch_data_empty' {
			if dispatch_runtime == unsafe { nil } || dispatch_runtime.data_stopping { return none }
			return u64(dispatch_runtime.empty_data)
		}
		else { return none }
	}
}
