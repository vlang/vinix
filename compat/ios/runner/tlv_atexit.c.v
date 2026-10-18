// SPDX-License-Identifier: GPL-2.0-or-later
module main

import sync

struct ImageTlsBlock {
	storage &ImageTls
	bytes   voidptr
}

struct ImageTlvDestructor {
	function ImageDestructor @[required]
	argument voidptr
}

struct ImageTlsThread {
	runtime &ImageRuntime
mut:
	previous    &ImageTlsThread = unsafe { nil }
	next        &ImageTlsThread = unsafe { nil }
	blocks      []ImageTlsBlock
	destructors []ImageTlvDestructor
	draining    bool
}

// This gate outlives executions. A native key destructor's counted owner
// keeps its runtime, templates and mapped callback code alive until it returns.
__global image_tls_lock = sync.new_mutex()

fn image_tls_start() {
	if C.pthread_key_create(unsafe { voidptr(&image_runtime.tls_key) },
		unsafe { voidptr(image_tls_thread_destroy) }) != 0 {
		panic('iOS: cannot allocate application TLS key')
	}
	image_runtime.tls_active = true
}

fn image_tls_thread() &ImageTlsThread {
	image_tls_lock.lock()
	defer { image_tls_lock.unlock() }
	if image_runtime == unsafe { nil } || !image_runtime.tls_active || image_runtime.tls_closing {
		panic('iOS: application TLS is not active')
	}
	pointer := C.pthread_getspecific(image_runtime.tls_key)
	if pointer != unsafe { nil } { return unsafe { &ImageTlsThread(pointer) } }
	mut state := &ImageTlsThread{ runtime: image_runtime }
	state.blocks.flags |= .noslices
	state.destructors.flags |= .noslices
	if C.pthread_setspecific(image_runtime.tls_key, state) != 0 {
		unsafe { free(state) }
		panic('iOS: cannot install application TLS')
	}
	image_runtime.tls_threads++
	state.next = image_runtime.tls_owners
	if state.next != unsafe { nil } { state.next.previous = state }
	image_runtime.tls_owners = state
	return state
}

fn image_tls_block(mut state ImageTlsThread, storage &ImageTls) voidptr {
	for block in state.blocks {
		if block.storage == storage { return block.bytes }
	}
	image_tls_lock.lock()
	defer { image_tls_lock.unlock() }
	bytes := C.malloc(usize(storage.template.len))
	if bytes == unsafe { nil } { panic('iOS: cannot allocate thread-local storage') }
	unsafe { C.memcpy(bytes, storage.template.data, usize(storage.template.len)) }
	state.blocks << ImageTlsBlock{storage, bytes}
	return bytes
}

fn image_tlv_atexit(function ImageDestructor, argument voidptr) {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	if function == unsafe { nil } { panic('iOS: null thread-local destructor') }
	mut state := image_tls_thread()
	image_tls_lock.lock()
	defer { image_tls_lock.unlock() }
	state.destructors << ImageTlvDestructor{function, argument}
}

fn image_tls_drain(mut state ImageTlsThread) {
	image_tls_lock.lock()
	if state.draining {
		image_tls_lock.unlock()
		return
	}
	state.draining = true
	image_tls_lock.unlock()
	// Pop before calling. Reentrant registrations go at the top and run next,
	// without a pthread destructor-iteration limit or a lock around app code.
	for {
		image_tls_lock.lock()
		if state.destructors.len == 0 {
			state.draining = false
			image_tls_lock.unlock()
			return
		}
		destructor := state.destructors.pop()
		image_tls_lock.unlock()
		destructor.function(destructor.argument)
	}
}

fn image_tls_finalize_current() {
	image_tls_lock.lock()
	if image_runtime == unsafe { nil } || !image_runtime.tls_active {
		image_tls_lock.unlock()
		return
	}
	pointer := C.pthread_getspecific(image_runtime.tls_key)
	image_tls_lock.unlock()
	if pointer != unsafe { nil } {
		mut state := unsafe { &ImageTlsThread(pointer) }
		image_tls_drain(mut state)
	}
}

fn image_tls_thread_free(state &ImageTlsThread) {
	for block in state.blocks { C.free(block.bytes) }
	unsafe {
		state.blocks.free()
		state.destructors.free()
		free(state)
	}
}

fn image_tls_thread_destroy(pointer voidptr) {
	if pointer == unsafe { nil } { return }
	mut state := unsafe { &ImageTlsThread(pointer) }
	mut runtime := state.runtime
	// pthread clears a key before its destructor. Restore it so callbacks see
	// the same bytes and can append to this thread's existing destructor stack.
	if C.pthread_setspecific(runtime.tls_key, pointer) != 0 {
		panic('iOS: cannot restore application TLS during destruction')
	}
	image_tls_drain(mut state)
	if C.pthread_setspecific(runtime.tls_key, unsafe { nil }) != 0 {
		panic('iOS: cannot clear application TLS')
	}
	image_tls_lock.lock()
	if state.previous == unsafe { nil } {
		runtime.tls_owners = state.next
	} else {
		state.previous.next = state.next
	}
	if state.next != unsafe { nil } { state.next.previous = state.previous }
	runtime.tls_threads--
	image_tls_thread_free(state)
	image_tls_lock.unlock()
}

// Check before destroying Objective-C/framework state, while a foreign owner's
// callback would still be safe. Workers must finish before execute() returns.
fn image_tls_require_current() {
	image_tls_lock.lock()
	defer { image_tls_lock.unlock() }
	if image_runtime == unsafe { nil } || !image_runtime.tls_active { return }
	pointer := C.pthread_getspecific(image_runtime.tls_key)
	owned := if pointer == unsafe { nil } { u64(0) } else { u64(1) }
	if image_runtime.tls_threads != owned {
		panic('iOS: active thread-local owner at image shutdown')
	}
}

fn image_tls_stop() {
	image_tls_lock.lock()
	defer { image_tls_lock.unlock() }
	if !image_runtime.tls_active { return }
	pointer := C.pthread_getspecific(image_runtime.tls_key)
	owned := if pointer == unsafe { nil } { u64(0) } else { u64(1) }
	if image_runtime.tls_threads != owned {
		panic('iOS: active thread-local owner at image shutdown')
	}
	if pointer != unsafe { nil } {
		state := unsafe { &ImageTlsThread(pointer) }
		if state.draining || state.destructors.len != 0 {
			panic('iOS: thread-local destructors remain after application finalization')
		}
	}
	image_runtime.tls_closing = true
	if C.pthread_setspecific(image_runtime.tls_key, unsafe { nil }) != 0
		|| C.pthread_key_delete(image_runtime.tls_key) != 0 {
		panic('iOS: cannot retire application TLS key')
	}
	image_runtime.tls_active = false
	if pointer != unsafe { nil } { image_tls_thread_free(unsafe { &ImageTlsThread(pointer) }) }
	image_runtime.tls_threads = 0
	image_runtime.tls_owners = unsafe { nil }
}

// The atfork dispatcher acquires this gate after application prepare handlers
// and releases it before parent/child handlers. Every ownership-list or array
// mutation shares it, so the child can discard vanished owners without calling
// their destructors or following a partially reallocated buffer.
fn image_tls_fork_prepare() { image_tls_lock.lock() }

fn image_tls_fork_complete(child bool) {
	if child && image_runtime != unsafe { nil } && image_runtime.tls_active {
		mut current := unsafe { &ImageTlsThread(C.pthread_getspecific(image_runtime.tls_key)) }
		mut owner := image_runtime.tls_owners
		for owner != unsafe { nil } {
			next := owner.next
			if u64(owner) != u64(current) { image_tls_thread_free(owner) }
			owner = next
		}
		image_runtime.tls_owners = current
		image_runtime.tls_threads = if current == unsafe { nil } { u64(0) } else { u64(1) }
		if current != unsafe { nil } {
			current.previous = unsafe { nil }
			current.next = unsafe { nil }
		}
	}
	image_tls_lock.unlock()
}
