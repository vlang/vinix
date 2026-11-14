// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module file

import klock
import gpu.agx.gpu

__global closing_lock klock.Lock
__global closing_head &GpuFile = unsafe { nil }
__global closing_tail &GpuFile = unsafe { nil }
__global closing_count = u64(0)
__global closing_reaper_active = false

fn enqueue_closing_file(data voidptr) {
	retain_closing_file(unsafe { &GpuFile(data) })
}

fn retire_closing_file(file &GpuFile) {
	if manager := gpu.get_global_manager() {
		mut gpu_manager := unsafe { manager }
		if gpu_manager.queue_file_retirement(enqueue_closing_file, voidptr(file)) { return }
	}
	// No worker can exit between a failed close and registration: either
	// registration held its manager lock before stop, or stop has completed
	// and released all GPU references before this synchronous retry.
	mut owned := unsafe { file }
	if owned.close() { unsafe { free(voidptr(owned)) } } else { retain_closing_file(owned) }
}

fn retain_closing_file(file &GpuFile) {
	closing_lock.acquire()
	mut owned := unsafe { file }
	assert !owned.closing_queued
	owned.closing_queued = true
	owned.closing_next = unsafe { nil }
	if closing_tail != unsafe { nil } {
		closing_tail.closing_next = owned
	} else {
		closing_head = owned
	}
	closing_tail = owned
	closing_count++
	closing_lock.release()
}

// Called outside GpuManager's lock, after completion callbacks or firmware
// shutdown. close() acquires the file lock before taking the manager lock.
// One bounded pass retries each previously retained file at most once.
pub fn reap_closed_files() {
	closing_lock.acquire()
	if closing_reaper_active || closing_head == unsafe { nil } {
		closing_lock.release()
		return
	}
	closing_reaper_active = true
	count := closing_count
	closing_lock.release()
	for i := u64(0); i < count; i++ {
		closing_lock.acquire()
		mut file := unsafe { closing_head }
		assert file != unsafe { nil } && closing_count != 0
		closing_head = file.closing_next
		if closing_head == unsafe { nil } { closing_tail = unsafe { nil } }
		file.closing_next = unsafe { nil }
		file.closing_queued = false
		closing_count--
		closing_lock.release()
		mut owned := unsafe { file }
		if owned.close() {
			unsafe { free(voidptr(owned)) }
		} else {
			retain_closing_file(owned)
		}
	}
	closing_lock.acquire()
	closing_reaper_active = false
	closing_lock.release()
}
