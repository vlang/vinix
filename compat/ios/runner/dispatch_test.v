// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os
import time

fn test_darwin_dispatch_macho() {
	path := os.getenv('VINIX_IOS_DISPATCH_FIXTURE')
	if path == '' { return }
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	image := macho.parse(data)!
	defer { module_image_free(image) }
	for _ in 0 .. 2 {
		assert execute(image, [path])! == 0
		assert ios_runtime.live == 0
		assert ios_runtime.block_refs.len == 0
		assert dispatch_runtime == unsafe { nil }
	}
}

struct DispatchMainProbe {
mut:
	turns int
	delayed int
	deadline u64
	thread u64
}

fn dispatch_probe_nested(context voidptr) {
	mut probe := unsafe { &DispatchMainProbe(context) }
	assert u64(C.pthread_self()) == probe.thread
	assert probe.turns == 1
	probe.turns++
}

fn dispatch_probe_first(context voidptr) {
	mut probe := unsafe { &DispatchMainProbe(context) }
	assert u64(C.pthread_self()) == probe.thread
	assert probe.turns == 0
	probe.turns++
	darwin_dispatch_async_f(darwin_dispatch_get_main_queue(), context, dispatch_probe_nested)
}

fn dispatch_probe_delayed(context voidptr) {
	mut probe := unsafe { &DispatchMainProbe(context) }
	assert u64(C.pthread_self()) == probe.thread
	assert dispatch_remaining(probe.deadline) == 0
	probe.delayed++
}

fn test_dispatch_main_deadline_and_turns() {
	objc_start()
	system_data_start()!
	defer { objc_stop(); system_data_stop() }
	mut probe := DispatchMainProbe{thread: u64(C.pthread_self()), deadline: darwin_dispatch_walltime(unsafe { nil }, 50_000_000)}
	queue := darwin_dispatch_get_main_queue()
	darwin_dispatch_after_f(probe.deadline, queue, unsafe { &probe }, dispatch_probe_delayed)
	darwin_dispatch_async_f(queue, unsafe { &probe }, dispatch_probe_first)
	assert dispatch_main_drain()
	assert probe.turns == 1 && probe.delayed == 0
	assert dispatch_main_drain()
	assert probe.turns == 2 && probe.delayed == 0
	assert !dispatch_main_drain()
	limit := darwin_mach_absolute_time() + 2_000_000_000
	for probe.delayed == 0 {
		assert darwin_mach_absolute_time() < limit
		time.sleep(time.millisecond)
		dispatch_main_drain()
	}
	assert probe.delayed == 1
	assert !dispatch_main_drain()
	// This callback borrows a stack context. Stop must discard it before either
	// the context or the image can be freed, without reporting it as executed.
	darwin_dispatch_after_f(darwin_dispatch_time(0, 60_000_000_000), queue, unsafe { &probe }, dispatch_probe_delayed)
	dispatch_stop()
	assert probe.delayed == 1
}

struct DispatchSyncProbe {
mut:
	queue u64
	thread u64
	state u64
}

fn dispatch_probe_sync_callback(context voidptr) {
	mut probe := unsafe { &DispatchSyncProbe(context) }
	assert u64(C.pthread_self()) == probe.thread
	assert C.ios_load_pointer(unsafe { &probe.state }) == 1
	C.ios_store_pointer(unsafe { &probe.state }, 2)
}

fn dispatch_probe_sync_thread(context voidptr) voidptr {
	mut probe := unsafe { &DispatchSyncProbe(context) }
	C.ios_store_pointer(unsafe { &probe.state }, 1)
	darwin_dispatch_sync_f(probe.queue, context, dispatch_probe_sync_callback)
	assert C.ios_load_pointer(unsafe { &probe.state }) == 2
	C.ios_store_pointer(unsafe { &probe.state }, 3)
	return unsafe { nil }
}

fn test_dispatch_background_sync_to_main_target() {
	objc_start()
	system_data_start()!
	defer { objc_stop(); system_data_stop() }
	child := darwin_dispatch_queue_create_with_target(c'main.child', 0, darwin_dispatch_get_main_queue())
	mut probe := DispatchSyncProbe{thread: u64(C.pthread_self()), queue: child}
	mut handle := usize(0)
	assert C.pthread_create(unsafe { voidptr(&handle) }, unsafe { nil }, unsafe { voidptr(dispatch_probe_sync_thread) }, unsafe { &probe }) == 0
	limit := darwin_mach_absolute_time() + 2_000_000_000
	for C.ios_load_pointer(unsafe { &probe.state }) != 3 {
		assert darwin_mach_absolute_time() < limit
		dispatch_main_drain()
		time.sleep(time.millisecond)
	}
	assert C.pthread_join(unsafe { voidptr(handle) }, unsafe { nil }) == 0
	darwin_dispatch_release(child)
}
