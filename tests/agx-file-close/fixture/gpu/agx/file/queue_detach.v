module file

import drm
import drm.ioctl
import gpu.agx.gpu
import gpu.agx.mmu
import gpu.agx.workqueue

__global reaping_file &GpuFile = unsafe { nil }
__global queue_release_checks int

fn check_registry_pin(_ &gpu.G13QueueResources) {
	assert file_map_lock.is_held() && reaping_file.lock.is_held()
	assert reaping_file.queues.len == 1 && reaping_file.g13_queues.len == 1
	assert reaping_file.queues[0].detached
	queue_release_checks++
}

fn (mut file GpuFile) submission_queue_exists(id u32) bool {
	captured := file.capture_submission_queue(id) or { return false }
	release_submission_queue(captured)
	return true
}

fn check_detached_queues() {
	mut cases := 0
	for cycle in 0 .. 100 {
		for pins in [u64(0), 1, 3] {
			for failures in 0 .. 4 {
				for available in [false, true] {
					mut queue := workqueue.WorkQueue{id: 7, vm_id: 1, caps: ioctl.asahi_queue_cap_compute}
					mut resource := gpu.G13QueueResources{queue_id: 7, failures: failures}
					mut vm := mmu.UatContext{id: 1, vm_id: 1}
					mut file := GpuFile{
						queues: [unsafe { &queue }]
						g13_queues: [G13QueueOwnership{queue_id: 7, vm_id: 1, resources: unsafe { &resource }}]
						vms: [unsafe { &vm }]
					}
					for _ in 0 .. int(pins) { resource.retain_file_reference() }
					vm.inflight = pins
					key := u64(0x1000_0000 + cycle)
					file_map[key] = unsafe { &file }
					gpu.available(available)
					assert file.submission_queue_exists(7)
					invalid := ioctl.DrmAsahiQueueDestroy{queue_id: 7, pad: 1}
					assert file.ioctl_queue_destroy(&invalid) == -22 && !queue.detached
					request := ioctl.DrmAsahiQueueDestroy{queue_id: 7}
					assert file.ioctl_queue_destroy(&request) == 0
					assert queue.detached && !file.submission_queue_exists(7)
					assert file.ioctl_queue_destroy(&request) == -2
					if pins != 0 {
						assert !queue.destroyed && !resource.released && resource.calls == 0
						assert file.queues.len == 1 && file.g13_queues.len == 1
					}
					// A detached but retained ID cannot alias a new queue graph.
					file.next_queue_id = 7
					id := file.allocate_queue_id_locked() or { panic('queue ID') }
					assert id == if resource.released { u32(7) } else { u32(8) }
					gpu.available(true)
					if pins != 0 {
						before := resource.calls
						reap_open_detached_g13_queues()
						assert resource.calls == before && !queue.destroyed && !vm.destroyed
					}
					// A callback ending is insufficient while the aggregate pin
					// remains; the last worker pass can retire only after zero.
					for _ in 0 .. int(pins) { resource.release_file_reference() }
					// Unrelated accepted work in the same VM must not retain this
					// queue after its own last submission reference ends.
					vm.inflight = 7
					if !resource.released {
						reaping_file = unsafe { &file }
						gpu.watch_queue_release(check_registry_pin)
						for _ in 0 .. failures + 2 { reap_open_detached_g13_queues() }
						gpu.watch_queue_release(unsafe { nil })
					}
					assert queue.destroyed && resource.released && !vm.destroyed
					assert file.queues.len == 0 && file.g13_queues.len == 0
					assert !file_map_lock.is_held() && !file.lock.is_held()
					vm.inflight = 0
					file_map.delete(key)
					assert file.close() && vm.destroyed
					cases++
				}
			}
		}
	}
	// A Handle close removes the registry entry. The ordinary closing list
	// then retains the exact same hidden owner until aggregate retirement.
	mut queue := workqueue.WorkQueue{id: 9, vm_id: 1}
	mut resource := gpu.G13QueueResources{queue_id: 9, failures: 1}
	mut vm := mmu.UatContext{id: 1, vm_id: 1}
	mut closing := &GpuFile{queues: [unsafe { &queue }], g13_queues: [G13QueueOwnership{queue_id: 9, vm_id: 1, resources: unsafe { &resource }}], vms: [unsafe { &vm }]}
	vm.inflight = 1
	resource.retain_file_reference()
	file_map[99] = closing
	assert closing.ioctl_queue_destroy(&ioctl.DrmAsahiQueueDestroy{queue_id: 9}) == 0
	device := drm.DrmDevice{}
	release_handle(&device, voidptr(u64(99)))
	assert 99 !in file_map && closing_count == 1 && !queue.destroyed
	vm.inflight = 0
	resource.release_file_reference()
	reap_closed_files()
	assert closing_count == 1 && !queue.destroyed && !vm.destroyed
	reap_closed_files()
	assert closing_count == 0 && queue.destroyed && vm.destroyed && resource.released
	assert queue_release_checks > 0 && file_map.len == 0
	println('G13 queue detach: ${cases} namespace/retirement cases, queue-specific references, unrelated VM pins, unavailable manager, invalidation retry, ID isolation, registry/file locking and Handle-close transfer passed')
}
