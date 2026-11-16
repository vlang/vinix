// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm.ioctl
import gpu.agx.fw
import gpu.agx.gpu
import gpu.agx.mmu
import gpu.agx.pgtable
import gpu.agx.workqueue
import klock

fn queue_request(priority u32, caps u32) ioctl.DrmAsahiQueueCreate {
	return ioctl.DrmAsahiQueueCreate{ vm_id: 1, priority: priority, queue_caps: caps }
}

fn priority_word(value &fw.G13WorkQueuePriority, band u32, compute bool) {
	assert value.value_0 == if compute { u32(0) } else { band }
	assert value.value_4 == band
	assert value.mask == if band == 2 { u64(0xffff000000000000) } else { u64(0) }
	assert value.value_10 == 0 && value.value_14 == 0
	assert value.value_18 == if compute { u32(1) } else { band }
}

fn close_priority_file(mut file GpuFile) {
	// Production retains successful logical queue metadata after destroy.
	// Fixture-only cleanup runs after close proves no borrower remains.
	queues := file.queues.clone()
	assert file.close()
	for queue in queues { unsafe { free(queue) } }
	unsafe { queues.free() }
}

fn check_queue_priorities() {
	gpu.set_running(true)
	assert sizeof(fw.G13WorkQueuePriority) == 0x1c
	for _ in 0 .. 100 {
		mut pt := pgtable.UatPgtable{}
		mut vm := mmu.UatContext{ id: 1, identity: mmu.new_identity(), pgtable: &pt }
		mut file := GpuFile{ vms: [&vm] }
		file.queues.flags |= .noslices
		file.g13_queues.flags |= .noslices
		for priority in [ioctl.asahi_priority_high, ioctl.asahi_priority_realtime, u32(4), ~u32(0)]! {
			mut request := queue_request(priority, ioctl.asahi_queue_cap_render)
			request.queue_id = 73
			host_before, gpu_before := workqueue.creation_attempts(), gpu.queue_creates()
			assert file.ioctl_queue_create(&request) == -22
			assert request.queue_id == 73 && file.next_queue_id == 1
			assert workqueue.creation_attempts() == host_before && gpu.queue_creates() == gpu_before
			assert file.queues.len == 0 && file.g13_queues.len == 0 && !file.lock.is_held()
		}
		priorities := [ioctl.asahi_priority_low, ioctl.asahi_priority_medium]!
		bands := [u32(3), 2]!
		caps := [ioctl.asahi_queue_cap_render, ioctl.asahi_queue_cap_compute,
			ioctl.asahi_queue_cap_render | ioctl.asahi_queue_cap_compute]!
		masks := [u32(3), 4, 7]!
		for which, priority in priorities {
			for kind, capability in caps {
				mut request := queue_request(priority, capability)
				assert file.ioctl_queue_create(&request) == 0
				assert request.queue_id == u32(which * 3 + kind + 1)
				logical := file.queues.last()
				resources := file.g13_queues.last().resources
				assert logical.priority == bands[which] && resources.priority == bands[which]
				assert logical.vm_id == 1 && logical.caps == capability
				assert resources.channel_mask == masks[kind] && resources.vm_address == u64(&vm)
				if masks[kind] & 1 != 0 { priority_word(&resources.vertex, bands[which], false) }
				if masks[kind] & 2 != 0 { priority_word(&resources.fragment, bands[which], false) }
				if masks[kind] & 4 != 0 { priority_word(&resources.compute, bands[which], true) }
				assert !file.lock.is_held()
			}
		}
		assert workqueue.active() == 6 && gpu.active_queues() == 6
		destroy := ioctl.DrmAsahiVmDestroy{ vm_id: 1 }
		assert file.ioctl_vm_destroy(&destroy) == 0 && !vm.destroyed
		assert file.ioctl_vm_destroy(&destroy) == -2
		close_priority_file(mut file)
		assert vm.destroyed
		assert workqueue.active() == 0 && gpu.active_queues() == 0
	}
	// Failed host construction and failed GPU preparation leave no installed
	// queue, release the mutation lock, and allow a later successful retry.
	mut failed_pt := pgtable.UatPgtable{}
	mut failed_vm := mmu.UatContext{ id: 1, pgtable: &failed_pt }
	mut failed := GpuFile{ vms: [&failed_vm] }
	failed.queues.flags |= .noslices
	failed.g13_queues.flags |= .noslices
	mut request := queue_request(ioctl.asahi_priority_medium, ioctl.asahi_queue_cap_compute)
	workqueue.fail_next()
	assert failed.ioctl_queue_create(&request) == -12 && request.queue_id == 0
	assert workqueue.active() == 0 && gpu.active_queues() == 0 && !failed.lock.is_held()
	gpu.fail_queue()
	assert failed.ioctl_queue_create(&request) == -12 && request.queue_id == 0
	assert workqueue.active() == 0 && gpu.active_queues() == 0 && !failed.lock.is_held()
	assert failed.ioctl_queue_create(&request) == 0 && request.queue_id != 0
	close_priority_file(mut failed)
	assert failed_vm.destroyed
	assert workqueue.active() == 0 && gpu.active_queues() == 0

	// A failed firmware invalidation retains a partially built GPU graph.
	// No userspace queue is installed, but VM destroy must still see its pin.
	mut retained_pt := pgtable.UatPgtable{}
	mut retained_vm := mmu.UatContext{ id: 1, pgtable: &retained_pt }
	mut retained := GpuFile{ vms: [&retained_vm] }
	retained.g13_queues.flags |= .noslices
	request = queue_request(ioctl.asahi_priority_low, ioctl.asahi_queue_cap_render)
	gpu.quarantine_queue()
	assert retained.ioctl_queue_create(&request) == -12 && request.queue_id == 0
	assert retained.queues.len == 0 && retained.g13_queues.len == 1
	assert workqueue.active() == 0 && gpu.active_queues() == 1
	retained.next_queue_id = retained.g13_queues[0].queue_id
	skipped_id := retained.allocate_queue_id_locked() or { panic('retained ID reservation') }
	assert skipped_id == 2
	destroy_retained := ioctl.DrmAsahiVmDestroy{ vm_id: 1 }
	assert retained.ioctl_vm_destroy(&destroy_retained) == 0 && !retained_vm.destroyed
	assert retained.ioctl_vm_destroy(&destroy_retained) == -2
	for _ in 0 .. 2 {
		assert !retained.close() && !retained_vm.destroyed
		assert retained.g13_queues.len == 1 && gpu.active_queues() == 1
		assert !retained.lock.is_held()
	}
	assert retained.close() && retained_vm.destroyed && gpu.active_queues() == 0

	// Destruction wins before queue creation takes file.lock. No borrowed VM
	// pointer may reach either constructor after that destruction.
	mut race_pt := pgtable.UatPgtable{}
	mut race_vm := mmu.UatContext{ id: 1, pgtable: &race_pt }
	mut raced := GpuFile{ vms: [&race_vm] }
	destroying_vm_file = &raced
	klock.before_once(unsafe { &raced.lock }, destroy_before_bind)
	request = queue_request(ioctl.asahi_priority_medium, ioctl.asahi_queue_cap_render)
	host_before, gpu_before := workqueue.creation_attempts(), gpu.queue_creates()
	assert raced.ioctl_queue_create(&request) == -2 && request.queue_id == 0
	assert race_vm.destroyed && raced.queues.len == 0 && raced.g13_queues.len == 0
	assert workqueue.creation_attempts() == host_before && gpu.queue_creates() == gpu_before
	destroying_vm_file = unsafe { nil }
	assert raced.close()
	println('G13 queue priority: 600 LOW/MEDIUM render/compute/mixed queues select bands3/2 and exact firmware defaults; HIGH/REALTIME/unknown refuse before allocation; host/GPU failures, quarantined failed-create ownership and VM-destroy lock race pass')
}
