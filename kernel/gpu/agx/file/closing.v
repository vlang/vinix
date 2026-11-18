// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module file

import klock

__global closing_lock klock.Lock
__global closing_head &GpuFile = unsafe { nil }
__global closing_tail &GpuFile = unsafe { nil }
__global closing_count = u64(0)
__global closing_reaper_active = false
__global closing_reaper_requested = false

fn enqueue_closing_file(data voidptr) {
	retain_closing_file(unsafe { &GpuFile(data) }, true)
}

fn retire_closing_file(file &GpuFile) {
	mut gpu_manager := unsafe { file.registration_manager }
	if gpu_manager != unsafe { nil } {
		if gpu_manager.queue_file_retirement(enqueue_closing_file, voidptr(file)) { return }
	}
	// The stopped worker may already have passed its final reap. Register
	// the file before retrying close so a concurrent reap can see it.
	retain_closing_file(file, true)
	reap_closed_files()
}

fn retain_closing_file(file &GpuFile, new_owner bool) {
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
	if new_owner && closing_reaper_active { closing_reaper_requested = true }
	closing_lock.release()
}

// Called outside GpuManager's lock, after completion callbacks or firmware
// shutdown. close() acquires the file lock before taking the manager lock.
// Each pass retries the files present at its start. A new owner or a poll
// that overlaps a pass requests another. A busy-file retry stays passive.
pub fn reap_closed_files() {
	closing_lock.acquire()
	if closing_reaper_active {
		closing_reaper_requested = true
		closing_lock.release()
		return
	}
	if closing_head == unsafe { nil } {
		closing_lock.release()
		return
	}
	closing_reaper_active = true
	for {
		count := closing_count
		closing_reaper_requested = false
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
			if file.close() {
				unsafe { free(voidptr(file)) }
			} else {
				retain_closing_file(file, false)
			}
		}
		closing_lock.acquire()
		if !closing_reaper_requested {
			closing_reaper_active = false
			closing_lock.release()
			return
		}
	}
}
