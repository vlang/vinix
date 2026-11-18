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
__global wait_on_vm_gate = false

fn resume_queue_submitter() {
	mut manager := gpu.get_global_manager() or { panic('manager') }
	assert !waiting_file.lock.is_held() && !manager.lock.is_held()
	assert uat_mgr.acquire_attempts == gate_slot_attempts && uat_mgr.lease_count == 0
	assert manager.prepares == 0 && pending_count == 0 && time.armed() == 1
	mut queue := unsafe { waiting_file.g13_queues[0].resources }
	waiting_file.lock.acquire()
	assert !queue.submission_gate.try_enter()
	if wait_on_vm_gate {
		assert queue.file_references == 1 && waiting_file.g13_queues[1].resources.has_file_references()
		assert !waiting_file.vm.binding_gate.try_enter()
	} else {
		assert queue.file_references == 2
	}
	waiting_file.lock.release()
	if interrupt_gate_wait {
		mut task := proc.current_thread()
		task.pending = 1
		return
	}
	// The worker and an independent submission can run before the wait
	// ends. A held VM gate still permits a submission on another VM.
	mut independent_file := if wait_on_vm_gate { new_file() } else { waiting_file }
	expected_refs := if wait_on_vm_gate { u64(1) } else { u64(2) }
	other := output()
	assert submit_slot_wait_packet(mut independent_file, 2, other) == 0
	service_file_work()
	manager.finish_compute(0)
	service_file_work()
	assert syncobj.is_signaled(fence(other)) && queue.file_references == expected_refs
	waiting_file.lock.acquire()
	if wait_on_vm_gate { waiting_file.vm.binding_gate.leave() }
	queue.submission_gate.leave()
	queue.release_file_reference()
	waiting_file.lock.release()
}

fn check_queue_admission() {
	for vm_scope in [false, true]! {
		check_admission_scope(vm_scope)
	}
	println('G13 queue and VM admission: both ABIs wait before binding, independent work retires, and interruption preserves the active owner')
}

fn check_admission_scope(vm_scope bool) {
	queue_id := if vm_scope { u32(2) } else { u32(1) }
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
			if vm_scope { assert file.vm.binding_gate.try_enter() }
			file.lock.release()
			waiting_file = file
			wait_on_vm_gate = vm_scope
			interrupt_gate_wait = interrupted
			gate_slot_attempts = uat_mgr.acquire_attempts
			event.before_wait(resume_queue_submitter, false)
			code := if modern {
				submit_slot_wait_packet(mut file, queue_id, out)
			} else {
				submit(mut file, queue_id, false, unsafe { nil }, out, false)
			}
			assert time.armed() == 0 && !file.lock.is_held() && !manager.lock.is_held()
			if interrupted {
				assert code == -int(errno.erestartsys)
				assert voidptr(fence(out)) == voidptr(previous) && queue.file_references == 1
				assert uat_mgr.acquire_attempts == gate_slot_attempts && manager.prepares == 0
				task.pending = 0
				file.lock.acquire()
				assert !queue.submission_gate.try_enter(), 'interrupted contender left the leader in place'
				if vm_scope {
					assert !file.vm.binding_gate.try_enter(), 'the lead VM binder still owns admission'
					file.vm.binding_gate.leave()
				}
				queue.submission_gate.leave()
				queue.release_file_reference()
				file.lock.release()
			} else {
				assert code == 0 && manager.prepares == 2
				assert uat_mgr.acquire_attempts == gate_slot_attempts + 2
				assert file.g13_queues[queue_id - 1].resources.file_references == 1
				assert voidptr(fence(out)) != voidptr(previous)
				service_file_work()
				manager.finish_compute(1)
				service_file_work()
				assert syncobj.is_signaled(fence(out))
			}
			assert_drained(file)
			waiting_file = unsafe { nil }
		}
	}
}
