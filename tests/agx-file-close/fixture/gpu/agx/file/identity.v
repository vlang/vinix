// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module file

import drm.ioctl
import gpu.agx.gpu
import gpu.agx.mmu
import gpu.agx.pgtable
import gpu.agx.workqueue

__global identity_cases = 0

fn identity_result(actual int, expected int) {
	assert actual == expected, 'identity lookup expected ${expected}, got ${actual}'
	identity_cases++
}

fn check_identity_lookups() {
	gpu.set_running(true)
	for _ in 0 .. 200 {
		mut pt := pgtable.UatPgtable{}
		mut vm := mmu.UatContext{ id: 1, vm_id: 1, identity: mmu.new_identity(), pgtable: &pt }
		mut neighbor_vm := mmu.UatContext{ id: 2, vm_id: 2 }
		mut neighbor_queue := workqueue.WorkQueue{ id: 3, vm_id: 2 }
		mut neighbor := GpuFile{ vms: [unsafe { &neighbor_vm }], queues: [unsafe { &neighbor_queue }] }
		mut file := GpuFile{ vms: [unsafe { &vm }] }
		file.vms.flags |= .noslices; file.queues.flags |= .noslices; file.g13_queues.flags |= .noslices
		mut valid := queue_request(ioctl.asahi_priority_medium, ioctl.asahi_queue_cap_compute)
		identity_result(file.ioctl_queue_create(&valid), 0)
		assert valid.queue_id == 1
		logical := file.queues[0]
		resources := file.g13_queues[0].resources
		host_before, gpu_before := workqueue.creation_attempts(), gpu.queue_creates()
		for id in [u32(0), 2, 64, ~u32(0)]! {
			mut destroy := ioctl.DrmAsahiVmDestroy{ vm_id: id }
			identity_result(file.ioctl_vm_destroy(&destroy), -2)
			destroy.pad = 1; identity_result(file.ioctl_vm_destroy(&destroy), -22)
			destroy.pad = 0; destroy.extensions = 1; identity_result(file.ioctl_vm_destroy(&destroy), -22)
			mut create := queue_request(ioctl.asahi_priority_medium, ioctl.asahi_queue_cap_compute)
			create.vm_id = id; create.queue_id = 73
			identity_result(file.ioctl_queue_create(&create), -2)
			create.pad = 1; identity_result(file.ioctl_queue_create(&create), -22)
			create.pad = 0; create.flags = 1; identity_result(file.ioctl_queue_create(&create), -22)
			create.flags = 0; create.priority = ioctl.asahi_priority_high
			identity_result(file.ioctl_queue_create(&create), -22)
			assert create.queue_id == 73 && file.next_queue_id == 2
		}
		for id in [u32(0), 3, 64, ~u32(0)]! {
			mut destroy := ioctl.DrmAsahiQueueDestroy{ queue_id: id }
			identity_result(file.ioctl_queue_destroy(&destroy), -2)
			destroy.pad = 1; identity_result(file.ioctl_queue_destroy(&destroy), -22)
			destroy.pad = 0; destroy.extensions = 1; identity_result(file.ioctl_queue_destroy(&destroy), -22)
		}
		assert !file.lock.is_held() && !vm.destroyed && !neighbor_vm.destroyed
		assert workqueue.creation_attempts() == host_before && gpu.queue_creates() == gpu_before
		assert workqueue.active() == 1 && gpu.active_queues() == 1 && resources.calls == 0
		assert file.vms.len == 1 && file.queues.len == 1 && file.g13_queues.len == 1
		assert voidptr(file.queues[0]) == voidptr(logical) && voidptr(file.g13_queues[0].resources) == voidptr(resources)
		// Remove the name while the queue retains the physical context.
		destroy_vm := ioctl.DrmAsahiVmDestroy{ vm_id: 1 }
		identity_result(file.ioctl_vm_destroy(&destroy_vm), 0)
		assert !vm.destroyed && file.detached_vms[1]
		identity_result(file.ioctl_vm_destroy(&destroy_vm), -2)
		destroy_queue := ioctl.DrmAsahiQueueDestroy{ queue_id: valid.queue_id }
		identity_result(file.ioctl_queue_destroy(&destroy_queue), 0)
		identity_result(file.ioctl_queue_destroy(&destroy_queue), -2)
		identity_result(file.ioctl_vm_destroy(&destroy_vm), -2)
		identity_result(file.ioctl_queue_create(&valid), -2)
		assert vm.destroyed && !neighbor_vm.destroyed && resources.calls == 1
		assert workqueue.active() == 0 && gpu.active_queues() == 0 && !file.lock.is_held()
		// Successful logical metadata is retained by the kernel. Only the
		// fixture retires it here, after destroy removed every consumer.
		unsafe { free(logical) }
		assert file.close() && neighbor.close() && neighbor_vm.destroyed
		unsafe { file.vms.free(); file.queues.free(); file.g13_queues.free(); neighbor.vms.free(); neighbor.queues.free() }
	}
	println('AGX identity lookup: ${identity_cases} ioctl checks; ENOENT for missing/removed/foreign-file VM and queue identities, validation precedence, unchanged queue IDs and resource counts, detached VM owners, live neighbor preservation and repeated destruction passed')
}
