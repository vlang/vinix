// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm.ioctl
import drm.asahi
import gpu.agx.gpu
import gpu.agx.mmu
import gpu.agx.pgtable

__global orphan_reaping_file &GpuFile = unsafe { nil }
__global orphan_release_checks int

fn check_orphan_release_locks(_ &gpu.G13QueueResources) {
	assert file_map_lock.is_held() && orphan_reaping_file.lock.is_held()
	assert orphan_reaping_file.g13_queues.len == 2
	assert orphan_reaping_file.vms[0].inflight == 7
	orphan_release_checks++
}

fn check_stopped_constructor_adoption() {
	for _ in 0 .. 32 {
		for modern in [false, true]! {
			gpu.set_running(true)
			mut vm := mmu.UatContext{id: 1, vm_id: 1}
			mut file := GpuFile{vms: [&vm]}
			gpu.stop_on_next_queue_quarantine()
			if modern {
				request := asahi.QueueCreate{vm_id: 1, queue_id: 73}
				assert file.ioctl_modern_queue_create(&request) == -12 && request.queue_id == 73
			} else {
				mut request := queue_request(ioctl.asahi_priority_low, ioctl.asahi_queue_cap_render)
				request.queue_id = 73
				assert file.ioctl_queue_create(&request) == -12 && request.queue_id == 73
			}
			assert file.queues.len == 0 && file.g13_queues.len == 1,
				'the failed ioctl must adopt the record after the shutdown drain'
			record := file.g13_queues[0].resources
			assert record.released && C.__asan_address_is_poisoned(record) == 0
			assert file.ioctl_vm_destroy(&ioctl.DrmAsahiVmDestroy{vm_id: 1}) == 0
			assert !vm.destroyed
			file.lock.acquire()
			file.reap_orphaned_g13_queues_locked()
			file.reap_detached_vms_locked()
			file.lock.release()
			assert C.__asan_address_is_poisoned(record) != 0 && vm.destroyed
			assert file.close()
		}
	}
	gpu.set_running(true)
	println('G13 failed queue handoff: 64 legacy and modern shutdown cases adopt and reclaim the unpublished record')
}

fn check_orphaned_queues() {
	gpu.set_running(true)
	mut cases := 0
	for cycle in 0 .. 25 {
		for references in [u64(0), 1, 3] {
			for failures in 0 .. 4 {
				for available in [false, true] {
					for remove_vm in [false, true] {
						gpu.available(true)
						mut pt := pgtable.UatPgtable{}
						mut vm := mmu.UatContext{id: 1, vm_id: 1, pgtable: &pt}
						mut file := GpuFile{vms: [&vm]}
						file.queues.flags |= .noslices
						file.g13_queues.flags |= .noslices
						mut request := queue_request(ioctl.asahi_priority_low, ioctl.asahi_queue_cap_render)
						gpu.quarantine_queue()
						assert file.ioctl_queue_create(&request) == -12 && request.queue_id == 0
						assert file.queues.len == 0 && file.g13_queues.len == 1
						orphan_id := file.g13_queues[0].queue_id
						mut orphan := unsafe { file.g13_queues[0].resources }
						orphan.failures = failures
						for _ in 0 .. int(references) { orphan.retain_file_reference() }
						// A successfully published neighbor retains the same VM and
						// has accepted work. Its identity is never an orphan.
						assert file.ioctl_queue_create(&request) == 0
						logical := file.queues[0]
						mut neighbor_resources := unsafe { file.g13_queues[1].resources }
						key := u64(0x6000_0000 + cycle)
						file_map[key] = unsafe { &file }
						// An idle published queue is retained by its logical name,
						// independently of submission reference counts.
						orphan.retain_file_reference()
						reap_open_detached_g13_queues()
						assert neighbor_resources.calls == 0 && !neighbor_resources.released
						assert orphan.calls == 0 && file.g13_queues.len == 2
						orphan.release_file_reference()
						neighbor_resources.retain_file_reference()
						vm.queue = neighbor_resources
						vm.inflight = 7
						file.next_queue_id = orphan_id
						assert (file.allocate_queue_id_locked() or { panic('retained ID') }) == 3
						if remove_vm {
							assert file.ioctl_vm_destroy(&ioctl.DrmAsahiVmDestroy{vm_id: 1}) == 0
						}
						gpu.available(available)
						reap_open_detached_g13_queues()
						if references != 0 {
							assert orphan.calls == 0 && !orphan.released && file.g13_queues.len == 2
						}
						for _ in 0 .. int(references) { orphan.release_file_reference() }
						gpu.available(true)
						orphan_reaping_file = unsafe { &file }
						gpu.watch_queue_release(check_orphan_release_locks)
						for _ in 0 .. failures + 2 { reap_open_detached_g13_queues() }
						gpu.watch_queue_release(unsafe { nil })
						assert orphan.released && !neighbor_resources.released && neighbor_resources.calls == 0
						assert file.g13_queues.len == 1 && file.queues.len == 1 && !vm.destroyed
						assert voidptr(file.g13_queues[0].resources) == voidptr(neighbor_resources)
						file.next_queue_id = orphan_id
						assert (file.allocate_queue_id_locked() or { panic('released ID') }) == orphan_id
						// Detached names still have logical owners while accepted
						// work retains them. The orphan reaper must skip those too.
						assert file.ioctl_queue_destroy(&ioctl.DrmAsahiQueueDestroy{queue_id: request.queue_id}) == 0
						reap_open_detached_g13_queues()
						assert logical.detached && !logical.destroyed && neighbor_resources.calls == 0
						neighbor_resources.release_file_reference()
						vm.inflight = 0
						reap_open_detached_g13_queues()
						assert logical.destroyed && neighbor_resources.released && file.g13_queues.len == 0
						assert vm.destroyed == remove_vm
						file_map.delete(key)
						assert file.close() && vm.destroyed && gpu.active_queues() == 0
						unsafe { free(logical) }
						cases++
					}
				}
			}
		}
	}
	// A failed constructor can be the last physical VM owner. Successful
	// retry must remove that record before the same worker retires the VM.
	for cycle in 0 .. 200 {
		mut pt := pgtable.UatPgtable{}
		mut vm := mmu.UatContext{id: 1, vm_id: 1, pgtable: &pt}
		mut file := GpuFile{vms: [&vm]}
		mut request := queue_request(ioctl.asahi_priority_medium, ioctl.asahi_queue_cap_compute)
		gpu.quarantine_queue()
		assert file.ioctl_queue_create(&request) == -12
		resources := file.g13_queues[0].resources
		assert file.ioctl_vm_destroy(&ioctl.DrmAsahiVmDestroy{vm_id: 1}) == 0
		key := u64(0x6100_0000 + cycle)
		file_map[key] = unsafe { &file }
		for _ in 0 .. 2 {
			reap_open_detached_g13_queues()
			assert file.g13_queues.len == 1 && !vm.destroyed && !resources.released
		}
		reap_open_detached_g13_queues()
		assert file.g13_queues.len == 0 && file.vms.len == 0 && vm.destroyed && resources.released
		file_map.delete(key)
		assert file.close() && gpu.active_queues() == 0
	}
	// Interleaved published/failed graphs exercise reverse array deletion,
	// partial progress and preservation of every surviving logical owner.
	for cycle in 0 .. 50 {
		mut vm := mmu.UatContext{id: 1, vm_id: 1}
		mut file := GpuFile{vms: [&vm]}
		file.queues.flags |= .noslices
		file.g13_queues.flags |= .noslices
		for index in 0 .. 4 {
			mut request := queue_request(ioctl.asahi_priority_low, ioctl.asahi_queue_cap_render)
			gpu.quarantine_queue()
			assert file.ioctl_queue_create(&request) == -12
			mut resources := unsafe { file.g13_queues.last().resources }
			resources.failures = index % 3
			assert file.ioctl_queue_create(&request) == 0 && request.queue_id == u32(index * 2 + 2)
		}
		key := u64(0x6200_0000 + cycle)
		file_map[key] = unsafe { &file }
		for _ in 0 .. 4 { reap_open_detached_g13_queues() }
		assert file.g13_queues.len == 4 && file.queues.len == 4 && !vm.destroyed
		for index, ownership in file.g13_queues {
			assert ownership.queue_id == u32(index * 2 + 2) && ownership.resources.calls == 0
		}
		file_map.delete(key)
		close_priority_file(mut file)
		assert vm.destroyed && gpu.active_queues() == 0
	}
	// Firmware stop may have released physical backing while captured
	// references still point to retained metadata. Do not drop their owner.
	gpu.set_running(false)
	mut vm := mmu.UatContext{id: 1, vm_id: 1}
	mut stopped := gpu.G13QueueResources{queue_id: 7, released: true}
	stopped.retain_file_reference()
	mut file := GpuFile{vms: [&vm], g13_queues: [G13QueueOwnership{queue_id: 7, vm_id: 1, resources: &stopped}]}
	assert file.ioctl_vm_destroy(&ioctl.DrmAsahiVmDestroy{vm_id: 1}) == 0
	file_map[99] = unsafe { &file }
	reap_open_detached_g13_queues()
	assert file.g13_queues.len == 1 && !vm.destroyed && stopped.calls == 0
	stopped.release_file_reference()
	reap_open_detached_g13_queues()
	assert file.g13_queues.len == 0 && vm.destroyed && stopped.calls == 1
	file_map.delete(u64(99))
	assert file.close() && orphan_release_checks > 0
	gpu.set_running(true)
	println('G13 failed queue retry: ${cases} ownership cases, 200 final-VM-owner retries, 50 interleaved arrays, visible/detached neighbors, references, unrelated VM pins, invalidation retry, unavailable managers, ID reuse, registry/file locks and stopped metadata passed')
}
