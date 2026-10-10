// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn test_mach_threads_macho_unload() {
	path := os.getenv('VINIX_IOS_PTHREAD_MACH_FIXTURE')
	if path == '' { return }
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	image := macho.parse(data)!
	defer { module_image_free(image) }
	for _ in 0 .. 2 {
		assert execute(image, [path])! == 0
		assert ios_runtime.live == 0
		assert system_data == unsafe { nil }
	}
	// Permanent native fork callbacks must tolerate the namespace's teardown.
	child := C.ios_fork()
	assert child >= 0
	if child == 0 { C._exit(0) }
	mut status := i32(-1)
	assert C.ios_waitpid(child, unsafe { &status }, 0) == child
	assert status == 0
}

fn test_mach_threads_retired_namespace_lifetime() {
	// Exercise V's allocation and retirement paths under the host sanitizers;
	// the host Mach-O fixture uses actual native Mac ports instead of this list.
	system_data_start()!
	defer { system_data_stop() }
	mut head := unsafe { &MachThreadPort(C.calloc(1, sizeof(MachThreadPort))) }
	mut middle := unsafe { &MachThreadPort(C.calloc(1, sizeof(MachThreadPort))) }
	mut tail := unsafe { &MachThreadPort(C.calloc(1, sizeof(MachThreadPort))) }
	assert head != unsafe { nil } && middle != unsafe { nil } && tail != unsafe { nil }
	unsafe {
		*head = MachThreadPort{name: 0x103, next: middle, refs: 1, borrowed: true}
		*middle = MachThreadPort{name: 0x203, next: tail, refs: 2, borrowed: true}
		*tail = MachThreadPort{name: 0x303, refs: 1, borrowed: true}
	}
	system_data.thread_ports = head
	mach_thread_retire(mut head)
	mach_thread_retire(mut middle)
	mach_thread_retire(mut tail)
	mach_threads_refresh()
	assert mach_thread_find(0x103) == unsafe { nil }
	assert mach_thread_find(0x303) == unsafe { nil }
	assert system_data.thread_ports == middle && middle.refs == 1 && middle.dead
	mach_threads_stop()
	assert system_data.thread_ports == unsafe { nil }
	mach_threads_stop()
}
