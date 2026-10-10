// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os
import time

struct ForkStopProbe {
mut:
	ready [2]i32
	release [2]i32
	stop_state u64
	result i32
}

__global fork_stop_probe = unsafe { &ForkStopProbe(nil) }

fn fork_stop_prepare() {
	mut byte := u8(1)
	assert C.write(fork_stop_probe.ready[1], unsafe { &byte }, 1) == 1
	assert C.read(fork_stop_probe.release[0], unsafe { &byte }, 1) == 1
}

fn fork_stop_worker(context voidptr) voidptr {
	mut probe := unsafe { &ForkStopProbe(context) }
	pid := C.ios_fork()
	if pid == 0 { C._exit(0) }
	mut status := i32(-1)
	probe.result = if pid > 0 && C.ios_waitpid(pid, unsafe { &status }, 0) == pid && status == 0 { i32(0) } else { i32(-1) }
	return unsafe { nil }
}

fn fork_stop_stopper(context voidptr) voidptr {
	mut probe := unsafe { &ForkStopProbe(context) }
	C.ios_store_pointer(unsafe { &probe.stop_state }, 1)
	image_atfork_stop()
	C.ios_store_pointer(unsafe { &probe.stop_state }, 2)
	return unsafe { nil }
}

fn test_atfork_stop_waits_for_real_fork() {
	mut probe := ForkStopProbe{}
	assert C.pipe(unsafe { &probe.ready[0] }) == 0
	defer { C.close(probe.ready[0]); C.close(probe.ready[1]) }
	assert C.pipe(unsafe { &probe.release[0] }) == 0
	defer { C.close(probe.release[0]); C.close(probe.release[1]) }
	fork_stop_probe = unsafe { &probe }
	defer { fork_stop_probe = unsafe { nil } }
	image_atfork_start()!
	assert darwin_pthread_atfork(fork_stop_prepare, unsafe { nil }, unsafe { nil }) == 0
	mut worker := u64(0)
	assert C.pthread_create(unsafe { &worker }, unsafe { nil }, unsafe { voidptr(fork_stop_worker) }, unsafe { &probe }) == 0
	mut byte := u8(0)
	assert C.read(probe.ready[0], unsafe { &byte }, 1) == 1
	mut stopper := u64(0)
	if C.pthread_create(unsafe { &stopper }, unsafe { nil }, unsafe { voidptr(fork_stop_stopper) }, unsafe { &probe }) != 0 {
		C.write(probe.release[1], unsafe { &byte }, 1)
		C.pthread_join(unsafe { voidptr(worker) }, unsafe { nil })
		image_atfork_stop()
		assert false
		return
	}
	for C.ios_load_pointer(unsafe { &probe.stop_state }) == 0 { time.sleep(time.millisecond) }
	assert C.ios_load_pointer(unsafe { &probe.stop_state }) == 1
	assert C.write(probe.release[1], unsafe { &byte }, 1) == 1
	assert C.pthread_join(unsafe { voidptr(worker) }, unsafe { nil }) == 0
	assert C.pthread_join(unsafe { voidptr(stopper) }, unsafe { nil }) == 0
	assert probe.result == 0
	assert C.ios_load_pointer(unsafe { &probe.stop_state }) == 2
	assert image_fork_state.head == unsafe { nil }
}

fn test_atfork_macho_unload() {
	path := os.getenv('VINIX_IOS_ATFORK_FIXTURE')
	if path == '' { return }
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	image := macho.parse(data)!
	defer { module_image_free(image) }
	for _ in 0 .. 2 {
		assert execute(image, [path, '--adapter'])! == 0
		assert ios_runtime.live == 0
		assert !image_fork_state.active
		assert image_fork_state.head == unsafe { nil }
		assert image_fork_state.tail == unsafe { nil }
		// Real libc fork after unmapping must not call a stale image callback.
		pid := C.ios_fork()
		if pid == 0 { C._exit(0) }
		assert pid > 0
		mut status := i32(-1)
		assert C.ios_waitpid(pid, unsafe { &status }, 0) == pid
		assert status == 0
	}
}
