// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module file

import drm.syncobj
import errno
import event
import gpu.agx.gpu
import proc
import time

__global interrupt_gate_wait = false
__global gate_slot_attempts = 0

fn resume_queue_submitter() {
	mut manager := gpu.get_global_manager() or { panic('manager') }
	assert !waiting_file.lock.is_held() && !manager.lock.is_held()
	assert uat_mgr.acquire_attempts == gate_slot_attempts && uat_mgr.lease_count == 0
	assert manager.prepares == 0 && pending_count == 0 && time.armed() == 1
	mut queue := unsafe { waiting_file.g13_queues[0].resources }
	waiting_file.lock.acquire()
	assert queue.file_references == 2 && !queue.submission_gate.try_enter()
	waiting_file.lock.release()
	if interrupt_gate_wait {
		mut task := proc.current_thread()
		task.pending = 1
		return
	}
	// The lead ioctl on queue 1 has released the file lock for a slot.
	// The worker and a submission on queue 2 can run before it resumes.
	other := output()
	assert submit_slot_wait_packet(mut waiting_file, 2, other) == 0
	service_file_work()
	manager.finish_compute(0)
	service_file_work()
	assert syncobj.is_signaled(fence(other)) && queue.file_references == 2
	waiting_file.lock.acquire()
	queue.submission_gate.leave()
	queue.release_file_reference()
	waiting_file.lock.release()
}

fn check_queue_admission() {
	for modern in [false, true]! {
		for interrupted in [false, true]! {
			gpu.reset()
			mut file := new_file()
			mut manager := gpu.get_global_manager() or { panic('manager') }
			mut queue := unsafe { file.g13_queues[0].resources }
			mut task := proc.current_thread()
			out := output()
			previous := syncobj.new_fence(77, 1)
			syncobj.replace_fence(out, previous)
			file.lock.acquire()
			queue.retain_file_reference()
			assert queue.submission_gate.try_enter()
			file.lock.release()
			waiting_file = file
			interrupt_gate_wait = interrupted
			gate_slot_attempts = uat_mgr.acquire_attempts
			event.before_wait(resume_queue_submitter, false)
			code := if modern {
				submit_slot_wait_packet(mut file, 1, out)
			} else {
				submit(mut file, 1, false, unsafe { nil }, out, false)
			}
			assert time.armed() == 0 && !file.lock.is_held() && !manager.lock.is_held()
			if interrupted {
				assert code == -int(errno.erestartsys)
				assert voidptr(fence(out)) == voidptr(previous) && queue.file_references == 1
				assert uat_mgr.acquire_attempts == gate_slot_attempts && manager.prepares == 0
				task.pending = 0
				file.lock.acquire()
				assert !queue.submission_gate.try_enter(), 'interrupted contender left the leader in place'
				queue.submission_gate.leave()
				queue.release_file_reference()
				file.lock.release()
			} else {
				assert code == 0 && manager.prepares == 2
				assert uat_mgr.acquire_attempts == gate_slot_attempts + 2
				assert queue.file_references == 1 && voidptr(fence(out)) != voidptr(previous)
				service_file_work()
				manager.finish_compute(1)
				service_file_work()
				assert syncobj.is_signaled(fence(out))
			}
			assert_drained(file)
			waiting_file = unsafe { nil }
		}
	}
	println('G13 queue admission: both ABIs wait before binding, independent queue work retires, interrupted contenders leave the owner in place')
}
